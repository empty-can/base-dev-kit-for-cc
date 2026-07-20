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

# 分類A（機微）の既知キー。custom.env に書かれていたら警告して読み飛ばす。
$SensitiveKeys = @(
    'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'AWS_BEARER_TOKEN_BEDROCK',
    'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN'
)

# 利用者が誤って launcher/ 側へ custom.env を置いた場合、そのままでは無警告で無視される。
$MisplacedEnv = Join-Path $PSScriptRoot 'custom.env'
if (Test-Path $MisplacedEnv) {
    Write-Warning "$MisplacedEnv は読み込まれません。custom.env は一つ上の .claude/ 直下に置いてください。"
}

# ---- 1) 利用者可変 env（分類D）をロード ----------------------------------
# 受け付ける書式は custom.env.template のヘッダに記した「素の KEY=VALUE」のみ（bash 版と同じ）。
if (Test-Path $CustomEnv) {
    # -Encoding UTF8 を明示する。Windows PowerShell 5.1 の Get-Content 既定は ANSI（日本語環境では
    # CP932）で、BOM 無し UTF-8 の非 ASCII 値を文字化けさせる。明示すれば 5.1 でも UTF-8 として読み、
    # pwsh 7 / bash と結果が揃う（BOM 付きでも -Encoding UTF8 は BOM を剥がして正しく読む）。
    foreach ($rawLine in (Get-Content -LiteralPath $CustomEnv -Encoding UTF8)) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()

        # 環境変数名として妥当なものだけを通す。
        # 黙って捨ててはいけない。typo（例: アンダースコアの入れ忘れ）で env が効かない時、
        # 手掛かりが何も無いと利用者は原因に到達できない。bash 版と同じ警告を出す。
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            Write-Warning "custom.env の行を読み飛ばしました（環境変数名として不正）: $key"
            continue
        }

        # 分類A のキーは読み込まない。ファイルに書いた機微値が実際に効いてしまうと
        # 「機微はファイルに置かない」規律が機構ごと破れるため、警告して読み飛ばす。
        if ($SensitiveKeys -contains $key) {
            Write-Warning "custom.env の $key は読み込みません（分類A: 機微）。この行を削除し、OS の環境変数として設定してください。"
            continue
        }

        # Windows は空文字の環境変数を保持できない（Set-Item Env:X -Value '' は変数を作らず
        # 削除扱いになり、$ErrorActionPreference='Stop' の下では例外化する恐れもある）。bash 版は
        # `export X=` で空値の変数を作れるため挙動が割れる。ここで空値を明示的に警告してスキップし、
        # 「黙って割れる」のを避ける（この非対称は Windows の制約に由来し、bash 側は空値を許す）。
        if ($val -eq '') {
            Write-Warning "custom.env の $key は空値のため設定しません（Windows は空文字の環境変数を保持できません。bash / macOS / Linux 版とは挙動が異なります）。"
            continue
        }

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
# ⚠ サードパーティプロバイダ（Bedrock / Google Cloud's Agent Platform / Microsoft Foundry）
#    へ切り替えると、以下の機能がサーバ側非対応のため無効になる（公式 docs の
#    「CLI capabilities that vary by provider」/「Admin and analytics」）:
#      - Advisor（3P すべて ✗）
#      - Fast mode（3P すべて ✗）
#      - Channels（3P すべて ✗）
#      - Web search（Bedrock ✗ / Vertex は条件付き）
#      - Server-managed settings（3P すべて ✗）
#    最後の一点は本ブロックの出口にも効く。「分類B は将来 managed スコープへ移設」
#    という前提はクラウド配信の server-managed settings を想定しているため、3P 採用組織では
#    その移設先が使えない。MDM 等で配布するローカルの managed-settings.json が代替となる。
#    Advisor をレビュー工程に組み込んでいるチームは、有効化前に運用への影響を確認すること。
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
