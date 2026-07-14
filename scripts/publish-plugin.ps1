<#
  publish-plugin.ps1 — <Dev>(C-BDK) の指定 ref のプラグインを Marketplace リポジトリ <C-MKT> へ publish（層2・validate ゲート）

  publish-share.ps1（層1 body の publish）の plugin 版。release-ready なプラグインを marketplace
  リポジトリへコピーし commit/push する意図的な公開操作で、push はここでしか行わない。
  publish 対象は -Ref で明示指定する（既定値は無い）。checkout 不要で任意 ref を publish できる。

  使い方:
    .\scripts\publish-plugin.ps1 -Marketplace <C-MKT のパス> -Ref <ref> [-Plugin <repo相対pluginディレクトリ>] [-Name <plugin名>]

  前提: claude CLI が PATH 上にあること（plugin validate ゲートに使用）。
  注記(ドラフト): プラグイン組成フェーズ未了のため既定 -Plugin=plugin は仮。marketplace.json の
    エントリ整備は本スクリプト範囲外（コピー後にリマインドを表示）。

  ⚠ 本スクリプトは publish-share.ps1 と同じ防御を持たせること（片方だけ直した状態を作らない）。
     -Ref 必須 / DevRoot の CWD 非依存 / 配布先ルート検査（gitlink 拒否）/ symlink 拒否 /
     zip 経由の展開 / core.autocrlf=false / 展開の fail-closed / commit・push 失敗の検知。
#>

# Windows PowerShell 5.1 では stderr リダイレクト（*> $null）と $ErrorActionPreference='Stop' の
# 組み合わせで native の stderr が terminating error に化け、ガードの診断と終了コード規約が崩れる
# （実測: ref の打ち間違いで『‼ ref が存在しない』(exit 2) ではなく NativeCommandError の生スタックが出る）。
# 対象シェルを機械で宣言して fail fast させる。
#requires -Version 7
param(
  [Parameter(Mandatory = $true)][string]$Marketplace,
  [Parameter(Mandatory = $true)][string]$Ref,
  [string]$Plugin = 'plugin',
  [string]$Name = ''
)
$ErrorActionPreference = 'Stop'

# ⚠ エラー出力に Write-Error を使わない: $ErrorActionPreference='Stop' 下では Write-Error が
#    terminating error になり、直後の exit <code> に到達せず終了コードが不定になる。

if (-not $Name) { $Name = Split-Path -Leaf $Plugin }

# $Name はそのまま plugins/<Name> というパスに連結される。検証しないと '..' や '.' や
# スラッシュ入りの値で dest が marketplace のルートを指し、後段の「.git 以外を全削除」が
# そこへ走る（実測: -Name .. でルートが plugin の中身に置換されて push された）。
if ($Name -eq '' -or $Name -eq '.' -or $Name -eq '..' -or $Name -match '[\\/]') {
  Write-Host "‼ plugin 名として不正: '$Name'（'/' '\' '.' '..' は使えない）"
  exit 2
}

# 開発リポの位置はスクリプトの場所から解決する（CWD に依存させない。別リポジトリ内から
# 実行して、そのリポのプラグインを publish してしまう事故を防ぐ）。
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DevRoot = (Resolve-Path (Join-Path $Here '..')).Path
git -C $DevRoot rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "‼ 開発リポジトリが見つからない: $DevRoot"; exit 2 }

# marketplace の検査: .git が「ディレクトリ」であること（submodule の .git はファイル＝gitlink）。
# -PathType Container を付けないと gitlink にも Test-Path が true を返し、submodule の checkout を
# 配布先に指定できてしまう。ミラー処理が .git を壊し、親リポジトリへ commit/push する事故になる。
if (-not (Test-Path -LiteralPath (Join-Path $Marketplace '.git') -PathType Container)) {
  Write-Host "‼ marketplace リポジトリが見つからない: $Marketplace"
  Write-Host '   .git がディレクトリである独立クローンを指定してください（submodule の checkout は不可）。'
  exit 2
}
# ルート判定は --show-prefix の空判定で行う（パス文字列の比較は表記揺れで壊れる）。
$mktPrefix = (git -C $Marketplace rev-parse --show-prefix 2>$null)
if ($LASTEXITCODE -ne 0) { Write-Host "‼ marketplace が git リポジトリではない: $Marketplace"; exit 2 }
if ($mktPrefix -and $mktPrefix.Trim() -ne '') {
  Write-Host "‼ marketplace はリポジトリのルートを指す必要があります: $Marketplace"
  Write-Host "   （リポジトリ内のサブディレクトリを指しています: $($mktPrefix.Trim())）"
  exit 2
}

