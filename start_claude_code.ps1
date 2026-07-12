# =============================================================================
# start_claude_code.ps1  ―  Claude Code ランチャー本体（PowerShell 版）
# =============================================================================
# これ一つで、統制された環境変数と起動オプションが適用された状態で claude を起動する。
# 設定した環境変数（$env:）はこのプロセスと子プロセス（claude）にのみ効くローカルスコープで、
# OS の環境変数や他アプリには影響しない。
#
# 読み込み関係:
#   start_claude_code.ps1
#     ├─ setup-environment.ps1  → custom.env をロード＋チーム/組織統制 env を後勝ち固定
#     └─ option-settings.ps1    → 利用者可変の起動オプション（$Opts）
#   ＋ 本ファイル内の $TeamOpts → チーム統制の起動オプション（分類C）
#
# ⚠ ここで設定する env が届くのは foreground 起動の claude だけ。background / agent-view
#    セッションは OS env・ディレクトリ設定から構成を読むため、そちらにも効かせたい値は
#    OS 環境変数または settings.json で設定すること。
#    起動オプションは一部が background へ引き継がれる（全滅ではない）。
# =============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootDir = $PSScriptRoot

# ---- 0) 実行要件の確認 ------------------------------------------------------
# .claude/ は submodule。--recurse-submodules なしで clone すると空になるため、
# 存在チェックなしで dot-source すると理由の分からないエラーになる。
$SetupEnv = Join-Path $RootDir '.claude\launcher\setup-environment.ps1'
if (-not (Test-Path $SetupEnv)) {
    Write-Error @"
$SetupEnv が見つかりません。
.claude/ が submodule として未初期化の可能性があります:
  git submodule update --init --recursive
"@
    exit 1
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error @"
claude コマンドが見つかりません（未インストール、または PATH 未設定）。
導入手順: https://code.claude.com/docs/en/quickstart
"@
    exit 1
}

# ---- 1) 環境変数セットアップ（custom.env + 統制 env 後勝ち）------------------
. $SetupEnv

# ---- 2) チーム統制の起動オプション（分類C）--------------------------------
# チームで揃えたい起動オプションはここに定義する（利用者は触らない）。
# 値を取らないフラグは値を $true にする。
#
# 統制の強さ: これは「既定値をチームで揃える」ための仕組みであって、強制力はない。
#   - 値上書き型のフラグは $TeamOpts が後段に付くためチーム値が後勝ちになる
#   - ただし起動時引数（@args）はさらに後ろに付くので、利用者が明示指定すれば上書きできる
#   - --add-dir のような反復可能フラグは上書きされず両方の値が渡る（累積する）
# 強制したい統制は settings.json / managed settings 側で行うこと。
$TeamOpts = [ordered]@{
    # '--setting-sources' = 'project,user'
}

# ---- 3) 利用者可変の起動オプション（分類D・option-settings.ps1）------------
$Opts = [ordered]@{}
$OptsFile = Join-Path $RootDir '.claude\option-settings.ps1'
if (Test-Path $OptsFile) {
    . $OptsFile   # $Opts を定義（未作成なら空のまま）
}

# ---- 4) claude コマンドを組み立て ------------------------------------------
# $TeamOpts を後に置くことで、同じフラグを $Opts にも書いた場合はチーム値が後勝ちする。
$cliArgs = [System.Collections.Generic.List[string]]::new()
foreach ($map in @($Opts, $TeamOpts)) {
    foreach ($k in $map.Keys) {
        $v = $map[$k]
        $cliArgs.Add([string]$k)
        # 値が空 / $true / 'true' のものは値なしフラグとして扱う
        if ($null -ne $v -and "$v" -ne '' -and "$v" -ne 'true' -and $v -ne $true) {
            $cliArgs.Add([string]$v)
        }
    }
}

# ---- 5) 起動（追加引数はそのまま claude へ委譲）------------------------------
$argsArray = $cliArgs.ToArray()
& claude @argsArray @args

# claude の終了コードをそのまま返す（ヘッドレス実行・CI で失敗を検知できるようにする）
exit $LASTEXITCODE
