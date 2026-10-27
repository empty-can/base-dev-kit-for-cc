#!/usr/bin/env bash
# =============================================================================
# setup-environment.sh  ―  Claude Code 起動用 環境変数セットアップ（bash 版）
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
#    「supervisor を最初に起動したシェル（ランチャー経由の claude を含む）」から継承される＝届くかは起動順次第
#    （2026-10-20 Windows で実測: ランチャー経由の claude が立ち上げた supervisor では、別の端末から dispatch したセッションにも
#    custom.env の値が届き、dispatch 元の同名の値より優先された。素のシェルが先に立ち上げていると、ランチャー経由の
#    claude --bg でも届かなかった。auto-update による supervisor の自己再起動では env は変わらなかった）。
#    各セッションは起動ディレクトリの settings（project の env を含む）を読み、dispatch 元シェルからは
#    PATH・CLAUDE_CODE_USE_*・ANTHROPIC_DEFAULT_*_MODEL・CLAUDE_CODE_EXTRA_BODY（と条件付きでゲートウェイ設定）
#    だけを引き継ぐ。background にも確実に効かせたい値は OS の環境変数（永続的なユーザー環境変数）で設定する。
#    supervisor は最初に起動したシェルの env を継承する（既に動いている service には、それが起動した時点の env が使われる）。
#    公式 docs は settings の env を勧めるが、キットは利用者に settings 系ファイルの env を使わせない（誤って commit / push する、Claude から読める場所に値が残る、を避けるため）。
#    組織で固定する値だけは managed settings の env に置く。機微（分類A）も OS 環境変数。
#    ※ supervisor ごとラップする公式手段（CLAUDE_CODE_PROCESS_WRAPPER / processWrapper）は Windows では無視される。
#      macOS / Linux でも start_claude_code はその契約を満たさないので登録しない（base-dev-kit の launcher 設計 §5-1）。
#    ※ 本ファイルの警告はすべて stderr に書く（stdout は claude の出力だけ。PS 版はランチャーが stderr へ回す）。
# =============================================================================

_LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# custom.env は .claude/ 直下（launcher の一つ上）。利用者が custom.env.template から作成。
_CUSTOM_ENV="${_LAUNCHER_DIR}/../custom.env"

# 分類A（機微）の既知キー。custom.env に書かれていたら警告して読み飛ばす（規律違反の可視化）。
# 資格情報そのもの（API キー / トークン / シークレット / パスフレーズ / 認証ヘッダ）だけを列挙する。
# 組織 ID・ワークスペース ID 等の識別子（ANTHROPIC_ORGANIZATION_ID 等）は資格情報ではないので含めない。
# ANTHROPIC_CUSTOM_HEADERS は Authorization: Bearer … を運ぶことが多いので含める。タグ付けだけの無害な
# ヘッダ（Accept-Language 等）でも止まるため、その場合は OS の環境変数に置く。
_SENSITIVE_KEYS="
  ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_CUSTOM_HEADERS
  CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_REFRESH_TOKEN
  AWS_BEARER_TOKEN_BEDROCK AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  ANTHROPIC_AWS_API_KEY ANTHROPIC_FOUNDRY_API_KEY ANTHROPIC_FOUNDRY_AUTH_TOKEN
  CLAUDE_CODE_CLIENT_KEY_PASSPHRASE MCP_CLIENT_SECRET
  OTEL_EXPORTER_OTLP_HEADERS OTEL_EXPORTER_OTLP_METRICS_HEADERS
  OTEL_EXPORTER_OTLP_LOGS_HEADERS OTEL_EXPORTER_OTLP_TRACES_HEADERS
"

# 利用者が誤って launcher/ 側へ custom.env を置いた場合、そのままでは無警告で無視される。
if [ -f "${_LAUNCHER_DIR}/custom.env" ]; then
  printf '⚠ %s は読み込まれません。custom.env は一つ上の .claude/ 直下に置いてください。\n' \
    "${_LAUNCHER_DIR}/custom.env" >&2
