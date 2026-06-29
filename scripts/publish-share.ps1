<#
  publish-share.ps1 — <Dev>（本リポジトリ）の .claude を共有本体 basic_dot_claude へ publish（Sync A・手動ゲート）

  session 開始時の自動同期（refresh / pull --ff-only）とは別物。
  「develop→main を経た release-ready な .claude を共有本体へ反映する」意図的な操作で、
  publish はここでしか push しない。

  使い方:  .\scripts\publish-share.ps1 [-ShareBody C:\cc-workspace\basic_dot_claude]
  前提:    main ブランチで実行（公開基準）。
#>
param([string]$ShareBody = 'C:\cc-workspace\basic_dot_claude')
$ErrorActionPreference = 'Stop'

$DevRoot = (git rev-parse --show-toplevel).Trim()
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path (Join-Path $ShareBody '.git'))) { Write-Error "共有本体（basic_dot_claude のクローン）が見つからない: $ShareBody"; exit 2 }

# 1. 公開基準ブランチ（main）確認
$branch = (git -C $DevRoot rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') { Write-Error "publish は main で実行してください（現在: $branch）"; exit 1 }

# 2. 衛生ゲート: check-assets.ps1（FAIL で中止）
& (Join-Path $Here 'check-assets.ps1') -Share $DevRoot
if ($LASTEXITCODE -ne 0) { Write-Error 'check-assets FAIL。publish 中止'; exit 1 }

# 3. /security-review は対話コマンドのため手動確認
$ok = Read-Host '→ Claude Code で /security-review を実行済みなら y で続行'
if ($ok -ne 'y') { Write-Host '中止'; exit 1 }

# 4. .claude の「Git 追跡ファイルのみ」を共有本体へミラー（個人/未追跡は構造的に除外）
$tmp = Join-Path $env:TEMP ('pubshare_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  git -C $DevRoot archive HEAD .claude -o (Join-Path $tmp 'a.tar')
  tar -xf (Join-Path $tmp 'a.tar') -C $tmp                       # → $tmp\.claude\
  $src = Join-Path $tmp '.claude'
  # /MIR で総入れ替え。共有本体のメタ（.git/README/LICENSE/.gitignore）は除外して保護
  robocopy $src $ShareBody /MIR /XD .git /XF README.md LICENSE .gitignore | Out-Null
  if ($LASTEXITCODE -ge 8) { Write-Error "robocopy 失敗 (code=$LASTEXITCODE)"; exit 1 }
  $global:LASTEXITCODE = 0
} finally { Remove-Item -Recurse -Force $tmp }

# 5. 共有本体を commit & push
git -C $ShareBody add -A
git -C $ShareBody diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host '変更なし。publish 不要'; exit 0 }
$short = (git -C $DevRoot rev-parse --short HEAD).Trim()
git -C $ShareBody commit -m "publish: sync .claude from base-dev-kit-for-cc@$short"
git -C $ShareBody push

Write-Host '✓ publish 完了。参照ハブ（basic_cc_project）側で submodule を bump してください:'
Write-Host '    git -C <basic_cc_project> submodule update --remote .claude'
Write-Host "    git -C <basic_cc_project> add .claude && git -C <basic_cc_project> commit -m 'chore: bump .claude' && git -C <basic_cc_project> push"
