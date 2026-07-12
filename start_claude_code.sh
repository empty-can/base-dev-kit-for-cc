#!/usr/bin/env bash
# =============================================================================
# start_claude_code.sh  ―  Claude Code ランチャー本体（bash 版）
# =============================================================================
# これ一つで、統制された環境変数と起動オプションが適用された状態で claude を起動する。
# 設定した環境変数はこのプロセスと子プロセス（claude）にのみ効くローカルスコープで、
# OS の環境変数や他アプリには影響しない。
#
# 実行要件: bash 4.4 以上（連想配列 declare -A / nameref local -n / set -u 下での空配列展開）。
#   macOS 同梱の bash は 3.2 のため動かない。`brew install bash` で 4.4+ を導入するか、
#   PowerShell 版（start_claude_code.ps1）を使うこと。
#
# 読み込み関係:
#   start_claude_code
#     ├─ setup-environment.sh  → custom.env をロード＋チーム/組織統制 env を後勝ち固定
#     └─ option-settings.sh    → 利用者可変の起動オプション（OPTS 連想配列）
#   ＋ 本ファイル内の TEAM_OPTS → チーム統制の起動オプション（分類C）
#
# ⚠ ここで設定する env が届くのは foreground 起動の claude だけ。background / agent-view
#    セッションは OS env・ディレクトリ設定から構成を読むため、そちらにも効かせたい値は
#    OS 環境変数または settings.json で設定すること。
#    起動オプションは一部が background へ引き継がれる（全滅ではない）。
# =============================================================================
set -euo pipefail

# ---- 0) 実行要件の確認 ------------------------------------------------------
if [ -z "${BASH_VERSINFO:-}" ] \
  || [ "${BASH_VERSINFO[0]}" -lt 4 ] \
  || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  printf 'エラー: bash 4.4 以上が必要です（現在: %s）。\n' "${BASH_VERSION:-unknown}" >&2
  printf '        macOS 同梱の bash は 3.2 です。brew install bash で更新するか、\n' >&2
  printf '        PowerShell 版（start_claude_code.ps1）を使ってください。\n' >&2
  exit 1
fi

_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SETUP_ENV="${_ROOT_DIR}/.claude/launcher/setup-environment.sh"

# .claude/ は submodule。--recurse-submodules なしで clone すると空になり、
# 存在チェックなしで source すると set -e で理由の分からない即死になる。
if [ ! -f "${_SETUP_ENV}" ]; then
  printf 'エラー: %s が見つかりません。\n' "${_SETUP_ENV}" >&2
  printf '        .claude/ が submodule として未初期化の可能性があります:\n' >&2
  printf '          git submodule update --init --recursive\n' >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  printf 'エラー: claude コマンドが見つかりません（未インストール、または PATH 未設定）。\n' >&2
  printf '        導入手順: https://code.claude.com/docs/en/quickstart\n' >&2
  exit 1
fi

# ---- 1) 環境変数セットアップ（custom.env + 統制 env 後勝ち）------------------
# shellcheck source=/dev/null
. "${_SETUP_ENV}"

# ---- 2) チーム統制の起動オプション（分類C）--------------------------------
# チームで揃えたい起動オプションはここに定義する（利用者は触らない）。
# 値を取らないフラグは値を "true" にする。
#
# 統制の強さ: これは「既定値をチームで揃える」ための仕組みであって、強制力はない。
#   - 値上書き型のフラグは TEAM_OPTS が後段に付くためチーム値が後勝ちになる
#   - ただし起動時引数（"$@"）はさらに後ろに付くので、利用者が明示指定すれば上書きできる
#   - --add-dir のような反復可能フラグは上書きされず両方の値が渡る（累積する）
# 強制したい統制は settings.json / managed settings 側で行うこと。
declare -A TEAM_OPTS=(
  # [--setting-sources]="project,user"
)

# ---- 3) 利用者可変の起動オプション（分類D・option-settings.sh）------------
declare -A OPTS=()
_OPTS_FILE="${_ROOT_DIR}/.claude/option-settings.sh"

# 利用者が誤って launcher/ 側（テンプレートの隣）へ option-settings.sh を置いた場合、
# そのままでは無警告で無視され、起動オプションが一切効かない理由に到達できない。
# custom.env と同じガードを張る（片方だけ守るのは、探すべき場所を一つ増やすだけ）。
if [ -f "${_ROOT_DIR}/.claude/launcher/option-settings.sh" ]; then
  printf '⚠ %s は読み込まれません。option-settings.sh は一つ上の .claude/ 直下に置いてください。\n' \
    "${_ROOT_DIR}/.claude/launcher/option-settings.sh" >&2
fi

if [ -f "${_OPTS_FILE}" ]; then
  # shellcheck source=/dev/null
  . "${_OPTS_FILE}"   # OPTS を定義（未作成なら空のまま）
fi

# ---- 4) claude コマンドを組み立て ------------------------------------------
# TEAM_OPTS を後に置くことで、同じフラグを OPTS にも書いた場合はチーム値が後勝ちする。
_args=()
_append_opts() {
  local -n _map="$1"
  local k v
  for k in "${!_map[@]}"; do
    v="${_map[$k]}"
    _args+=("$k")
    # 値が空 / "true" のものは値なしフラグとして扱う
    if [ -n "$v" ] && [ "$v" != "true" ]; then
      _args+=("$v")
    fi
  done
}
_append_opts OPTS
_append_opts TEAM_OPTS

# ---- 5) 起動（追加引数はそのまま claude へ委譲）------------------------------
exec claude "${_args[@]}" "$@"
