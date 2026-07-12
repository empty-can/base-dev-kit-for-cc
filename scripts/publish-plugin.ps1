<#
  publish-plugin.ps1 — <Dev>(C-BDK) の指定 ref のプラグインを Marketplace リポジトリ <C-MKT> へ publish（層2・validate ゲート）

  publish-share.ps1（層1 body の publish）の plugin 版。release-ready なプラグインを marketplace
  リポジトリへコピーし commit/push する意図的な公開操作で、push はここでしか行わない。
  取り出しは -Ref で指定（既定 main＝公開基準）。checkout 不要で任意 ref を publish できる。

  使い方:
    .\scripts\publish-plugin.ps1 -Marketplace <C-MKT のパス> [-Plugin <repo相対pluginディレクトリ>] [-Ref <ref>] [-Name <plugin名>]

  前提: claude CLI が PATH 上にあること（plugin validate ゲートに使用）。
  注記(ドラフト): プラグイン組成フェーズ未了のため既定 -Plugin=plugin は仮。marketplace.json の
    エントリ整備は本スクリプト範囲外（コピー後にリマインドを表示）。
#>
param(
  [Parameter(Mandatory = $true)][string]$Marketplace,
  [string]$Plugin = 'plugin',
  [string]$Ref = 'main',
  [string]$Name = ''
)
$ErrorActionPreference = 'Stop'

if (-not $Name) { $Name = Split-Path -Leaf $Plugin }
$DevRoot = (git rev-parse --show-toplevel).Trim()

if (-not (Test-Path (Join-Path $Marketplace '.git'))) { Write-Error "marketplace リポジトリが見つからない: $Marketplace"; exit 2 }
git -C $DevRoot rev-parse --verify "$Ref^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { Write-Error "ref が存在しない: $Ref"; exit 2 }

$tmp = Join-Path $env:TEMP ('pubplugin_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  # 1. 追跡ファイルのみを ref から取り出し（checkout 不要・個人/未追跡は構造的に除外）
  git -C $DevRoot archive $Ref $Plugin -o (Join-Path $tmp 'a.tar')
  if ($LASTEXITCODE -ne 0) { Write-Error "$Ref から $Plugin を取り出せない（パス誤り?）"; exit 1 }
  tar -xf (Join-Path $tmp 'a.tar') -C $tmp                       # → $tmp\$Plugin\
  $src = Join-Path $tmp $Plugin

  # 2. 安全弁: 空 / manifest 不在なら中止
  if (-not (Test-Path $src) -or -not (Get-ChildItem -Force $src)) { Write-Error "$Ref の $Plugin が空。中止"; exit 1 }
  if (-not (Test-Path (Join-Path $src '.claude-plugin/plugin.json'))) { Write-Error "$Plugin/.claude-plugin/plugin.json が無い（plugin ではない?）。中止"; exit 1 }

  # 3. ゲート: claude plugin validate（--strict）
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Error "claude CLI が PATH に無い。中止"; exit 1 }
  claude plugin validate --strict $src
  if ($LASTEXITCODE -ne 0) { Write-Error 'plugin validate FAIL。publish 中止'; exit 1 }

  # 4. /security-review は対話のため手動確認
  $ok = Read-Host "→ $Name について /security-review を実行済みなら y で続行"
  if ($ok -ne 'y') { Write-Host '中止'; exit 1 }

  # 5. marketplace へミラー（<C-MKT>/plugins/<name>/ を総入れ替え。.git は保護）
  $dest = Join-Path $Marketplace "plugins/$Name"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  robocopy $src $dest /MIR /XD .git | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Error "robocopy 失敗 (code=$LASTEXITCODE)"; exit 1 }
  $global:LASTEXITCODE = 0
} finally { Remove-Item -Recurse -Force $tmp }

# 6. commit & push
git -C $Marketplace add -A
git -C $Marketplace diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host '変更なし。publish 不要'; exit 0 }
$short = (git -C $DevRoot rev-parse --short $Ref).Trim()
git -C $Marketplace commit -m "publish: sync plugin '$Name' from <Dev>@$short (ref: $Ref)"
git -C $Marketplace push

Write-Host "✓ plugin '$Name' を $dest へ publish 完了（ref: $Ref）。"
Write-Host "  ※ <C-MKT>/.claude-plugin/marketplace.json に '$Name' エントリがあるか確認してください（本スクリプトは marketplace.json を編集しません）。"
