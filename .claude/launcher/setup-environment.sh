#!/usr/bin/env bash
# =============================================================================
# setup-environment.sh  ―  Claude Code 起動用 環境変数セットアップ（bash 版）
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

_LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# custom.env は .claude/ 直下（launcher の一つ上）。利用者が custom.env.template から作成。
_CUSTOM_ENV="${_LAUNCHER_DIR}/../custom.env"

# 分類A（機微）の既知キー。custom.env に書かれていたら警告する（規律違反の可視化）。
_SENSITIVE_KEYS="ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN AWS_BEARER_TOKEN_BEDROCK AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN"

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

    # 分類A のキーは読み込まない。ファイルに書いた機微値が実際に効いてしまうと
    # 「機微はファイルに置かない」規律が機構ごと破れるため、警告して読み飛ばす。
    _skip=0
    for _s in ${_SENSITIVE_KEYS}; do
      if [ "${_key}" = "${_s}" ]; then
        printf '⚠ custom.env の %s は読み込みません（分類A: 機微）。この行を削除し、OS の環境変数として設定してください。\n' \
          "${_key}" >&2
        _skip=1
      fi
    done
    if [ "${_skip}" -eq 1 ]; then
      continue
    fi

    export "${_key}=${_val}"
  done < "${_CUSTOM_ENV}"
  unset _line _key _val _s _skip _first
fi

# ---- 2) チーム統制 env（分類C）: 後勝ち固定 ------------------------------
# 利用者が custom.env に別の値を書いても、ここで上書きしてチームルールに収束させる。
export CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1   # キット動作依存（追加 CLAUDE.md 連結）

# 自前の git 運用 skill を採用しているチームのみ有効化する:
# export CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1

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
# export CLAUDE_CODE_USE_BEDROCK=1
# export CLAUDE_CODE_USE_VERTEX=1
# export ANTHROPIC_VERTEX_PROJECT_ID=your-gcp-project      # 非秘匿の場合のみ
# export CLAUDE_CODE_SKIP_VERTEX_AUTH=1
# --- ゲートウェイ URL（★組織外秘なら分類A＝OS env にすること。非秘匿な場合のみ下記）---
# export ANTHROPIC_BEDROCK_BASE_URL=https://gateway.example.internal
# --- データガバナンス / テレメトリ（SIEM 監視をチームで統制する場合）---
# export CLAUDE_CODE_ENABLE_TELEMETRY=1
# export OTEL_EXPORTER_OTLP_ENDPOINT=https://otel.example.internal
# export DISABLE_TELEMETRY=1
# export DISABLE_ERROR_REPORTING=1
# --- 企業プロキシ前提のチームのみ固定（既定は custom.env で利用者可変）---
# export HTTP_PROXY=http://proxy.example.internal:8080
# export HTTPS_PROXY=http://proxy.example.internal:8080
# export NO_PROXY=localhost,127.0.0.1,.example.internal

# ⚠ 分類A（機微）はここに書かない。ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN /
#    AWS_BEARER_TOKEN_BEDROCK 等は OS 環境変数として設定すること。