git -C $DevRoot rev-parse --verify "$Ref^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "‼ ref が存在しない: $Ref"; exit 2 }

# 0. symlink（mode 120000）を含む ref は publish しない。zip 経由の本版は symlink を
#    「ターゲットのパス文字列を中身とする通常ファイル」として配布してしまう（件数照合もすり抜ける）。
$links = @(git -C $DevRoot ls-tree -r $Ref -- $Plugin |
  Where-Object { $_ -match '^120000\s' } |
  ForEach-Object { ($_ -split "`t", 2)[1] })
if ($links.Count -gt 0) {
  Write-Host '‼ plugin に symlink が含まれている。publish 中止（配布先で壊れたファイルになる）:'
  $links | ForEach-Object { Write-Host "   $_" }
  exit 1
}

$tmp = Join-Path $env:TEMP ('pubplugin_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  # 1. 追跡ファイルのみを ref から取り出し（checkout 不要・個人/未追跡は構造的に除外）
  #
  #    ⚠ tar ではなく zip を使う。PowerShell から呼ばれる tar は C:\Windows\System32\tar.exe
  #       （bsdtar）で、UTF-8 の日本語ファイル名を黙って取りこぼす。欠落したまま publish すると
  #       ミラー処理が「payload に無い」と見なして配布先の該当ファイルを削除する。
  #    ⚠ core.autocrlf を無効化する。git archive は working-tree 変換（text/eol 属性 ＋
  #       core.autocrlf）を適用するため、付けないと publisher のローカル設定で中身が変わる
  #       （Git for Windows の既定は autocrlf=true）。bash 版と対称にすること。
  $zip = Join-Path $tmp 'plugin.zip'
  git -c core.autocrlf=false -C $DevRoot archive $Ref $Plugin --format=zip -o $zip
  if ($LASTEXITCODE -ne 0) { Write-Host "‼ $Ref から $Plugin を取り出せない（パス誤り? 未コミット?）"; exit 1 }
  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force   # → $tmp\$Plugin\
  $src = Join-Path $tmp $Plugin

  # 2. 安全弁: 空 / manifest 不在なら中止
  if (-not (Test-Path $src) -or -not (Get-ChildItem -Force $src)) { Write-Host "‼ $Ref の $Plugin が空。中止"; exit 1 }
  if (-not (Test-Path (Join-Path $src '.claude-plugin/plugin.json'))) {
    Write-Host "‼ $Plugin/.claude-plugin/plugin.json が無い（plugin ではない?）。中止"; exit 1
  }

  # 2-b. 安全弁: 展開したファイル数が ref の追跡ファイル数と一致するか（fail-closed）
  $expected = (git -C $DevRoot ls-tree -r --name-only $Ref -- $Plugin | Measure-Object).Count
  $actual   = (Get-ChildItem -Recurse -File -Force -LiteralPath $src | Measure-Object).Count
  if ($actual -ne $expected) {
    Write-Host "‼ plugin の展開に失敗（期待 $expected ファイル / 実際 $actual ファイル）。publish 中止"
    Write-Host '   ファイル名の文字コードが原因の可能性があります。'
    exit 1
  }

  # 3. ゲート: claude plugin validate（--strict）
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Host '‼ claude CLI が PATH に無い。中止'; exit 1 }
  claude plugin validate --strict $src
  if ($LASTEXITCODE -ne 0) { Write-Host '‼ plugin validate FAIL。publish 中止'; exit 1 }

  # 4. /security-review は対話のため手動確認
  $ok = Read-Host "→ $Name について /security-review を実行済みなら y で続行"
  if ($ok -ne 'y') { Write-Host '中止'; exit 1 }

  # 5. marketplace へミラー（<C-MKT>/plugins/<name>/ を総入れ替え。.git は保護）
  #    ⚠ robocopy /XF は使わない。ファイル名マッチが全階層に効くため、plugin 内の同名ファイル
  #       （.gitignore 等）まで除外してしまい bash 版と挙動が食い違う。bash 版と同じく
  #       「.git だけ残して消し、payload を上書きコピー」で揃える。
  #    ⚠ New-Item -ItemType Directory -Force は、パスをファイルが占有していると
  #       $ErrorActionPreference='Stop' でも**例外を投げず $null を返して黙って続行する**
  #       （実測）。その後の Get-ChildItem -LiteralPath はそのファイル自身を返すため、
  #       「dest を空にする」つもりの削除が占有ファイルを消し、Copy-Item は dest 不在の
  #       ため最初の子（.claude-plugin/）を dest へ「リネーム」してしまう。結果、階層の
  #       壊れた plugin が commit・push され「✓ publish 完了」が表示される。
  #       事前にディレクトリであることを検査し、作成後も確認する。
  $script:dest = Join-Path $Marketplace "plugins/$Name"
  if (Test-Path -LiteralPath $script:dest -PathType Leaf) {
    Write-Host "‼ 配布先 $script:dest がディレクトリではない（ファイルが占有している）。publish 中止"; exit 1
  }
  New-Item -ItemType Directory -Force -Path $script:dest | Out-Null
  if (-not (Test-Path -LiteralPath $script:dest -PathType Container)) {
    Write-Host "‼ 配布先ディレクトリを作れない: $script:dest。publish 中止"; exit 1
  }
  Get-ChildItem -Force -LiteralPath $script:dest |
    Where-Object { $_.Name -ne '.git' } |
    Remove-Item -Recurse -Force
  Get-ChildItem -Force -LiteralPath $src | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $script:dest -Recurse -Force
  }

  # 5-b. 出口検査: コピーしたファイル数が payload と一致するか（2-b と対称の fail-closed）
  $copied = (Get-ChildItem -Recurse -File -Force -LiteralPath $script:dest |
    Where-Object { $_.FullName -notlike (Join-Path $script:dest '.git*') } | Measure-Object).Count
  if ($copied -ne $expected) {
    Write-Host "‼ ミラーの結果が payload と一致しない（payload $expected / 配布先 $copied）。publish 中止"
    exit 1
  }
} finally { Remove-Item -Recurse -Force $tmp }

# 6. commit & push（失敗を握りつぶさない。publish 未完了なのに ✓ を出さない）
git -C $Marketplace add -A
if ($LASTEXITCODE -ne 0) { Write-Host '‼ add 失敗。publish 中止'; exit 1 }
git -C $Marketplace diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host '変更なし。publish 不要'; exit 0 }
$short = (git -C $DevRoot rev-parse --short $Ref).Trim()
git -C $Marketplace commit -m "publish: sync plugin '$Name' from <Dev>@$short (ref: $Ref)"
if ($LASTEXITCODE -ne 0) { Write-Host '‼ commit 失敗。publish は完了していない'; exit 1 }
git -C $Marketplace push
if ($LASTEXITCODE -ne 0) {
  Write-Host '‼ push 失敗。publish は完了していない（marketplace にローカルコミットが残っている）'
  Write-Host "   認証・保護ブランチ設定を確認し、$Marketplace で push し直してください。"
  exit 1
}

Write-Host "✓ plugin '$Name' を $script:dest へ publish 完了（ref: $Ref）。"
Write-Host "  ※ <C-MKT>/.claude-plugin/marketplace.json に '$Name' エントリがあるか確認してください（本スクリプトは marketplace.json を編集しません）。"
