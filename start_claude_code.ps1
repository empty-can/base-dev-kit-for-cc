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
# ⚠ ここで設定する env・オプションは foreground 起動の claude にのみ届く。
#    background / agent-view セッションには届かない（OS env・ディレクトリ設定を使う）。
# =============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootDir = $PSScriptRoot

# ---- 1) 環境変数セットアップ（custom.env + 統制 env 後勝ち）------------------
. (Join-Path $RootDir '.claude\launcher\setup-environment.ps1')

# ---- 2) チーム統制の起動オプション（分類C）--------------------------------
# チームで揃えたい起動オプションはここに定義する（利用者は触らない）。
# 値を取らないフラグは値を $true にする。
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
# 後勝ちの意味を持たせるため $TeamOpts を後に置く（同一フラグはチーム値が優先）。
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
