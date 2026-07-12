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
#
# 成果物クラスの正本リストは本配列。root/.claude 双方の .gitignore はこれに追随させること。
foreach ($artifact in @('.claude\reports', '.claude\work', '.claude\workspace', '.claude\plans',
                        '.claude\agent-memory-local', '.claude\work_instructions.txt')) {
  $abs = Join-Path $Share $artifact
  if ($isGit) {
    $tracked = (git -C $Share ls-files -- $artifact 2>$null)
    if ($tracked) {
      Bad "$artifact が Git 追跡されている（payload に乗り配布される）。git rm --cached して .gitignore へ"
    } elseif (Test-Path $abs) {
      Warn "$artifact が実在するが未追跡（配布はされない。掃除推奨）"
    } else {
      Pass "$artifact なし"
    }
  } else {
    if (Test-Path $abs) {
      Bad "$artifact が配布ペイロードに含まれている（内部成果物は配布しない）。grooming 済みの ref を publish すること"
    } else {
      Pass "$artifact なし"
    }
  }
}

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
$absHits = $payloadFiles |
  Where-Object { $_ -notmatch 'win-file-encoding' } |
  Where-Object {
    $raw = Get-Content -Raw -LiteralPath (Join-Path $Share $_) -ErrorAction SilentlyContinue
    $raw -and ($raw -match $absPattern)
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

# 3. settings.json の JSON 構文 ＋ project/local で無視される security キーの検出
$settings = Join-Path $Share '.claude\settings.json'
if (Test-Path $settings) {
  $json = $null
  try { $json = Get-Content $settings -Raw | ConvertFrom-Json } catch { $json = $null }
  if ($null -eq $json) {
    Bad "settings.json が不正な JSON（/doctor でも検出される）"
  } else {
    Pass "settings.json は valid JSON"
    $hits = @()
    # defaultMode は permissions 配下に置くのが正。トップレベルだけを見ると検査が不発になる
    # （bash 版は raw テキストを grep するため、ここが揃っていないと OS で判定が食い違う）。
    if ($json.permissions.defaultMode -eq 'auto' -or $json.defaultMode -eq 'auto') { $hits += 'defaultMode:auto' }
    if ($null -ne $json.skipDangerousModePermissionPrompt)  { $hits += 'skipDangerousModePermissionPrompt' }
    if ($null -ne $json.autoMode)                           { $hits += 'autoMode' }
    if ($null -ne $json.useAutoModeDuringPlan)              { $hits += 'useAutoModeDuringPlan' }
    if ($hits.Count -gt 0) {
      Warn ("project/local では無視される可能性のあるキー: " + ($hits -join ', ') + "（効かせるなら ~/.claude/settings.json へ）")
    } else {
      Pass "project/local 無視キーなし（settings.json）"
    }
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