fi

# ---- 1) 利用者可変 env（分類D）をロード ----------------------------------
# source ではなく行パーサで読む。理由:
#   - CRLF の \r を落とし、PowerShell 版と同じ結果に揃える（source だと $'\r' で落ちる）
#   - custom.env に書かれた任意のコードが実行されるのを防ぐ
# 受け付ける書式は custom.env.template のヘッダに記した「素の KEY=VALUE」のみ。
if [ -f "${_CUSTOM_ENV}" ]; then
  _first=1
  while IFS= read -r _line || [ -n "${_line}" ]; do
    _line="${_line%$'\r'}"                          # CRLF 耐性
    # UTF-8 BOM 耐性。Windows のメモ帳で「UTF-8 (BOM)」保存すると先頭に EF BB BF が付く。
    # BOM を残すと先頭行のキーが "﻿FOO" となって名前検査に落ち、その 1 件だけが
    # 黙って無効になる（PowerShell の Get-Content は BOM を剥がすため、同じ custom.env が
    # OS で違う結果になる）。しかも警告に出るキー名は BOM が不可視なので正しく見え、
    # 利用者は原因に到達できない。ここで落とす。
    if [ "${_first}" -eq 1 ]; then
      _line="${_line#$'\xef\xbb\xbf'}"
      _first=0
    fi
    _line="${_line#"${_line%%[![:space:]]*}"}"      # 前後の空白を除去
    _line="${_line%"${_line##*[![:space:]]}"}"
    case "${_line}" in ''|'#'*) continue ;; esac    # 空行・コメント行
    case "${_line}" in *=*) ;; *) continue ;; esac  # KEY=VALUE 以外

    _key="${_line%%=*}"
    _val="${_line#*=}"
    _key="${_key%"${_key##*[![:space:]]}"}"         # KEY の末尾空白を除去
    _val="${_val#"${_val%%[![:space:]]*}"}"         # VALUE の先頭空白を除去

    # 環境変数名として妥当なものだけを通す（不正名の export で落とさない）。
    #
    # ⚠ case は glob であって正規表現ではない。`[A-Za-z_][A-Za-z0-9_]*` と書くと
    #    末尾の * が「空白を含む任意の文字列」に一致してしまい、`AB CD` のような
    #    不正名が検査を通過して export が落ちる（set -e 下では起動そのものが止まる）。
    #    逆に 1 文字のキー（`A`）は 2 文字目が必須のため弾かれてしまう。
    #    アンカー付きの正規表現で判定すること（bash 4.4+ を要求しているので使える）。
    if ! [[ "${_key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      printf '⚠ custom.env の行を読み飛ばしました（環境変数名として不正）: %s\n' "${_key}" >&2
      continue
    fi

    # ランチャー（本ファイルと start_claude_code.sh）が内部で使う名前は読み込まない。下の export は
    # シェル変数そのものを書き換えるため、_SENSITIVE_KEYS や IFS を書かれると以後の行で分類A の
    # 完全一致判定が効かなくなり（AWS_ACCESS_KEY_ID のように接尾辞で拾えないキーが通る）、IFS は
    # ランチャー本体の以後の単語分割まで変え、_ROOT_DIR は source する option-settings.sh の場所を変える。
    # 判定は変数を介さない case にする（判定に使う変数自体が書き換えの対象になりうるため）。
    # 比較は大文字小文字を区別する（bash の変数名は区別する。_line と _LINE は別の変数）。
    # `_` で始まる名前を一律には拒否しない（_JAVA_OPTIONS 等の正当な用途がある）。内部変数を readonly にも
    # しない（set -e の下で export が失敗し、起動ごと止まる）。名前の集合は PowerShell 版と揃えること。
    # bash の読み取り専用の変数（非対話の bash で readonly -p / declare -r が示す BASHOPTS / BASH_VERSINFO / EUID / PPID /
    # SHELLOPTS / UID）も同じ扱いにする。export が失敗し、set -e の下ではランチャーの起動ごと止まるため（PS 版も同じ名前を
    # 同じ警告で読み飛ばし、同じ custom.env が OS で違う結果にならないようにする）。一覧に無い読み取り専用の変数は、
    # 下の export の安全網が警告にする。
    case "${_key}" in
      IFS|_LAUNCHER_DIR|_CUSTOM_ENV|_SENSITIVE_KEYS|_first|_line|_key|_val|_ukey|_skip|_s|_url_re|_ROOT_DIR|_SETUP_ENV|BASHOPTS|BASH_VERSINFO|EUID|PPID|SHELLOPTS|UID)
        printf '⚠ custom.env の行を読み飛ばしました（ランチャーの内部変数名と衝突）: %s\n' "${_key}" >&2
        continue ;;
    esac

    # 分類A のキーは読み込まない。ファイルに書いた機微値が実際に効いてしまうと
    # 「機微はファイルに置かない」規律が機構ごと破れるため、警告して読み飛ばす。
    # 既知キーの完全一致に加え、資格情報らしい名前（接尾辞）と認証情報入りの URL も対象。
    # Windows の環境変数名は大文字小文字を区別しないため、比較は大文字化して行う（PowerShell 版と揃える）。
    # 接尾辞の *_TOKEN は *_AUTH_TOKEN / *_OAUTH_TOKEN / *_REFRESH_TOKEN を含む（GH_TOKEN・HF_TOKEN 等）。
    # MAX_THINKING_TOKENS のような *_TOKENS は対象外。*_CREDENTIALS は加えない
    # （GOOGLE_APPLICATION_CREDENTIALS は鍵ファイルのパスで、custom.env に書く正当な用途がある）。
    # 接尾辞と同じ語の名前全体（API_KEY / TOKEN / SECRET 等そのもの）と SECRET_* も対象。
    # *_PASS / *_PASSWD / *_PWD は DB_PASS 等の略記、*_CONNECTION_STRING は Azure の AccountKey=… のように
    # 「://」を含まない資格情報入りの接続文字列を拾う。PWD 単独は加えない（シェルのカレントディレクトリ）。
    # *_KEY や *SECRET* のような広い形は加えない（非機微の設定名を巻き込む）。
    _ukey="${_key^^}"
    _skip=0
    for _s in ${_SENSITIVE_KEYS}; do
      if [ "${_ukey}" = "${_s}" ]; then
        _skip=1
      fi
    done
    case "${_ukey}" in
      *_API_KEY|*_TOKEN|*_ACCESS_KEY|*_PRIVATE_KEY|*_SECRET|*_SECRET_*|*_PASSWORD|*_PASSPHRASE|OTEL_EXPORTER_OTLP*_HEADERS)
        _skip=1 ;;
      API_KEY|TOKEN|ACCESS_KEY|PRIVATE_KEY|SECRET|SECRET_*|PASSWORD|PASSPHRASE)
        _skip=1 ;;
      *_PASS|*_PASSWD|*_PWD|*_CONNECTION_STRING)
        _skip=1 ;;
    esac
    # URL 埋め込みの資格情報: 値のどこかに「://<userinfo>@」があれば機微とみなす。値の先頭に限らず、
    # コロン無しの userinfo（https://token@host）・引用符付き（"http://u:p@h"）・jdbc:postgresql://u:p@h も検出する。
    # userinfo に / ? # 空白は含まれないので、パスやクエリの中の @（https://h/@user・https://h?x=a@b）は対象外。
    # パスワード無しの user@ 形式（https://<token>@host）も機微として扱う意図的な判定のため、ssh://git@github.com/... や
    # smtp://noreply@mail.example のような無害な値も止まる。その場合は OS の環境変数に置く。
    # 正規表現は変数に入れて渡す（[[ =~ ]] の右辺に ? [ # を直書きすると glob・コメントと紛れる）。
    # ⚠ ここでの「空白」は ASCII のスペースとタブだけ（PS 版の [ \t] と同じ。値は 1 行なので改行は含まれない）。[:space:] は
    #    ロケール次第で U+3000（和文の空白）や NBSP にも一致し、.NET の \s は常に一致するため、userinfo にそれらを含む値で
    #    両版の判定が割れうる。ブラケット式の中では \t がタブにならない（\ と t になる）ので、タブは $'\t' でつなぐ。
    _url_re='://[^/@?# '$'\t'']+@'
    if [[ "${_val}" =~ ${_url_re} ]]; then
      _skip=1
    fi
    # 「//」の抜けた形も拾う: special scheme（http / https / ws / wss / ftp）の直後の「:」に続けて / か \ が
    # 何個（0 個を含む）あっても、userinfo（/ \ @ ? # 空白を含まない 1 文字以上）と @ が続けば機微とみなす。
    # WHATWG URL 規格はこれらのスキームで // の欠落と \ を補うため、http:u:p@host:port や https:\u:p@host も
    # 認証付き URL として使われる（claude 2.1.303 の HTTPS_PROXY で実測。Proxy-Authorization が送られた）。
    # スキームの前は値の先頭か、スキームに使えない文字（英数字と + . - 以外）に限る（xhttp:u@h のような語の途中を拾わない）。
    # 補われないスキーム（mailto:user@example.com・socks5:u@h 等）は対象外。file は userinfo を持たないので含めない。
    # 大文字小文字は文字クラスで書き分ける（nocasematch はロケール次第で ASCII 以外も畳みうる。PS 版は同じ式を -cmatch で使う）。
    # 変数は上の _url_re を使い回す（名前を増やすと、上の case の内部変数名の集合と PS 版も増やす必要がある）。
    # 空白は上と同じく ASCII のスペースとタブだけ。
    _url_re='(^|[^A-Za-z0-9+.-])([Hh][Tt][Tt][Pp][Ss]?|[Ww][Ss][Ss]?|[Ff][Tt][Pp]):[/\\]*[^/\\@?# '$'\t'']+@'
    if [[ "${_val}" =~ ${_url_re} ]]; then
      _skip=1
    fi
    if [ "${_skip}" -eq 1 ]; then
      printf '⚠ custom.env の %s は読み込みません（分類A: 機微）。この行を削除し、OS の環境変数として設定してください。\n' \
        "${_key}" >&2
      continue
    fi

    # ⚠ bash 固有の安全網（PS 版には無い。この非対称は許容する）: 上の case に無い読み取り専用の変数（呼び出し元が
    #    BASH_ENV 等で readonly にしたもの、将来の bash が加えるもの等）は export が失敗する。set -e の下では、この失敗は
    #    if や || の中でもシェルを終了させる（bash 5.2 で実測）ため、export の間だけ errexit を外し、失敗は警告にして読み飛ばす。
    #    退避先は既存の内部変数を使い回す（_skip はここでは必ず 0 で以後使わず、_s は上のループ変数。名前を増やすと
    #    上の case・PS 版の配列・設計書の 3 か所の集合も増やす必要がある）。
    _skip=0
    case "$-" in *e*) _skip=1; set +e ;; esac
    export "${_key}=${_val}" 2>/dev/null
    _s=$?
    if [ "${_skip}" -eq 1 ]; then set -e; fi
    if [ "${_s}" -ne 0 ]; then
      printf '⚠ custom.env の行を読み飛ばしました（シェルが設定を拒否した。読み取り専用の変数など）: %s\n' "${_key}" >&2
    fi
  done < "${_CUSTOM_ENV}"
  unset _line _key _ukey _val _s _skip _first _url_re
