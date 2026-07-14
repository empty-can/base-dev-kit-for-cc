<#
.SYNOPSIS
  clean-test-env.ps1 — クリーン隔離テスト環境を作って Claude Code を起動する（手順書 §5）

.DESCRIPTION
  自分の ~/.claude / project 設定を切り離し、配布する <Share> の共有資産だけを検証する。
  空の CLAUDE_CONFIG_DIR と、.claude / CLAUDE.md / .mcp.json を持たない空の作業ディレクトリを作り、
  <Share> を --add-dir / 環境変数 / --settings で結合して起動する。

  注意:
    - managed settings は system パスにあるためクリーンセッションでも適用され続ける。
    - Windows では認証情報が config dir 配下のため再ログインを求められることがある。

.PARAMETER Share
  配布する共有ペイロード <Share> のパス。省略時は結合なしの素のクリーンセッション。

.PARAMETER Keep
  指定すると終了後に一時ディレクトリを残す（既定は削除）。

.EXAMPLE
  .\clean-test-env.ps1 -Share C:\path\to\share
#>
param(
  [string]$Share = "",
  [switch]$Keep
)

$pushed = $false

# ⚠ 引数の検証は、一時ディレクトリの作成と $env: の書き換えより**前**に済ませること。
#    ここを後回しにすると、検証失敗の exit が try/finally の外で起きるため、env は汚染された
#    まま・一時ディレクトリは残ったままになる（＝このスクリプトが直そうとした症状そのものが、
#    -Share の打ち間違え一発で再現する）。
$shareAbs = ""
if ($Share -ne "") {
  if (-not (Test-Path -PathType Container $Share)) {
    Write-Host "‼ <Share> が見つかりません: $Share"
    exit 1
  }
  $shareAbs = (Resolve-Path $Share).Path
}

$cfg  = Join-Path $env:TEMP ("cc-clean-cfg-"  + [System.IO.Path]::GetRandomFileName())
$work = Join-Path $env:TEMP ("cc-clean-work-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $cfg, $work | Out-Null
Write-Host "[clean-test-env] CLAUDE_CONFIG_DIR = $cfg"
Write-Host "[clean-test-env] 作業ディレクトリ   = $work"

# PowerShell の $env: はプロセス全体を書き換える（bash と違い子プロセスに閉じない）。復元しないと、
# スクリプト終了後も呼び出し元シェルが削除済みの一時 config dir を指したままになる。
$savedCfg      = $env:CLAUDE_CONFIG_DIR
$savedAddDirMd = $env:CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD

try {
  $env:CLAUDE_CONFIG_DIR = $cfg
  $cli = @()

  if ($shareAbs -ne "") {
    $cli += @("--add-dir", $shareAbs)
    $env:CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD = "1"   # CLAUDE.md / rules も結合
    Write-Host "[clean-test-env] 結合: --add-dir $shareAbs（+ CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1）"
    $settings = Join-Path $shareAbs ".claude\settings.json"
    if (Test-Path $settings) {
      $cli += @("--settings", $settings)   # settings.json は --add-dir で来ないので明示
      Write-Host "[clean-test-env] 結合: --settings $settings"
    }
  }

  Write-Host "[clean-test-env] 起動中... (起動後は /memory /context /status /doctor /skills /agents で検証)"
  Push-Location $work
  $pushed = $true
  & claude @cli
}
finally {
  # Push-Location に到達する前に落ちた場合に Pop すると、呼び出し元のカレントを巻き戻してしまう。
  if ($pushed) { Pop-Location }

  # 元の値へ戻す。元が未設定なら $null を渡して変数ごと消す（空文字を代入すると
  # 「空で設定済み」という別状態になり、未設定と区別がつかなくなる）。
  [Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $savedCfg)
  [Environment]::SetEnvironmentVariable('CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD', $savedAddDirMd)

  if ($Keep) {
    Write-Host "[clean-test-env] 一時ディレクトリを残しました: $cfg  $work"
  } else {
    Remove-Item -Recurse -Force $cfg, $work -ErrorAction SilentlyContinue
    Write-Host "[clean-test-env] 一時ディレクトリを削除しました（残すには -Keep）"
  }
  Write-Host "[clean-test-env] 環境変数を元に戻しました"
}
