# =============================================================================
# setup-environment.ps1  ―  Claude Code 起動用 環境変数セットアップ（PowerShell 版）
# =============================================================================
# 役割: 利用者がカスタムする custom.env（分類D）をロードした後、チーム/組織で
#       統制すべき env（分類C・分類B暫定）を「後勝ち」で上書き固定する。
#
# 配置分類（詳細は base-dev-kit の launcher 設計を参照）:
#   分類A（機微: API キー/トークン/パスワード/組織外秘の URL 等）
#       → 本ファイルにも custom.env にも書かない。OS の環境変数として設定すること。
#   分類B（組織単位で統制。将来 managed スコープへ移設予定）
#       → managed 統制が始まるまでの暫定として、非秘匿のみ本ファイルで後勝ち固定。
#   分類C（チーム単位で統制）→ 本ファイルで後勝ち固定。
#   分類D（統制不要・利用者可変）→ custom.env に記述。
#
# ⚠ このランチャー経由の env は foreground 起動の claude にのみ届く。
#    background / agent-view セッションは OS env・ディレクトリ設定から構成を読むため、
#    background にも効かせたい値は OS 環境変数または settings.json で設定すること。
# =============================================================================

# custom.env は .claude/ 直下（launcher の一つ上）。利用者が custom.env.template から作成。
$CustomEnv = Join-Path $PSScriptRoot '..\custom.env'

# ---- 1) 利用者可変 env（分類D）をロード ----------------------------------
if (Test-Path $CustomEnv) {
    Get-Content -LiteralPath $CustomEnv | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        Set-Item -Path ("Env:" + $key) -Value $val
    }
}

# ---- 2) チーム統制 env（分類C）: 後勝ち固定 ------------------------------
# 利用者が custom.env に別の値を書いても、ここで上書きしてチームルールに収束させる。
$env:CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD = '1'   # キット動作依存（追加 CLAUDE.md 連結）

# 自前の git 運用 skill を採用しているチームのみ有効化する:
# $env:CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = '1'

# ---- 3) 組織統制 env（分類B・暫定 C / 将来 managed スコープへ移設）--------
# 非秘匿のみをここに置く。プロバイダ選択やテレメトリ等、組織で揃えるべき値。
# managed スコープ統制が始まったら本ブロックは撤去する。
#
# --- プロバイダ選択（Bedrock / Vertex を使う組織のみ）---
# $env:CLAUDE_CODE_USE_BEDROCK = '1'
# $env:CLAUDE_CODE_USE_VERTEX = '1'
# $env:ANTHROPIC_VERTEX_PROJECT_ID = 'your-gcp-project'      # 非秘匿の場合のみ
# $env:CLAUDE_CODE_SKIP_VERTEX_AUTH = '1'
# --- ゲートウェイ URL（★組織外秘なら分類A＝OS env にすること。非秘匿な場合のみ下記）---
# $env:ANTHROPIC_BEDROCK_BASE_URL = 'https://gateway.example.internal'
# --- データガバナンス / テレメトリ（SIEM 監視をチームで統制する場合）---
# $env:CLAUDE_CODE_ENABLE_TELEMETRY = '1'
# $env:OTEL_EXPORTER_OTLP_ENDPOINT = 'https://otel.example.internal'
# $env:DISABLE_TELEMETRY = '1'
# $env:DISABLE_ERROR_REPORTING = '1'
# --- 企業プロキシ前提のチームのみ固定（既定は custom.env で利用者可変）---
# $env:HTTP_PROXY = 'http://proxy.example.internal:8080'
# $env:HTTPS_PROXY = 'http://proxy.example.internal:8080'
# $env:NO_PROXY = 'localhost,127.0.0.1,.example.internal'

# ⚠ 分類A（機微）はここに書かない。ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN /
#    AWS_BEARER_TOKEN_BEDROCK 等は OS 環境変数として設定すること。
