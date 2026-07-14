<#
  publish-share.ps1 — 指定 ref の .claude を共有本体 basic_dot_claude へ publish（Sync A・手動ゲート）

  session 開始時の自動同期（refresh / pull --ff-only）とは別物。release-ready な .claude を
  共有本体へ反映する意図的な操作で、publish はここでしか push しない。
  publish 対象は -Ref で明示指定する（既定値は無い）。checkout 不要で任意 ref を publish できる。

  使い方:
    .\scripts\publish-share.ps1 -Ref <ref> [-ShareBody <basic_dot_claude のパス>]
  例:
    .\scripts\publish-share.ps1 -Ref v1.0.0                    # リリースタグを publish
    .\scripts\publish-share.ps1 -Ref chore/groom-as-share      # 指定ブランチを publish（検証 run 等）

  ⚠ -Ref に既定値を持たせない理由: かつて既定は main だったが、未 grooming の ref を
     無自覚に publish する事故（内部レポートの公開リポ流出）を招く。publish する ref は
     毎回意識して選ぶこと。payload に成果物が混入していれば check-assets が FAIL させる。
#>

# Windows PowerShell 5.1 では stderr リダイレクト（*> $null）と $ErrorActionPreference='Stop' の
# 組み合わせで native の stderr が terminating error に化け、ガードの診断と終了コード規約が崩れる
# （実測: ref の打ち間違いで『‼ ref が存在しない』(exit 2) ではなく NativeCommandError の生スタックが出る）。
# 対象シェルを機械で宣言して fail fast させる。
#requires -Version 7
param(
  [Parameter(Mandatory = $true)]
  [string]$Ref,
  [string]$ShareBody = 'C:\cc-workspace\basic_dot_claude'
)
$ErrorActionPreference = 'Stop'

# 開発リポの位置はスクリプトの場所から解決する（CWD に依存させない。別リポジトリ内から
# 実行して、そのリポの .claude を publish してしまう事故を防ぐ）。
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DevRoot = (Resolve-Path (Join-Path $Here '..')).Path
git -C $DevRoot rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "‼ 開発リポジトリが見つからない: $DevRoot"; exit 2 }

# 共有本体の検査: .git が「ディレクトリ」であること（submodule の .git はファイル＝gitlink）。
# かつ、指定パスがそのリポジトリのルートそのものであること。
# これを緩めると、submodule の checkout（例: basic_cc_project\.claude）を配布先に指定でき、
# ミラー処理が gitlink を壊して親リポジトリへ commit/push してしまう。
if (-not (Test-Path -LiteralPath (Join-Path $ShareBody '.git') -PathType Container)) {
  Write-Host "‼ 共有本体（basic_dot_claude のクローン）が見つからない: $ShareBody"
  Write-Host "   .git がディレクトリである独立クローンを指定してください（submodule の checkout は不可）。"
  exit 2
}
# 指定パスがリポジトリの「ルート」かを --show-prefix で判定する（空＝ルート）。
# ⚠ パス文字列を比較してはいけない。同じ場所を指す表記が複数あるため（Windows 形式 vs MSYS 形式、
#    マウント別名、symlink）、比較方式では正しい配布先を誤って拒否する。bash 版と同じ判定に揃える。
$sharePrefix = (git -C $ShareBody rev-parse --show-prefix 2>$null)
if ($LASTEXITCODE -ne 0) { Write-Host "‼ 共有本体が git リポジトリではない: $ShareBody"; exit 2 }
if ($sharePrefix -and $sharePrefix.Trim() -ne '') {
  Write-Host "‼ 共有本体はリポジトリのルートを指す必要があります: $ShareBody"
  Write-Host "   （リポジトリ内のサブディレクトリを指しています: $($sharePrefix.Trim())）"
  exit 2
}

git -C $DevRoot rev-parse --verify "$Ref^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "‼ ref が存在しない: $Ref"; exit 2 }

