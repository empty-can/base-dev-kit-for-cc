<#
.SYNOPSIS
  clean-test-env.ps1 — クリーン隔離テスト環境を作って Claude Code を起動する（手順書 §5）

.DESCRIPTION
  自分の ~/.claude / project 設定を切り離し、配布する <Share> の共有資産だけを検証する。
  空の CLAUDE_CONFIG_DIR と、.claude / CLAUDE.md / .mcp.json を持たない空の作業ディレクトリを作り、
  <Share> を --add-dir / 環境変数 / --settings で結合して起動する。

  注意:
    - managed settings は system パスにあるためクリーンセッションでも適用され続ける。
    - 認証情報は config dir ごとに分かれるため、初回は再ログインを求められる（環境変数での認証は除く）。
    - claude.ai アカウントの skills / plugins / connectors はクリーン config dir の settings.json で止めている。
    - --settings は user settings と同格に効くため、本テストで観察できるのは方法 B（--add-dir + --settings）の
      挙動であって、.claude\ を project として置く方法 A の挙動ではない（check-assets 3. の WARN 対象キーの扱いが違う）。

.PARAMETER Share
  配布する共有ペイロード <Share> のパス。省略時は結合なしの素のクリーンセッション。

.PARAMETER Keep
  指定すると終了後に一時ディレクトリを残す（既定は削除）。

.PARAMETER PermissionMode
  起動時の権限モード（既定 default）。組み込み既定は版で変わる（v2.1.283〜 対話は auto）ため固定している。
  default / acceptEdits / plan / auto / dontAsk / bypassPermissions / manual のいずれか（大文字小文字を区別）。
  それ以外は起動前に exit 2 で止める（bash 版の PERMISSION_MODE と同じ値集合・同じメッセージ）。

.EXAMPLE
  .\clean-test-env.ps1 -Share C:\path\to\share
#>
# ⚠ -PermissionMode に ValidateSet を使わない。ValidateSet は大文字小文字を区別せず（AUTO が通ってそのまま
#    claude に渡る）、不正値はパラメータバインドの段階で PowerShell 独自の文言・終了コードで落ちるため、
#    bash 版と同じメッセージ・同じ終了コードにできない。補完は ArgumentCompleter で出し、検証は本文で行う。
#    値の一覧は下の $PermissionModes と同じにすること（補完のスクリプトブロックからは本文の変数が見えない）。
param(
  [string]$Share = "",
  [switch]$Keep,
  [ArgumentCompleter({
      param($commandName, $parameterName, $wordToComplete)
      @('default', 'acceptEdits', 'plan', 'auto', 'dontAsk', 'bypassPermissions', 'manual') |
        Where-Object { $_ -like "$wordToComplete*" }
    })]
  [string]$PermissionMode = 'default'
)

$pushed = $false

# ⚠ 引数の検証は、一時ディレクトリの作成と $env: の書き換えより**前**に済ませること。
#    ここを後回しにすると、検証失敗の exit が try/finally の外で起きるため、env は汚染された
#    まま・一時ディレクトリは残ったままになる（＝このスクリプトが直そうとした症状そのものが、
#    -Share の打ち間違え一発で再現する）。
# 権限モードは bash 版と同じ値集合で、大文字小文字を区別して検証する（同じ順序・同じメッセージ・exit 2）。
$PermissionModes = @('default', 'acceptEdits', 'plan', 'auto', 'dontAsk', 'bypassPermissions', 'manual')
if ($PermissionModes -cnotcontains $PermissionMode) {
  # bash 版と同じく stderr へ出す。Write-Error は $ErrorActionPreference='Stop' 下で終端エラーになり exit 2 に届かないので使わない
  [Console]::Error.WriteLine("‼ 権限モードが不正: '$PermissionMode'（default / acceptEdits / plan / auto / dontAsk / bypassPermissions / manual のいずれか。大文字小文字を区別する）")
  exit 2
}
$shareAbs = ""
if ($Share -ne "") {
  if (-not (Test-Path -PathType Container $Share)) {
    # bash 版と同じく stderr へ出す（同じ文言・exit 1。理由は上の権限モードと同じ）
    [Console]::Error.WriteLine("‼ <Share> が見つかりません: $Share")
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
# （bash 版と同じ理由）環境変数で直接読み込まれる plugin を切り離す。$env: はプロセス全体なので退避・復元する。
$isolateVars = @('CLAUDE_CODE_PLUGIN_DIRS', 'CLAUDE_CODE_PLUGIN_SEED_DIR', 'CLAUDE_CODE_PLUGIN_CACHE_DIR')
$savedIsolate = @{}
foreach ($v in $isolateVars) { $savedIsolate[$v] = [Environment]::GetEnvironmentVariable($v) }
foreach ($v in @('CLAUDE_CODE_SAFE_MODE', 'CLAUDE_CODE_SIMPLE', 'CLAUDE_CODE_RESTRICTED', 'CLAUDE_CODE_DISABLE_CLAUDE_MDS')) {
  $val = [Environment]::GetEnvironmentVariable($v)
  if ($val) { Write-Host "[clean-test-env] ⚠ $v=$val が設定されている（<Share> の資産が読み込まれない）" }
}

try {
  $env:CLAUDE_CONFIG_DIR = $cfg
  foreach ($v in $isolateVars) { [Environment]::SetEnvironmentVariable($v, $null) }
  # （bash 版と同じ理由）アカウント同期で <Share> 以外の skills / plugins / connectors が混入するのを止める。
  # 中身は ASCII のみ。WriteAllText(path, string) は BOM なし UTF-8 で書くので 5.1 / 7 で差が出ない。
  [System.IO.File]::WriteAllText((Join-Path $cfg 'settings.json'),
    '{"syncClaudeAiSkills": false, "syncClaudeAiPlugins": false, "disableClaudeAiConnectors": true}')
  # （bash 版と同じ理由）起動時の権限モードを固定する
  $cli = @('--permission-mode', $PermissionMode)
  Write-Host "[clean-test-env] 起動モード: --permission-mode $PermissionMode"

  if ($shareAbs -ne "") {
    $cli += @("--add-dir", $shareAbs)
    $env:CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD = "1"   # CLAUDE.md / .claude\CLAUDE.md / .claude\rules\*.md / CLAUDE.local.md も結合（skills / agents / commands は変数なしでも来る）
    Write-Host "[clean-test-env] 結合: --add-dir $shareAbs（+ CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1）"
    # ⚠ --settings は「コマンドライン」層で、user settings に置けるキーなら何でも効く（project より強い）。
    #    方法 A では無視されるキー（check-assets 3 の WARN 対象）もここでは有効になるため、
    #    本テストの結果は方法 B の挙動であって方法 A の挙動ではない。
    #    --setting-sources で project を外してはならない（--add-dir の skills / agents / commands が読み込まれなくなる）。
    $settings = Join-Path $shareAbs ".claude\settings.json"
    if (Test-Path $settings) {
      $cli += @("--settings", $settings)   # --add-dir からは enabledPlugins / extraKnownMarketplaces しか来ないので明示
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
  foreach ($v in $isolateVars) { [Environment]::SetEnvironmentVariable($v, $savedIsolate[$v]) }

  if ($Keep) {
    Write-Host "[clean-test-env] 一時ディレクトリを残しました: $cfg  $work"
  } else {
    Remove-Item -Recurse -Force $cfg, $work -ErrorAction SilentlyContinue
    Write-Host "[clean-test-env] 一時ディレクトリを削除しました（残すには -Keep）"
  }
  Write-Host "[clean-test-env] 環境変数を元に戻しました"
}
