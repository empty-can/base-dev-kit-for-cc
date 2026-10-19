# =============================================================================
# setup-environment.ps1  ―  Claude Code 起動用 環境変数セットアップ（PowerShell 版）
# =============================================================================
# 役割: 利用者がカスタムする custom.env（分類D）をロードした後、チーム/組織で
#       統制すべき env（分類C・分類B暫定）を「後勝ち」で上書き固定する
#       （ランチャー内での優先順位。settings.json の env には負ける ―― 2) の注記を参照）。
#
# 配置分類（詳細は base-dev-kit の launcher 設計を参照）:
#   分類A（機微: API キー/トークン/パスワード/組織外秘の URL 等）
#       → 本ファイルにも custom.env にも書かない。OS の環境変数として設定すること。
#   分類B（組織単位で統制。将来 managed スコープへ移設予定）
#       → managed 統制が始まるまでの暫定として、非秘匿のみ本ファイルで後勝ち固定。
#   分類C（チーム単位で統制）→ 本ファイルで後勝ち固定。
#   分類D（統制不要・利用者可変）→ custom.env に記述。
#
# ⚠ このランチャー経由の env が確実に届くのは foreground 起動の claude だけ。
#    background / agent-view セッションは全端末で共有する supervisor プロセスがホストし、その env は
#    「supervisor を最初に起動したシェル（ランチャー経由の claude を含む）」から継承される＝届くかは起動順次第。
#    各セッションは起動ディレクトリの settings（project の env を含む）を読み、dispatch 元シェルからは
#    PATH・CLAUDE_CODE_USE_*・ANTHROPIC_DEFAULT_*_MODEL・CLAUDE_CODE_EXTRA_BODY（と条件付きでゲートウェイ設定）
#    だけを引き継ぐ。background にも確実に効かせたい値は OS の環境変数（永続的なユーザー環境変数）で設定する。
#    supervisor は最初に起動したシェルの env を継承する（既に動いている service には、それが起動した時点の env が使われる）。
#    公式 docs は settings の env を勧めるが、キットは利用者に settings 系ファイルの env を使わせない（誤って commit / push する、Claude から読める場所に値が残る、を避けるため）。
#    組織で固定する値だけは managed settings の env に置く。機微（分類A）も OS 環境変数。
#    ※ supervisor ごとラップする公式手段（CLAUDE_CODE_PROCESS_WRAPPER / processWrapper）は Windows では無視される。
# =============================================================================

# custom.env は .claude/ 直下（launcher の一つ上）。利用者が custom.env.template から作成。
$CustomEnv = Join-Path $PSScriptRoot '..\custom.env'

# 分類A（機微）の既知キー。custom.env に書かれていたら警告して読み飛ばす。
# 資格情報そのもの（API キー / トークン / シークレット / パスフレーズ / 認証ヘッダ）だけを列挙する。
# 組織 ID・ワークスペース ID 等の識別子（ANTHROPIC_ORGANIZATION_ID 等）は資格情報ではないので含めない。
# ANTHROPIC_CUSTOM_HEADERS は Authorization: Bearer … を運ぶことが多いので含める。タグ付けだけの無害な
# ヘッダ（Accept-Language 等）でも止まるため、その場合は OS の環境変数に置く。
$SensitiveKeys = @(
    'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_CUSTOM_HEADERS',
    'CLAUDE_CODE_OAUTH_TOKEN', 'CLAUDE_CODE_OAUTH_REFRESH_TOKEN',
    'AWS_BEARER_TOKEN_BEDROCK', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_SESSION_TOKEN',
    'ANTHROPIC_AWS_API_KEY', 'ANTHROPIC_FOUNDRY_API_KEY', 'ANTHROPIC_FOUNDRY_AUTH_TOKEN',
    'CLAUDE_CODE_CLIENT_KEY_PASSPHRASE', 'MCP_CLIENT_SECRET',
    'OTEL_EXPORTER_OTLP_HEADERS', 'OTEL_EXPORTER_OTLP_METRICS_HEADERS',
    'OTEL_EXPORTER_OTLP_LOGS_HEADERS', 'OTEL_EXPORTER_OTLP_TRACES_HEADERS'
)