fi

# ---- 2) チーム統制 env（分類C）: 後勝ち固定 ------------------------------
# 利用者が custom.env に別の値を書いても、ここで上書きしてチームルールに収束させる。
# ⚠ 「後勝ち」が効くのはランチャー内（custom.env）に対してだけ。settings.json（user / project / local）の
#    env に同じ変数があるとそちらが勝つ（/setup-bedrock・/setup-vertex も user settings の env へ書き込む）。
#    利用者側で覆せない固定が必要になったら managed settings の env へ移すこと。
# --add-dir 先の CLAUDE.md / .claude/CLAUDE.md / .claude/rules/*.md / CLAUDE.local.md を読み込ませる（AGENTS.md は対象外）。
export CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1   # キット動作依存（追加 CLAUDE.md 連結）
# ⚠ この値は background / agent-view セッションに届かないことがある（冒頭の注記を参照）。--add-dir 自体は
#    background へ引き継がれるので、共有 CLAUDE.md を background でも読ませたい利用者は
#    CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 を OS の環境変数（永続的なユーザー環境変数）として設定する。

# 自前の git 運用 skill を採用しているチームのみ有効化する:
# export CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1

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
# export CLAUDE_CODE_USE_BEDROCK=1
# export AWS_REGION=us-east-1                              # AWS プロファイルに region があれば不要
# Claude Platform on AWS（Bedrock / Foundry の指定が優先されるため併用しない。ワークスペース API キーは分類A）
# export CLAUDE_CODE_USE_ANTHROPIC_AWS=1
# export ANTHROPIC_AWS_WORKSPACE_ID=wrkspc_xxxxxxxxxxxx   # 必須（ID であり資格情報ではない）
# export AWS_REGION=us-east-1
# Google Cloud's Agent Platform（旧 Vertex AI）
# export CLAUDE_CODE_USE_VERTEX=1
# export CLOUD_ML_REGION=global                            # 未設定だと us-east5 にフォールバック
# export ANTHROPIC_VERTEX_PROJECT_ID=your-gcp-project      # 非秘匿の場合のみ。GCLOUD_PROJECT 等より常に優先される
# Microsoft Foundry（API キー / Entra トークンは分類A。未設定なら Azure 既定の資格情報チェーンを使う）
# export CLAUDE_CODE_USE_FOUNDRY=1
# export ANTHROPIC_FOUNDRY_RESOURCE=your-resource         # リソース名のみ（URL・ホスト名は拒否される）
# --- 3P のモデル版固定（3P のエイリアス既定は最新版より遅れ、未有効化のモデルを指すことがある）---
# 値はプロバイダ形式の ID（Bedrock は推論プロファイル ID / ARN、Foundry はデプロイ名）。
# export ANTHROPIC_DEFAULT_OPUS_MODEL=us.anthropic.claude-opus-5-5
# export ANTHROPIC_DEFAULT_SONNET_MODEL=<プロバイダ形式の Sonnet ID>
# export ANTHROPIC_DEFAULT_HAIKU_MODEL=<プロバイダ形式の Haiku ID>
# --- ゲートウェイ URL（★組織外秘なら分類A＝OS env にすること。非秘匿な場合のみ下記）---
# LLM ゲートウェイ（Anthropic Messages 形式のエンドポイント。LiteLLM 等）を組織で運用している場合:
# ⛔ ゲートウェイの認証（ANTHROPIC_AUTH_TOKEN〔Authorization: Bearer〕/ ANTHROPIC_API_KEY〔x-api-key〕）は分類A。ここにも
#    custom.env にも、ほかのどの .env ファイルにも書かず、OS の環境変数で設定する（custom.env に書くと読み飛ばされる）。
#    ANTHROPIC_CUSTOM_HEADERS は値次第: 認証情報（Authorization 等）や個人情報（利用者の ID・メールアドレス等）を載せるなら
#    同じく分類A として OS の環境変数で設定する。載せないヘッダでも custom.env では名前で読み飛ばされるので、OS の環境変数に
#    置く（custom.env.template の冒頭と同じ）。
# ⚠ api.anthropic.com 以外を指すと Remote Control は使えない（v2.1.196 以降）。server-managed settings も取得されない（上の注記）。
# export ANTHROPIC_BASE_URL=https://llm-gateway.example.internal
# この下では MCP の tool search が既定で on になる（v2.1.304 以降。それ未満は ENABLE_TOOL_SEARCH で有効にしない限り off）。ゲートウェイが defer_loading /
# tool_reference を転送できずに 400 / 422 で拒否すると、tool search 無しで自動的に再試行される（v2.1.305 以降。利用者の
# 操作は不要で、MCP ツールは最初から全部読み込まれる）。ただし後で再び試すので、拒否されるリクエストがときどき出る。
# 転送できないと分かっているゲートウェイでは、次の行で最初から止める。
# export ENABLE_TOOL_SEARCH=false
# プロバイダ形式のゲートウェイ（Bedrock / Claude Platform on AWS / Agent Platform / Foundry の形式で受けるもの）:
# ゲートウェイが認証を付ける場合は、各プロバイダのクライアント認証を省く CLAUDE_CODE_SKIP_*_AUTH と対で使う。
# export ANTHROPIC_BEDROCK_BASE_URL=https://gateway.example.internal
# export CLAUDE_CODE_SKIP_BEDROCK_AUTH=1
# export ANTHROPIC_AWS_BASE_URL=https://gateway.example.internal
# export CLAUDE_CODE_SKIP_ANTHROPIC_AWS_AUTH=1
# export ANTHROPIC_VERTEX_BASE_URL=https://gateway.example.internal
# export CLAUDE_CODE_SKIP_VERTEX_AUTH=1
# export ANTHROPIC_FOUNDRY_BASE_URL=https://gateway.example.internal/anthropic
# export CLAUDE_CODE_SKIP_FOUNDRY_AUTH=1                   # Foundry の API キー / トークンがあると無視される
# --- データガバナンス / テレメトリ（SIEM 監視をチームで統制する場合）---
# OpenTelemetry の送出先（組織の収集基盤）。settings へ移す場合は user か managed に置くこと
# （project / local の settings では無視される。v2.1.282 以降）。
# export CLAUDE_CODE_ENABLE_TELEMETRY=1
# export OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.example.internal
# 権限ルール・managed のルール・auto mode・hook・sandbox 等がツール呼び出しを拒否した / 確認を求めた記録は
# claude_code.safety_event（v2.1.307 以降）として events 側に出る。events（logs）は OTEL_LOGS_EXPORTER を
# 設定したときだけ送られる（SIEM で拒否を監視するならメトリクスだけでは足りない）。
# ⛔ OTEL_EXPORTER_OTLP_HEADERS（Authorization=Bearer … を載せる）は分類A。ここに書かない。
# Anthropic への運用テレメトリ / エラー報告の停止（3P プロバイダでは既定で停止済み）。
# ⚠ どちらも「空でない値なら何でも停止」で、0 や false でも停止する。戻すには行ごと消す。
# ⚠ DISABLE_TELEMETRY は feature-flag 取得も止めるため、1P（Anthropic API）でも Advisor・
#    アイドル時コンパクション・claude.ai のスキル同期・Windows での PowerShell ツール既定有効化 等が使えなくなる。
#    Advisor をレビュー工程に組み込んでいるチームは有効化しないこと。
# export DISABLE_TELEMETRY=1
# export DISABLE_ERROR_REPORTING=1
# --- 企業プロキシ前提のチームのみ固定（既定は custom.env で利用者可変）---
# ⛔ 認証情報を含むプロキシ URL（user:pass@）は分類A。ここに書かず OS 環境変数で設定する。
# export HTTP_PROXY=http://proxy.example.internal:8080
# export HTTPS_PROXY=http://proxy.example.internal:8080
# export NO_PROXY=localhost,127.0.0.1,.example.internal

# ⚠ 分類A（機微）はここに書かない。ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN / CLAUDE_CODE_OAUTH_TOKEN /
#    AWS_BEARER_TOKEN_BEDROCK / ANTHROPIC_FOUNDRY_API_KEY / ANTHROPIC_AWS_API_KEY / OTEL_EXPORTER_OTLP_HEADERS /
#    ANTHROPIC_CUSTOM_HEADERS 等は OS 環境変数として設定すること。