# 0. symlink（mode 120000）を含む ref は publish しない。
#    zip 経由の本版は symlink を「ターゲットのパス文字列を中身とする通常ファイル」として
#    配布してしまう（データが化けたまま公開され、件数照合もすり抜ける）。bash 版は tar が
#    展開に失敗して止まるため、対策しないと実行者の OS でリリース可否が変わる。
#    ref の段階で両版とも止める。bash 版の 0 と対称。
$links = @(git -C $DevRoot ls-tree -r $Ref -- .claude |
  Where-Object { $_ -match '^120000\s' } |
  ForEach-Object { ($_ -split "`t", 2)[1] })
if ($links.Count -gt 0) {
  Write-Host '‼ payload に symlink が含まれている。publish 中止（配布先で壊れたファイルになる）:'
  $links | ForEach-Object { Write-Host "   $_" }
  exit 1
}

$tmp = Join-Path $env:TEMP ('pubshare_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  # ⚠ エラー出力に Write-Error を使わない: $ErrorActionPreference='Stop' 下では
  #    Write-Error が terminating error になり、直後の exit <code> に到達しないため
  #    終了コードが不定になる（CI で FAIL の種別を判別できない）。Write-Host + exit を使う。

  # 1. 追跡ファイルのみを ref から取り出し（checkout 不要・個人/未追跡は構造的に除外）
  #
  #    ⚠ tar ではなく zip を使う。Windows の tar（C:\Windows\System32\tar.exe＝bsdtar）は
  #       UTF-8 の日本語ファイル名を展開できず、該当ファイルを黙って取りこぼす
  #       （実測: 16 ファイルの payload が 11 ファイルしか展開されない）。
  #       欠落したまま publish すると、ミラー処理が「payload に無い」と見なして
  #       配布先の該当ファイルを削除する。zip + Expand-Archive なら全件復元できる。
  #
  #    ⚠ core.autocrlf を明示的に無効化する。git archive は working-tree 変換（text/eol 属性
  #       ＋ core.autocrlf）を適用するため、これを付けないと publisher のローカル設定で
  #       payload の中身が変わる。Git for Windows の既定は autocrlf=true なので、普通に
  #       clone した Windows 開発者が publish すると配布リポのほぼ全ファイルが CRLF で
  #       書き換わり、同じ ref なのに publish するマシン次第で配布内容が変わる。
  #       eol=crlf 属性を持つファイル（launcher\*.ps1）は属性が優先されるため CRLF のまま。
  #       bash 版と対称にすること。
  $zip = Join-Path $tmp 'payload.zip'
  git -c core.autocrlf=false -C $DevRoot archive $Ref .claude --format=zip -o $zip
  if ($LASTEXITCODE -ne 0) { Write-Host "‼ $Ref から .claude を取り出せない（.claude が無い?）"; exit 1 }
  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force   # → $tmp\.claude\
  $src = Join-Path $tmp '.claude'

  # 2. 安全弁: 取り出した .claude が空なら中止
  if (-not (Test-Path $src) -or -not (Get-ChildItem -Force $src)) {
    Write-Host "‼ $Ref の .claude が空。publish 中止（共有本体を空で上書きしない）"; exit 1
  }

  # 2-b. 安全弁: 展開したファイル数が ref の追跡ファイル数と一致するか
  #      取りこぼしを検知する（欠落したまま publish すると配布先で削除が起きる）。
  $expected = (git -C $DevRoot ls-tree -r --name-only $Ref -- .claude | Measure-Object).Count
  $actual   = (Get-ChildItem -Recurse -File -Force -LiteralPath $src | Measure-Object).Count
  if ($actual -ne $expected) {
    Write-Host "‼ payload の展開に失敗（期待 $expected ファイル / 実際 $actual ファイル）。publish 中止"
    Write-Host "   ファイル名の文字コードが原因の可能性があります。"
    exit 1
  }

  # 3. 衛生ゲート: 取り出した実体に対して check-assets
  #    -Payload で実体基準を強制する。付けないと、%TEMP% が git worktree 配下のマシンでは
  #    check-assets が payload を「追跡基準」で検査してしまい、成果物の混入も統制ファイルの
  #    不在も WARN へ退化してゲートが素通しになる（呼び出し側は層を知っているのだから明示する）。
  & (Join-Path $Here 'check-assets.ps1') -Share $tmp -Payload
  if ($LASTEXITCODE -ne 0) { Write-Host '‼ check-assets FAIL。publish 中止'; exit 1 }

  # 4. /security-review は対話のため手動確認
  $ok = Read-Host "→ $Ref の内容について /security-review を実行済みなら y で続行"
  if ($ok -ne 'y') { Write-Host '中止'; exit 1 }

  # 5. 共有本体へミラー
  #    dest 直下の資産だけを消し（.git とメタ 3 種は残す）、payload を上書きコピーする。
  #    keep-list は「削除から守る」意味であって「payload より優先する」意味ではない。
  #    payload に .gitignore 等が含まれる場合は payload 側が正（配布先の統制ファイルを
  #    開発リポで一元管理するため）。bash 版と挙動を揃えること。
  #
  #    ⚠ robocopy /MIR /XF は使わない。/XF はファイル名マッチが全階層に効くため、
  #       payload 内の .claude/.gitignore まで除外してしまい、配布先の統制ファイルが
  #       永久に届かなくなる（bash 版とだけ挙動が食い違う）。
  $keep = @('.git', '.gitignore', '.gitattributes', 'README.md', 'LICENSE')
  Get-ChildItem -Force -LiteralPath $ShareBody |
    Where-Object { $keep -notcontains $_.Name } |
    Remove-Item -Recurse -Force

  # payload を上書きコピー（-Force で隠しファイル・既存ファイルも対象にする）
  Get-ChildItem -Force -LiteralPath $src | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $ShareBody -Recurse -Force
  }

  # 5-b. 出口検査: payload の全ファイルが配布先に着地したか（2-b と対称の fail-closed）
  #      ミラー段の部分失敗を素通しにすると、混合状態が commit/push され「✓ publish 完了」
  #      が表示される。bash 版の 5-b と対称。
  $missing = @(Get-ChildItem -Recurse -File -Force -LiteralPath $src | ForEach-Object {
      $rel = $_.FullName.Substring($src.Length).TrimStart('\', '/')
      if (-not (Test-Path -LiteralPath (Join-Path $ShareBody $rel))) { $rel }
    })
  if ($missing.Count -gt 0) {
    Write-Host "‼ ミラーの結果に payload のファイルが $($missing.Count) 件欠落している。publish 中止"
    $missing | ForEach-Object { Write-Host "   欠落: $_" }
    exit 1
  }
} finally { Remove-Item -Recurse -Force $tmp }

# 6. 共有本体を commit & push
git -C $ShareBody add -A
if ($LASTEXITCODE -ne 0) { Write-Host '‼ add 失敗。publish 中止'; exit 1 }
git -C $ShareBody diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host '変更なし。publish 不要'; exit 0 }
$short = (git -C $DevRoot rev-parse --short $Ref).Trim()
git -C $ShareBody commit -m "publish: sync .claude from base-dev-kit-for-cc@$short (ref: $Ref)"
if ($LASTEXITCODE -ne 0) { Write-Host '‼ commit 失敗。publish は完了していない'; exit 1 }
git -C $ShareBody push
if ($LASTEXITCODE -ne 0) {
  Write-Host '‼ push 失敗。publish は完了していない（共有本体にローカルコミットが残っている）'
  Write-Host "   認証・保護ブランチ設定を確認し、$ShareBody で push し直してください。"
  exit 1
}

Write-Host "✓ publish 完了（ref: $Ref）。参照ハブ（basic_cc_project）で submodule を bump してください:"
Write-Host '    git -C <basic_cc_project> submodule update --remote .claude'
Write-Host "    git -C <basic_cc_project> add .claude && git -C <basic_cc_project> commit -m 'chore: bump .claude' && git -C <basic_cc_project> push"
