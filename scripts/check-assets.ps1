<#
.SYNOPSIS
  check-assets.ps1 — 配布する共有ペイロード <Share> を公開前に機械チェックする

.DESCRIPTION
  個人ファイル・無視されうる設定キー・壊れた JSON が「配布されてしまう」状態かを自動判定する。
  対話 TUI が必要な項目（trust 承認・/memory・/status の確認など）は対象外（手で確認）。

  判定基準（README 隔離方式 / 案1 対応）― 検査対象の「層」で基準が変わる:
    追跡基準（対象が git リポジトリのルート = 開発者の作業ツリー）:
      - tracked            → FAIL（clone に含まれ参照側へ漏れる / payload に乗る）
      - untracked で実在   → WARN（gitignore 済みで配布はされないが掃除推奨）
      - 不在               → PASS
    実体基準（対象が非 git = publish 時に取り出した payload の実体）:
      - 実在               → FAIL（実際に配布される中身なので追跡状態は無関係）

  名前の照合（2-c 成果物クラス・2-c' *\evals\results\・3. の E 区分の env キー）は二段階で、照合と判定を分けている:
    照合: まず完全一致（大文字小文字を区別）、一致しなければ ASCII（A〜Z）だけを小文字へ畳んだ同士で比べ、
          「完全一致 / 大文字小文字だけ違う / 不一致」に分類する（Get-NameClass）。
    判定: 完全一致は上の基準のまま。大文字小文字だけ違うものは、成果物（2-c / 2-c'）では実体基準（payload）で FAIL、
          追跡基準（git）で WARN、env キー（3.）では層によらず WARN。区別する OS では正当な別物でありうるが、区別しない
          Windows では .gitignore をすり抜けた成果物でありうる。publish-share は FAIL でしか止まらない（WARN は確認
          プロンプトを経て公開まで進む）ため、配布する実体では止め、開発中の作業ツリーでは人の確認に回す。対応は各節の判定表。

  FAIL が1件以上で終了コード 1、なければ 0（CI 利用可）。

.PARAMETER Payload
  実体基準を強制する（publish-share から payload を検査する時に使う）。

.EXAMPLE
  .\check-assets.ps1 -Share C:\path\to\share
#>
param(
  [Parameter(Mandatory = $true)][string]$Share,
  [switch]$Payload
)

if (-not (Test-Path -PathType Container $Share)) { Write-Error "ディレクトリが見つかりません: $Share"; exit 2 }
$Share = (Resolve-Path $Share).Path

$script:fail = 0
function Pass($m) { Write-Host "  [PASS] $m" }
function Bad($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red;    $script:fail = 1 }
function Warn($m) { Write-Host "  [WARN] $m" -ForegroundColor Yellow }

# 層の判定。
#
# ⚠ rev-parse --is-inside-work-tree を使ってはいけない。祖先方向に .git を探すため、
#    対象自身がリポジトリでなくても「どこかの repo 配下」なら真を返す。publish-share は
#    payload を %TEMP% へ展開して検査するので、%TEMP% が worktree 配下のマシンでは payload が
#    追跡基準で検査され、成果物の混入も統制ファイルの不在も FAIL から WARN へ退化する
#    ＝ ゲートの fail-open。
#    → 対象が「リポジトリのルートそのもの」の時だけ追跡基準を使う（--show-prefix が空）。
#    → publish-share からは -Payload で実体基準を明示強制する（呼び出し側は層を知っている）。
#    bash 版と同じ判定に揃えること。
$isGit = $false
if (-not $Payload) {
  $prefix = (git -C $Share rev-parse --show-prefix 2>$null)
  if ($LASTEXITCODE -eq 0 -and [string]::IsNullOrWhiteSpace($prefix)) { $isGit = $true }
}