# bash 版のランチャー（setup-environment.sh と start_claude_code.sh）が内部で使う名前。bash 版は custom.env の
# 値を export でシェル変数へ書くため、これらを書かれると分類A の判定や起動処理が壊れる。本版は Set-Item Env: で
# 書くので影響を受けないが、同じ custom.env が OS で違う結果にならないよう、同じ名前を同じ警告で読み飛ばす。
# bash の変数名に合わせて大文字小文字を区別して比較する（-ccontains）。集合は bash 版の case と揃えること。
# 末尾の 6 個は bash の読み取り専用の変数（非対話の bash で readonly -p / declare -r が示すもの）。bash 版は export が失敗し、
# set -e の下でランチャーの起動ごと止まるので読み飛ばす。本版は設定できるが、結果を揃えるため同じ警告で読み飛ばす。
# （bash 版は一覧に無い読み取り専用の変数でも止まらないよう export の失敗を警告にしている。本版にその安全網は要らない）
$LauncherInternalKeys = @(
    'IFS', '_LAUNCHER_DIR', '_CUSTOM_ENV', '_SENSITIVE_KEYS', '_first', '_line', '_key', '_val',
    '_ukey', '_skip', '_s', '_url_re', '_ROOT_DIR', '_SETUP_ENV',
    'BASHOPTS', 'BASH_VERSINFO', 'EUID', 'PPID', 'SHELLOPTS', 'UID'
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
        # '=' の無い行だけを読み飛ばす。キー名が空の行（=novalue）は下の名前検査で bash 版と同じ警告を出す
        if ($idx -lt 0) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()

        # 環境変数名として妥当なものだけを通す。
        # 黙って捨ててはいけない。typo（例: アンダースコアの入れ忘れ）で env が効かない時、
        # 手掛かりが何も無いと利用者は原因に到達できない。bash 版と同じ警告を出す。
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            Write-Warning "custom.env の行を読み飛ばしました（環境変数名として不正）: $key"
            continue
        }

        # bash 版のランチャーの内部変数名は読み込まない（上の $LauncherInternalKeys の注記を参照）
        if ($LauncherInternalKeys -ccontains $key) {
            Write-Warning "custom.env の行を読み飛ばしました（ランチャーの内部変数名と衝突）: $key"
            continue
        }

        # 分類A のキーは読み込まない。ファイルに書いた機微値が実際に効いてしまうと
        # 「機微はファイルに置かない」規律が機構ごと破れるため、警告して読み飛ばす。
        # 既知キーの完全一致に加え、資格情報らしい名前（接尾辞）と認証情報入りの URL も対象。
        # -contains / -match は既定で大文字小文字を区別しない（bash 版は大文字化して比較し、結果を揃えている）。
        # 接尾辞の _TOKEN は _AUTH_TOKEN / _OAUTH_TOKEN / _REFRESH_TOKEN を含む（GH_TOKEN・HF_TOKEN 等）。
        # MAX_THINKING_TOKENS のような _TOKENS は対象外。_CREDENTIALS は加えない
        # （GOOGLE_APPLICATION_CREDENTIALS は鍵ファイルのパスで、custom.env に書く正当な用途がある）。
        # 接尾辞と同じ語の名前全体（API_KEY / TOKEN / SECRET 等そのもの）と SECRET_* も対象。
        # _PASS / _PASSWD / _PWD は DB_PASS 等の略記、_CONNECTION_STRING は Azure の AccountKey=… のように
        # 「://」を含まない資格情報入りの接続文字列を拾う。PWD 単独は加えない（シェルのカレントディレクトリ）。
        # _KEY や SECRET を含むだけの広い形は加えない（非機微の設定名を巻き込む）。
        # URL 埋め込みの資格情報: 値のどこかに「://<userinfo>@」があれば機微とみなす（bash 版と同じ判定）。
        # コロン無しの userinfo（https://token@host）・引用符付き・jdbc:postgresql://u:p@h も検出し、
        # パスやクエリの中の @（https://h/@user・https://h?x=a@b）は対象外。
        # パスワード無しの user@ 形式（https://<token>@host）も機微として扱う意図的な判定のため、ssh://git@github.com/... や
        # smtp://noreply@mail.example のような無害な値も止まる。その場合は OS の環境変数に置く。
        # 「//」の抜けた形も拾う（bash 版と同じ判定）: special scheme（http / https / ws / wss / ftp）の直後の「:」に続けて
        # / か \ が何個（0 個を含む）あっても、userinfo（/ \ @ ? # 空白を含まない 1 文字以上）と @ が続けば機微とみなす。
        # WHATWG URL 規格はこれらのスキームで // の欠落と \ を補うため、http:u:p@host:port や https:\u:p@host も
        # 認証付き URL として使われる（claude 2.1.303 の HTTPS_PROXY で実測。Proxy-Authorization が送られた）。
        # スキームの前は値の先頭か、スキームに使えない文字（英数字と + . - 以外）に限る（xhttp:u@h のような語の途中を拾わない）。
        # 補われないスキーム（mailto:user@example.com・socks5:u@h 等）は対象外。file は userinfo を持たないので含めない。
        # 大文字小文字は文字クラスで書き分け、-cmatch で比べる（-match の大文字小文字を無視する照合は ASCII 以外も畳み、
        # 否定の文字クラスの結果が bash 版と割れうる）。
        # URL の判定での「空白」は ASCII のスペースとタブだけ（[ \t]。bash 版と同じ。値は 1 行なので改行は含まれない）。
        # \s は U+3000（和文の空白）や NBSP にも一致し、bash 版の [:space:] はロケール次第なので、userinfo にそれらを含む値で
        # 両版の判定が割れうる。
        $isSensitive = ($SensitiveKeys -contains $key) -or
            ($key -match '(^|_)(API_KEY|TOKEN|ACCESS_KEY|PRIVATE_KEY|SECRET|PASSWORD|PASSPHRASE)$') -or
            ($key -match '(^|_)SECRET_') -or
            ($key -match '_(PASS|PASSWD|PWD|CONNECTION_STRING)$') -or
            ($key -match '^OTEL_EXPORTER_OTLP.*_HEADERS$') -or
            ($val -match '://[^/@?# \t]+@') -or
            ($val -cmatch '(^|[^A-Za-z0-9+.-])([Hh][Tt][Tt][Pp][Ss]?|[Ww][Ss][Ss]?|[Ff][Tt][Pp]):[/\\]*[^/\\@?# \t]+@')
        if ($isSensitive) {
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
# ⚠ 「後勝ち」が効くのはランチャー内（custom.env）に対してだけ。settings.json（user / project / local）の
#    env に同じ変数があるとそちらが勝つ（/setup-bedrock・/setup-vertex も user settings の env へ書き込む）。
#    利用者側で覆せない固定が必要になったら managed settings の env へ移すこと。
# --add-dir 先の CLAUDE.md / .claude/CLAUDE.md / .claude/rules/*.md / CLAUDE.local.md を読み込ませる（AGENTS.md は対象外）。
$env:CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD = '1'   # キット動作依存（追加 CLAUDE.md 連結）
# ⚠ この値は background / agent-view セッションに届かないことがある（冒頭の注記を参照）。--add-dir 自体は
#    background へ引き継がれるので、共有 CLAUDE.md を background でも読ませたい利用者は
#    CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 を OS の環境変数（永続的なユーザー環境変数）として設定する。

# 自前の git 運用 skill を採用しているチームのみ有効化する:
# $env:CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = '1'

# ---- 3) 組織統制 env（分類B・暫定 C / 将来 managed スコープへ移設）--------
# 非秘匿のみをここに置く。プロバイダ選択やテレメトリ等、組織で揃えるべき値。
# managed スコープ統制が始まったら本ブロックは撤去する。移設先は managed settings の env ブロック:
#   - endpoint-managed（MDM / GPO / ファイル配布）: Windows は C:\Program Files\ClaudeCode\managed-settings.json
#     （macOS /Library/Application Support/ClaudeCode/、Linux・WSL /etc/claude-code/ の同名ファイル）
#   - server-managed（claude.ai 管理画面）: Team / Enterprise かつ api.anthropic.com 直結の OAuth ログイン /
#     CLAUDE_CODE_OAUTH_TOKEN / 直接設定した API キーのときだけ取得される。apiKeyHelper・WIF・3P・
#     非既定の ANTHROPIC_BASE_URL では取得されず、Console の API キーには claude.ai 組織の設定が届かない。
#   managed の env は管理ソース間で変数単位にマージされ（v2.1.223 以降）、user / project の settings より優先される。
#
# --- プロバイダ選択（3P プロバイダを使う組織のみ。1 つだけ有効化すること）---
# ⚠ サードパーティプロバイダ（Amazon Bedrock / Claude Platform on AWS / Google Cloud's Agent Platform /
#    Microsoft Foundry）へ切り替えると、以下がサーバ側非対応のため使えなくなる（公式 docs
#    「Feature availability」の「CLI capabilities that vary by provider」/「Admin and analytics」）:
#      - Advisor / Fast mode / Channels / Server-managed settings / Analytics dashboard（3P すべて ✗）
#      - Web search（Bedrock ✗ / Agent Platform は Opus 4・Sonnet 4・Haiku 4.5 以降のみ / CPAWS・Foundry ✓）
#      - Auto mode（Sonnet 5 以降 / Opus 4.7 以降 / Haiku 5.5 / Fable 系のモデルに限る）
#      - Remote Control・Artifacts・cloud sessions 等、claude.ai サブスクリプション必須の機能
#    3P では feature-flag 取得と、Anthropic へのテレメトリ / エラー報告も既定で止まる。
#    最後の一点は本ブロックの出口にも効く。ここで CLAUDE_CODE_USE_* を設定した時点で server-managed の
#    取得は止まり、endpoint-managed の env で上書きしても戻らない。3P 採用組織の出口は endpoint-managed
#    （MDM 等で配布する managed-settings.json）か、self-hosted の Claude apps gateway からの配信となる。
#    Advisor をレビュー工程に組み込んでいるチームは、有効化前に運用への影響を確認すること。
# Amazon Bedrock
# $env:CLAUDE_CODE_USE_BEDROCK = '1'
# $env:AWS_REGION = 'us-east-1'                              # AWS プロファイルに region があれば不要
# Claude Platform on AWS（Bedrock / Foundry の指定が優先されるため併用しない。ワークスペース API キーは分類A）
# $env:CLAUDE_CODE_USE_ANTHROPIC_AWS = '1'
# $env:ANTHROPIC_AWS_WORKSPACE_ID = 'wrkspc_xxxxxxxxxxxx'   # 必須（ID であり資格情報ではない）
# $env:AWS_REGION = 'us-east-1'
# Google Cloud's Agent Platform（旧 Vertex AI）
# $env:CLAUDE_CODE_USE_VERTEX = '1'
# $env:CLOUD_ML_REGION = 'global'                            # 未設定だと us-east5 にフォールバック
# $env:ANTHROPIC_VERTEX_PROJECT_ID = 'your-gcp-project'      # 非秘匿の場合のみ。GCLOUD_PROJECT 等より常に優先される
# Microsoft Foundry（API キー / Entra トークンは分類A。未設定なら Azure 既定の資格情報チェーンを使う）
# $env:CLAUDE_CODE_USE_FOUNDRY = '1'
# $env:ANTHROPIC_FOUNDRY_RESOURCE = 'your-resource'         # リソース名のみ（URL・ホスト名は拒否される）
# --- 3P のモデル版固定（3P のエイリアス既定は最新版より遅れ、未有効化のモデルを指すことがある）---
# 値はプロバイダ形式の ID（Bedrock は推論プロファイル ID / ARN、Foundry はデプロイ名）。
# $env:ANTHROPIC_DEFAULT_OPUS_MODEL = 'us.anthropic.claude-opus-5-5'
# $env:ANTHROPIC_DEFAULT_SONNET_MODEL = '<プロバイダ形式の Sonnet ID>'
# $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = '<プロバイダ形式の Haiku ID>'
# --- ゲートウェイ URL（★組織外秘なら分類A＝OS env にすること。非秘匿な場合のみ下記）---
# ゲートウェイが認証を付ける場合は、各プロバイダのクライアント認証を省く CLAUDE_CODE_SKIP_*_AUTH と対で使う。
# $env:ANTHROPIC_BEDROCK_BASE_URL = 'https://gateway.example.internal'
# $env:CLAUDE_CODE_SKIP_BEDROCK_AUTH = '1'
# $env:ANTHROPIC_AWS_BASE_URL = 'https://gateway.example.internal'
# $env:CLAUDE_CODE_SKIP_ANTHROPIC_AWS_AUTH = '1'
# $env:ANTHROPIC_VERTEX_BASE_URL = 'https://gateway.example.internal'
# $env:CLAUDE_CODE_SKIP_VERTEX_AUTH = '1'
# $env:ANTHROPIC_FOUNDRY_BASE_URL = 'https://gateway.example.internal/anthropic'
# $env:CLAUDE_CODE_SKIP_FOUNDRY_AUTH = '1'                   # Foundry の API キー / トークンがあると無視される
# --- データガバナンス / テレメトリ（SIEM 監視をチームで統制する場合）---
# OpenTelemetry の送出先（組織の収集基盤）。settings へ移す場合は user か managed に置くこと
# （project / local の settings では無視される。v2.1.282 以降）。
# $env:CLAUDE_CODE_ENABLE_TELEMETRY = '1'
# $env:OTEL_EXPORTER_OTLP_ENDPOINT = 'https://otel.example.internal'
# ⛔ OTEL_EXPORTER_OTLP_HEADERS（Authorization=Bearer … を載せる）は分類A。ここに書かない。
# Anthropic への運用テレメトリ / エラー報告の停止（3P プロバイダでは既定で停止済み）。
# ⚠ どちらも「空でない値なら何でも停止」で、0 や false でも停止する。戻すには行ごと消す。
# ⚠ DISABLE_TELEMETRY は feature-flag 取得も止めるため、1P（Anthropic API）でも Advisor・
#    アイドル時コンパクション・claude.ai のスキル同期・Windows での PowerShell ツール既定有効化 等が使えなくなる。
#    Advisor をレビュー工程に組み込んでいるチームは有効化しないこと。
# $env:DISABLE_TELEMETRY = '1'
# $env:DISABLE_ERROR_REPORTING = '1'
# --- 企業プロキシ前提のチームのみ固定（既定は custom.env で利用者可変）---
# ⛔ 認証情報を含むプロキシ URL（user:pass@）は分類A。ここに書かず OS 環境変数で設定する。
# $env:HTTP_PROXY = 'http://proxy.example.internal:8080'
# $env:HTTPS_PROXY = 'http://proxy.example.internal:8080'
# $env:NO_PROXY = 'localhost,127.0.0.1,.example.internal'

# ⚠ 分類A（機微）はここに書かない。ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN / CLAUDE_CODE_OAUTH_TOKEN /
#    AWS_BEARER_TOKEN_BEDROCK / ANTHROPIC_FOUNDRY_API_KEY / ANTHROPIC_AWS_API_KEY / OTEL_EXPORTER_OTLP_HEADERS /
#    ANTHROPIC_CUSTOM_HEADERS 等は OS 環境変数として設定すること。