function Test-Tracked($rel) {
  git -C $Share ls-files --error-unmatch $rel 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

# 個人ファイル（tracked=FAIL / untracked実在=WARN / 不在=PASS、非gitは実在=FAIL）を判定
function Check-Personal($rel, $label) {
  $abs = Join-Path $Share $rel
  if ($isGit) {
    if (Test-Tracked $rel) {
      Bad "$label が Git 追跡されている（clone に含まれ参照側へ漏れる）。git rm --cached して .gitignore へ"
    } elseif (Test-Path $abs) {
      Warn "$label が実在するが未追跡（配布はされない。掃除推奨）"
    } else {
      Pass "$label なし"
    }
  } else {
    if (Test-Path $abs) {
      Bad "$label がある（非 git のためコピー展開でそのまま配布される）。削除する"
    } else {
      Pass "$label なし"
    }
  }
}

Write-Host ("[check-assets] 対象: $Share（" + $(if ($isGit) { 'リポジトリのルート: 追跡基準' } else { 'payload / 非リポジトリ: 実体基準' }) + "）")

# 1. 個人ファイル CLAUDE.local.md
Check-Personal 'CLAUDE.local.md'         'CLAUDE.local.md'
Check-Personal '.claude\CLAUDE.local.md' '.claude\CLAUDE.local.md'

# 2. settings.local.json
Check-Personal '.claude\settings.local.json' '.claude\settings.local.json'

# 2-b. ランチャーの個人実体（テンプレから利用者が作る。配布してはならない）
Check-Personal '.claude\custom.env'          '.claude\custom.env'
Check-Personal '.claude\option-settings.sh'  '.claude\option-settings.sh'
Check-Personal '.claude\option-settings.ps1' '.claude\option-settings.ps1'

# 2-c. セッション成果物・作業一時物の混入（内部レポートの公開リポ流出を止める最後の砦）
#      判定は個人ファイル（Check-Personal）と同じ二層基準:
#        - 非 git（= publish 時に取り出した payload 実体）→ 実在＝FAIL。
#        - git リポジトリ（= 作業ツリーへの手動実行）→ 追跡されていれば FAIL / 未追跡の実在は WARN。
#          実体基準にすると work/ を持つ通常の開発マシンで常時 FAIL し、ゲートの信号価値が死ぬ。
#      名前は二段階で照合し（下の「名前の照合」）、大文字小文字だけが違うものは payload で FAIL、git で WARN にする（判定表）。
#
# ---- 名前の照合（チェックロジック）。分類を返すだけで、判定（PASS / WARN / FAIL と文言）は各節の判定表に置く ----
#   1) 完全一致（大文字小文字を区別）  2) 一致しなければ ASCII（A〜Z）だけを小文字へ畳んだ同士で比べる
#   → exact（完全一致）/ case（大文字小文字だけが違う）/ none（不一致）。bash 版の name_class と同じ規則。
# ⚠ 存在検査（Test-Path .claude\reports）で照合しない。Windows ではそれ自体が大文字小文字を無視して真になり、
#    区別する OS とで判定が割れる。エントリ名・追跡パスを列挙して文字列で比べる（publish-plugin の
#    大文字小文字違い検査と同じ方式）。
# ⚠ 比較は [string]::Equals(…, Ordinal)。-ceq は culture 依存でゼロ幅文字を無視する（pwsh 7.4 で実測）ため bash の == と割れる。
# ⚠ 畳むのは A〜Z だけ。ToLowerInvariant() / -ieq / -like は非 ASCII も畳む（K と KELVIN SIGN 等）ため bash 版の
#    LC_ALL=C の tr と割れる。String.Replace(char, char) は序数比較なので A〜Z の 26 文字だけを置き換える。
function Fold-Ascii([string]$s) {
  foreach ($u in 65..90) { $s = $s.Replace([char]$u, [char]($u + 32)) }
  return $s
}
function Get-NameClass([string]$actual, [string]$want) {
  if ([string]::Equals($actual, $want, [StringComparison]::Ordinal)) { return 'exact' }
  if ([string]::Equals((Fold-Ascii $actual), (Fold-Ascii $want), [StringComparison]::Ordinal)) { return 'case' }
  return 'none'
}
# 候補 $cands を期待する名前 $want と照合し、exact / case になった候補を返す（bash 版の match_cands）
function Match-Names([string[]]$cands, [string]$want) {
  $r = @{ Exact = @(); Case = @() }
  foreach ($c in $cands) {
    $k = Get-NameClass $c $want
    if ($k -ceq 'exact') { $r.Exact += $c } elseif ($k -ceq 'case') { $r.Case += $c }
  }
  return $r
}
# bash 版の LC_ALL=C sort と同じ順に並べる（パスは / 区切りの形で並べること。\ は英字より後ろに来る）
function Sort-Ordinal([string[]]$a) {
  if (-not $a) { return }
  $k = [string[]]$a.Clone()
  [Array]::Sort($k, [StringComparer]::Ordinal)
  $k
}
$claudeDir = Join-Path $Share '.claude'
# 追跡されている .claude 配下のパス（git 層のみ・/ 区切り・git の順）。2-c / 2-c' が使う
$trackedClaude = @()
if ($isGit) { $trackedClaude = @(((git -C $Share ls-files -z -- .claude 2>$null) -join "`n") -split "`0" | Where-Object { $_ }) }
# 2-c の候補（.claude\<直下の名前>）。追跡: 追跡パスの最初の要素（重複なし・git の順）／実在: 直下のエントリ（序数順）
$topTracked = @()
$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($p in $trackedClaude) {
  $t = if ($p.StartsWith('.claude/', [StringComparison]::Ordinal)) { $p.Substring(8) } else { $p }
  $i = $t.IndexOf([char]'/'); if ($i -ge 0) { $t = $t.Substring(0, $i) }
  $t = ".claude\$t"
  if ($seen.Add($t)) { $topTracked += $t }
}
$topDisk = @()
if (Test-Path -LiteralPath $claudeDir -PathType Container) {
  $topDisk = @(Sort-Ordinal @(Get-ChildItem -Force -LiteralPath $claudeDir -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) |
    ForEach-Object { ".claude\$_" })
}
$layer = if ($isGit) { 'git' } else { 'payload' }

# 大文字小文字だけが違うパスの判定（2-c / 2-c' の判定表が共有する文言。bash 版の verdict_case）。$src=層:出どころ
#   payload は FAIL（publish-share は FAIL でしか止まらないので、WARN では公開まで進む）、git は WARN（開発中の確認用）。
function Verdict-Case([string]$src, [string]$path, [string]$cls) {
  $same = "（$cls と同一視される OS がある。"
  if ($src -ceq 'git:tracked') { Warn "大文字小文字だけが違う成果物クラスらしきパスが Git 追跡されている（payload に乗る）: $path${same}意図したものか確認すること）" }
  elseif ($src -ceq 'git:disk') { Warn "大文字小文字だけが違う成果物クラスらしきパスが実在する（未追跡。配布はされない）: $path${same}意図したものか確認すること）" }
  else { Bad "大文字小文字だけが違う成果物クラスらしきパスが配布ペイロードに含まれている: $path${same}公開前に名前を直すか除外すること）" }
}
# 2-c の判定表（照合の分類 → 判定）。bash 版の verdict_artifact と同じ表。1 クラスにつき判定は 1 つで、上の行ほど優先する:
#   層:出どころ:分類          判定
#   git:tracked:exact         FAIL  Git 追跡されている（payload に乗る）
#   git:tracked:case          WARN  大文字小文字だけが違うパスが Git 追跡されている（パスごとに 1 行）
#   git:disk:exact            WARN  実在するが未追跡（配布はされない）
#   git:disk:case             WARN  大文字小文字だけが違うパスが実在する（未追跡）
#   payload:disk:exact        FAIL  配布ペイロードに含まれている
#   payload:disk:case         FAIL  大文字小文字だけが違うパスが配布ペイロードに含まれている（パスごとに 1 行）
#   none                      PASS  なし
function Verdict-Artifact([string]$key, [string]$cls, [string[]]$paths) {
  if ($key -ceq 'git:tracked:exact') { Bad "$cls が Git 追跡されている（payload に乗り配布される）。git rm --cached して .gitignore へ" }
  elseif ($key -ceq 'git:disk:exact') { Warn "$cls が実在するが未追跡（配布はされない。掃除推奨）" }
  elseif ($key -ceq 'payload:disk:exact') { Bad "$cls が配布ペイロードに含まれている（内部成果物は配布しない）。grooming 済みの ref を publish すること" }
  elseif ($key.EndsWith(':case', [StringComparison]::Ordinal)) { foreach ($p in $paths) { Verdict-Case $key.Substring(0, $key.Length - 5) $p $cls } }
  else { Pass "$cls なし" }
}

# 成果物クラスの正本リストは本配列。root/.claude 双方の .gitignore はこれに追随させること。
# 位置が固定でないクラス（evals\results\）は直後の 2-c' が正本。
#   .claude\worktrees            … --worktree / EnterWorktree が作る git worktree（公式も .gitignore を推奨）
#   .claude\scheduled_tasks.json … 永続化したスケジュールタスク（作成したフォルダでしか動かない個人状態）
foreach ($artifact in @('.claude\reports', '.claude\work', '.claude\workspace', '.claude\plans',
                        '.claude\agent-memory-local', '.claude\work_instructions.txt',
                        '.claude\.bat-shadow', '.claude\worktrees', '.claude\scheduled_tasks.json')) {
  $key = 'none'; $hits = @()
  if ($isGit) {
    $m = Match-Names $topTracked $artifact
    if ($m.Exact.Count -gt 0) { $key = 'git:tracked:exact' }
    elseif ($m.Case.Count -gt 0) { $key = 'git:tracked:case'; $hits = $m.Case }
  }
  if ($key -ceq 'none') {
    $m = Match-Names $topDisk $artifact
    if ($m.Exact.Count -gt 0) { $key = "${layer}:disk:exact" }
    elseif ($m.Case.Count -gt 0) { $key = "${layer}:disk:case"; $hits = $m.Case }
  }
  Verdict-Artifact $key $artifact $hits
}

# 2-c'. 置き場所が固定でない成果物クラス: claude plugin eval の結果（評価した plugin / skill の evals\results\。v2.1.269〜）
#       bash 版と対称。追跡パス（git 層）と .claude 配下のディレクトリ（両層）を列挙し、evals/results の 2 要素を
#       二段階で照合する。追跡パスはファイル名を除いたディレクトリ部分のどこか（旧 pathspec ':(glob).claude/**/evals/results/**'
#       と同じ範囲）、ディレクトリは末尾の 2 要素（旧 Name / Parent.Name の比較と同じ）を見る。
#       ⚠ .claude\worktrees（丸ごとの git チェックアウト。2-c で別途判定する）には降りない（bash 版の find -prune と対称。
#          名前は完全一致で除外）。降りると遅いうえ、worktree 内の evals\results を payload の成果物と誤って数える。
$evrWant = 'evals/results'; $evrCls = '*\evals\results\'
$sep = [System.IO.Path]::DirectorySeparatorChar
# $path（/ 区切り）の分類と、一致した …/results までのディレクトリを返す。$isDir: 末尾の 2 要素 / それ以外: ディレクトリ部分のどこか
function Get-EvrClass([string]$path, [bool]$isDir) {
  $p = $path.Split([char]'/')
  $n = $p.Count
  if ($isDir) { $lo = $n - 2 } else { $lo = 1; $n = $n - 1 }
  if ($lo -lt 1) { $lo = 1 }                       # $p[0] は .claude
  $best = 'none'; $dir = ''
  for ($i = $lo; $i + 1 -lt $n; $i++) {
    $c = Get-NameClass ($p[$i] + '/' + $p[$i + 1]) $evrWant
    if ($c -ceq 'exact') { $best = 'exact'; $dir = ($p[0..($i + 1)] -join '/'); break }
    if ($c -ceq 'case' -and $best -ceq 'none') { $best = 'case'; $dir = ($p[0..($i + 1)] -join '/') }
  }
  return @{ Class = $best; Dir = $dir }
}
# -like は候補を絞るだけ（作業ツリーの .claude\work 等は数千ディレクトリになり、全件を照合すると遅い）。ASCII の
# 大文字小文字を畳む一致は必ず含むので取りこぼさず、分類はこのあと Get-EvrClass が行う（bash 版の find -iname と同じ役割）。
$evrDirs = @()
if (Test-Path -LiteralPath $claudeDir -PathType Container) {
  $evrDirs = @(Sort-Ordinal @(Get-ChildItem -Directory -Force -LiteralPath $claudeDir -ErrorAction SilentlyContinue |
    Where-Object { -not [string]::Equals($_.Name, 'worktrees', [StringComparison]::Ordinal) } |
    ForEach-Object { $_; Get-ChildItem -Recurse -Directory -Force -LiteralPath $_.FullName -ErrorAction SilentlyContinue } |
    Where-Object { $_.Name -like 'results' } |
    ForEach-Object { $_.FullName.Substring($Share.Length + 1) -replace '\\', '/' }))
}
# 2-c' の判定表（照合の分類 → 判定）。bash 版の verdict_evr と同じ表・同じ優先順位で判定は 1 つ。列挙は 5 件まで:
#   git:tracked:exact    FAIL  Git 追跡されている（追跡ファイルを列挙）
#   git:tracked:case     WARN  大文字小文字だけが違うパスが Git 追跡されている（…\results のディレクトリごとに 1 行）
#   git:disk:exact       WARN  実在するが未追跡
#   git:disk:case        WARN  大文字小文字だけが違うパスが実在する（未追跡）
#   payload:disk:exact   FAIL  配布ペイロードに含まれている（ディレクトリを列挙）
#   payload:disk:case    FAIL  大文字小文字だけが違うパスが配布ペイロードに含まれている（…\results のディレクトリごとに 1 行）
#   none                 PASS  なし
function Verdict-Evr([string]$key, [string[]]$paths) {
  if ($key -ceq 'git:tracked:exact') {
    Bad 'plugin eval の結果（*\evals\results\）が Git 追跡されている（payload に乗り配布される）。git rm -r --cached して .gitignore へ:'
    foreach ($p in $paths) { Write-Host "         $p" }
  } elseif ($key -ceq 'git:disk:exact') {
    Warn 'plugin eval の結果（*\evals\results\）が実在するが未追跡（配布はされない。掃除推奨）'
  } elseif ($key -ceq 'payload:disk:exact') {
    Bad 'plugin eval の結果（*\evals\results\）が配布ペイロードに含まれている:'
    foreach ($p in $paths) { Write-Host "         $($p.Replace('/', $sep))" }
  } elseif ($key.EndsWith(':case', [StringComparison]::Ordinal)) {
    foreach ($p in $paths) { Verdict-Case $key.Substring(0, $key.Length - 5) $p.Replace('/', $sep) $evrCls }
  } else {
    Pass 'plugin eval の結果（*\evals\results\）なし'
  }
}
$key = 'none'; $hits = @()
if ($isGit) {
  $ex = @(); $cs = @()
  foreach ($p in $trackedClaude) {
    $r = Get-EvrClass $p $false
    if ($r.Class -ceq 'exact') { $ex += $p }
    elseif ($r.Class -ceq 'case' -and   # git の順なので同じディレクトリは隣接する
            ($cs.Count -eq 0 -or -not [string]::Equals($cs[-1], $r.Dir, [StringComparison]::Ordinal))) { $cs += $r.Dir }
  }
  if ($ex.Count -gt 0) { $key = 'git:tracked:exact'; $hits = @($ex | Select-Object -First 5) }
  elseif ($cs.Count -gt 0) { $key = 'git:tracked:case'; $hits = @($cs | Select-Object -First 5) }
}
if ($key -ceq 'none') {
  $ex = @(); $cs = @()
  foreach ($p in $evrDirs) {
    $r = Get-EvrClass $p $true
    if ($r.Class -ceq 'exact') { $ex += $p } elseif ($r.Class -ceq 'case') { $cs += $p }
  }
  if ($ex.Count -gt 0) { $key = "${layer}:disk:exact"; $hits = @($ex | Select-Object -First 5) }
  elseif ($cs.Count -gt 0) { $key = "${layer}:disk:case"; $hits = @($cs | Select-Object -First 5) }
}
Verdict-Evr $key $hits

# 2-d. 配布先の統制ファイル（payload に無いと配布先から「消える」クラス）
#      publish-share のミラーは payload に無いものを削除するため、これらを欠いた ref を
#      publish すると配布先の除外設定・改行保護が黙って失われる（CR-1 の逆行）。
#      判定は 2-c と同じ二層基準（非 git = 実際に publish する payload → 不在は FAIL。
#      git = 開発中の作業ツリー → 不在は WARN）。
foreach ($guard in @('.claude\.gitignore', '.claude\.gitattributes')) {
  if (Test-Path -PathType Leaf (Join-Path $Share $guard)) {
    Pass "$guard あり（配布先の統制ファイル）"
  } elseif ($isGit) {
    Warn "$guard が無い（publish 前に必要。この状態のまま publish すると配布先の除外設定・改行保護が失われる）"
  } else {
    Bad "$guard が payload に無い。このまま publish すると配布先の除外設定・改行保護が失われる"
  }
}

# 「実際に配布されるファイル」の列挙。2-e / 2-f はこれを走査する。
#
# ⚠ 二層基準をここにも適用すること。作業ツリーに対して単純に再帰列挙すると、gitignored で
#    payload には乗らない .claude\work\ 等まで検査対象になり、通常の開発マシンで常時 FAIL する
#    （IM-2 でゲートのオオカミ少年化として指摘された故障をそのまま再発させる）。bash 版と対称。
function Get-PayloadFiles {
  if ($isGit) {
    (git -C $Share ls-files -- .claude) | Where-Object { $_ } | ForEach-Object { $_ -replace '/', '\' }
  } else {
    $base = (Join-Path $Share '.claude')
    if (Test-Path $base) {
      Get-ChildItem -Recurse -File -LiteralPath $base |
        ForEach-Object { $_.FullName.Substring($Share.Length + 1) }
    }
  }
}
$payloadFiles = @(Get-PayloadFiles)

# 2-e. 配布物の本文に「環境固有の絶対パス」が埋まっていないか。
#      payload は公開リポへ配る。開発者マシンのディレクトリ構成が載ると、(1) ローカルの FS
#      レイアウトを公開してしまい、(2) 利用者のマシンには存在しないパスを指示することになる。
#      説明用の例示を弾ききれないので WARN 止まり（人間が判断する）。
$absPattern = '(^|[^A-Za-z])[A-Za-z]:\\[A-Za-z]|(^|[^A-Za-z])/home/[a-z][a-z0-9_-]*/|/Users/[a-z][a-z0-9_-]*/'
# 製品が規定する公式パス（managed-settings.json の配置先、Git for Windows の既定）は環境固有ではないので除く。
# 行から公式パスの部分文字列だけを取り除き、残りを絶対パスのパターンで判定する（行ごと除外すると、同じ行にある
# 開発者固有パスを見逃す）。bash 版と同じ表・同じ判定にすること:
#   - -creplace / -cmatch で大文字小文字を区別する（bash の grep -E / sed -E と同じ。-match は区別しない）
#   - 除外するのは skills\win-file-encoding\ 配下だけ（bash 版の */skills/win-file-encoding/* と同じ。
#     名前に win-file-encoding を含むだけのファイル（rules\win-file-encoding.md 等）は検査する）
$absAllow = '[A-Za-z]:\\Program Files( \(x86\))?\\(ClaudeCode|Git)\\'
$absHits = $payloadFiles |
  Where-Object { $_ -cnotlike '*\skills\win-file-encoding\*' } |
  Where-Object {
    $lines = Get-Content -LiteralPath (Join-Path $Share $_) -Encoding UTF8 -ErrorAction SilentlyContinue
    @($lines | Where-Object { ($_ -creplace $absAllow, '') -cmatch $absPattern }).Count -gt 0
  }
if ($absHits) {
  Warn "配布物に環境固有の絶対パスらしき記述がある（公開前に確認すること）:"
  $absHits | ForEach-Object { Write-Host "         $_" }
} else {
  Pass "配布物に環境固有の絶対パスなし"
}

# 2-f. 配布される .ps1 が UTF-8 BOM を保持しているか。
#      BOM が無いと Windows PowerShell 5.1 が CP932 と誤読して日本語が化ける。BOM は「中身」なので
#      .gitattributes では守れず、一度落ちると復元されない（convert_encoding.py --to-win が落とす）。
$noBom = $false
$payloadFiles | Where-Object { $_ -like '*.ps1' -or $_ -like '*.ps1.template' } | ForEach-Object {
  $head = [System.IO.File]::ReadAllBytes((Join-Path $Share $_)) | Select-Object -First 3
  if (-not ($head.Count -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)) {
    Bad "$_ に UTF-8 BOM が無い（Windows PowerShell 5.1 で日本語が化ける）"
    $noBom = $true
  }
}
if (-not $noBom) { Pass "配布される .ps1 は全て BOM 付き" }

# 3. settings.json の JSON 構文 ＋ project（.claude\settings.json）では効かないキーの検出
#    区分・根拠は bash 版 3. と同じ（U / M / E）。表を更新したら bash 版の _U_KEYS / _M_KEYS / _ENV_RE も同時に更新する。
#    E 区分のキー名は 2-c と同じ二段階で照合する（$envRe に完全一致 → A〜Z だけ畳んだ同士で一致。Get-EnvClass）。
#    判定は、完全一致 → 従来の WARN、大文字小文字だけ違う（systemroot 等）→ 「Windows でのみ同一視される」旨の別の WARN。
$uKeys =@('skipDangerousModePermissionPrompt', 'useAutoModeDuringPlan', 'autoMode', 'skipAutoPermissionPrompt',
           'processWrapper', 'pluginConfigs', 'syncClaudeAiSkills', 'syncClaudeAiPlugins',
           'sandbox.allowAppleEvents', 'sandbox.ripgrep', 'sandbox.filesystem.disabled',
           'sandbox.network.strictAllowlist', 'sandbox.network.tlsTerminate',
           'sandbox.credentials.allowPlaintextInject', 'sandbox.credentials.awsPairs', 'sandbox.credentials.sigv4')
# prependPlugins / appendPlugins は Scope 表記こそ User or managed だが --settings でも無視されるので M に置く（bash 版と同じ）
$mKeys = @('prependPlugins', 'appendPlugins',
           'allowManagedPermissionRulesOnly', 'allowManagedHooksOnly', 'allowManagedMcpServersOnly', 'managedMcpServers',
           'strictKnownMarketplaces', 'allowedMarketplaces', 'blockedMarketplaces', 'strictPluginOnlyCustomization',
           'disableSideloadFlags', 'disableCommandPluginSources', 'claudeMd', 'policyHelper', 'allowedProviders',
           'deniedModels', 'availableModelsMatch', 'requiredMinimumVersion', 'requiredMaximumVersion', 'sshHostAllowlist',
           'channelsEnabled', 'allowedChannelPlugins',
           'sandbox.bwrapPath', 'sandbox.socatPath', 'sandbox.filesystem.allowManagedReadPathsOnly',
           'sandbox.network.allowManagedDomainsOnly')
# ⚠ 二段階目は $envRe 自体も A〜Z を畳んで照合する。畳めるのは \D \S \W \B 等の「大文字で意味が変わるエスケープ」を
#    含まないから。追加するときもリテラルと . * ( ) | ? だけで書くこと（bash 版の _ENV_RE も同じ）。
$envRe ='^(CLAUDE_CONFIG_DIR|CLAUDE_CODE_TMPDIR|HOME|TMPDIR|TMP|TEMP|XDG_.*|SystemRoot|ComSpec|ProgramData|LOCALAPPDATA|PATHEXT|PSModulePath|ProgramFiles.*|CommonProgramFiles.*|ALLUSERSPROFILE|SystemDrive|CLAUDE_CODE_ENABLE_TELEMETRY|CLAUDE_CODE_ENHANCED_TELEMETRY_BETA|ENABLE_ENHANCED_TELEMETRY_BETA|OTEL_(LOGS|METRICS|TRACES)_EXPORTER|OTEL_LOG_.*|OTEL_EXPORTER_OTLP_(.*_)?(ENDPOINT|HEADERS|PROTOCOL|CERTIFICATE|CLIENT_KEY|INSECURE)|OTEL_EXPORTER_PROMETHEUS_(HOST|PORT)|ENABLE_BETA_TRACING_DETAILED|BETA_TRACING_ENDPOINT|CLAUDE_CODE_PROCESS_WRAPPER|CLAUDE_CODE_SYNC_(SKILLS|PLUGINS)|CLAUDE_CODE_PLUGIN_(CACHE|SEED)_DIR|CLAUDE_CODE_USER_DIALOG_TIMEOUT_MS|CLAUDE_AFK_(TIMEOUT|COUNTDOWN)_MS|CLAUDE_CODE_DISABLE_(ATTACHMENTS|FILE_MENTIONS)|CLAUDE_CODE_PROJECT_DIR_NAME|CLAUDE_CODE_RESTRICTED)$'
# キーパス（a.b.c）が JSON に存在するか。bash 版の has() と同じ意味（大文字小文字を区別する）。
# ⚠ [pscustomobject] は PSObject の別名でほぼ何にでも一致するため、完全修飾の型名で判定する。
function Test-JsonPath($obj, [string]$path) {
  $cur = $obj
  foreach ($k in $path.Split('.')) {
    if (-not ($cur -is [System.Management.Automation.PSCustomObject]) -or
        -not ($cur.PSObject.Properties.Name -ccontains $k)) { return $false }
    $cur = $cur.$k
  }
  return $true
}
# E 区分の照合（二段階。bash 版の python の env_class と同じ）。-match は大文字小文字を区別せず非 ASCII も畳むので使わない
$envReFold = Fold-Ascii $envRe
function Get-EnvClass([string]$k) {
  if ($k -cmatch $envRe) { return 'exact' }
  if ((Fold-Ascii $k) -cmatch $envReFold) { return 'case' }
  return 'none'
}
$settings = Join-Path $Share '.claude\settings.json'
# ⚠ 先頭の UTF-8 BOM は専用メッセージで FAIL にする（JSON 構文・キーの検査には進まない。bash 版と同じ）。
#    Claude Code が BOM 付きの settings.json を読める保証が無い。かつては本版（Get-Content -Encoding UTF8 が
#    BOM を剥がす）が PASS、bash 版（python の utf-8）が「不正な JSON」で FAIL と判定が割れていた。
$settingsBom = $false
if (Test-Path -LiteralPath $settings -PathType Leaf) {
  $head = [System.IO.File]::ReadAllBytes($settings) | Select-Object -First 3
  $settingsBom = ($head.Count -eq 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)
}
if ($settingsBom) {
  Bad "settings.json の先頭に UTF-8 BOM がある（Claude Code が BOM 付きを読める保証が無い）。BOM なしの UTF-8 で保存し直すこと（JSON 構文とキーの検査は BOM を外してから行う）"
} elseif (Test-Path $settings) {
  $json = $null
  # ⚠ -Encoding UTF8 を明示する。Windows PowerShell 5.1 は BOM なし UTF-8 を ANSI（CP932）で読み、
  #    日本語を含む正しい JSON を「不正な JSON」と誤判定する（実測）。bash 版の encoding='utf-8' と対称。
  try { $json = Get-Content -LiteralPath $settings -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $json = $null }
  if ($null -eq $json) {
    Bad "settings.json が不正な JSON（claude doctor / /doctor でも検出される）"
  } else {
    Pass "settings.json は valid JSON"
    $uHits = @($uKeys | Where-Object { Test-JsonPath $json $_ })
    foreach ($src in @($json.permissions, $json)) {
      if ((Test-JsonPath $src 'defaultMode') -and (@('auto', 'bypassPermissions') -ccontains $src.defaultMode)) {
        $uHits = @("defaultMode:$($src.defaultMode)") + $uHits
        break
      }
    }
    $mHits = @($mKeys | Where-Object { Test-JsonPath $json $_ })
    $eHits = @(); $eCase = @()
    if ($json.env -is [System.Management.Automation.PSCustomObject]) {
      foreach ($k in @($json.env.PSObject.Properties.Name)) {
        $c = Get-EnvClass $k
        if ($c -ceq 'exact') { $eHits += $k } elseif ($c -ceq 'case') { $eCase += $k }
      }
    }
    # 判定（E 区分は 完全一致 → 従来の WARN／大文字小文字だけ違う → 別文言の WARN）
    if ($uHits.Count -gt 0) { Warn ("方法 A（.claude\ を project として配置）では無視されるキー: " + ($uHits -join ' ') + "（方法 B / clean-test-env の --settings 結合では有効になり、配布方式で挙動が割れる。各自に効かせるなら ~/.claude/settings.json へ）") }
    if ($mHits.Count -gt 0) { Warn ("project でも --settings でも無視されるキー: " + ($mHits -join ' ') + "（managed 専用。prependPlugins / appendPlugins だけは条件付きで user も可。組織の managed settings で配る）") }
    if ($eHits.Count -gt 0) { Warn ("env で project / local からは設定できない変数: " + ($eHits -join ' ') + "（シェル・~/.claude/settings.json・managed で設定する。テレメトリの off 値 none / 0 だけは例外。CLAUDE_CODE_PROJECT_DIR_NAME / CLAUDE_CODE_RESTRICTED は起動環境からしか読まれない）") }
    if ($eCase.Count -gt 0) { Warn ("env で project / local からは設定できない変数と大文字小文字だけが違う変数: " + ($eCase -join ' ') + "（Windows でのみ同一視される。環境変数名の大文字小文字を区別しないのは Windows だけで、Windows では設定できない変数と同じ扱いになりうる。意図したものか確認すること）") }
    if (($uHits.Count + $mHits.Count + $eHits.Count + $eCase.Count) -eq 0) { Pass "project で効かないキーなし（settings.json）" }
  }
} else {
  Warn "settings.json が無い（settings を共有しない構成なら問題なし）"
}

# 4. 共有共通ルールの所在（案1 では .claude\CLAUDE.md。ルート CLAUDE.md は README 隔離の対象）
#    不在は FAIL。publish-share のミラーは payload に無いファイルを配布先から削除するため、
#    .claude\CLAUDE.md を持たない ref を publish すると「配布先の共通 CLAUDE.md が消える」。
#    配る構成を採用済みなので、WARN では止められない。
if (Test-Path (Join-Path $Share '.claude\CLAUDE.md')) {
  Pass "共有共通ルール .claude\CLAUDE.md あり（案1 構成）"
} elseif (Test-Path (Join-Path $Share 'CLAUDE.md')) {
  Bad "共有ルールがルート CLAUDE.md にある（.claude\CLAUDE.md が無い）。このまま publish すると配布先の CLAUDE.md が削除される。.claude\CLAUDE.md へ移し、リポ固有情報は README.md へ"
} else {
  Bad "共有共通ルール .claude\CLAUDE.md が無い。このまま publish すると配布先の CLAUDE.md が削除される。grooming 済みの ref を publish すること"
}

# 5. （案1 情報）ルート CLAUDE.md が tracked なら --add-dir+env で参照側へ漏れる旨を通知
if ($isGit -and (Test-Tracked 'CLAUDE.md')) {
  Warn "ルート CLAUDE.md が Git 追跡されている。--add-dir + CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 で参照側にロードされる点に注意（リポ固有情報を含めない）"
}

if ($script:fail -eq 0) {
  Write-Host "[check-assets] 結果: 重大な問題なし（FAIL=0）"
} else {
  Write-Host "[check-assets] 結果: FAIL あり。上記を修正してください"
}
exit $script:fail
