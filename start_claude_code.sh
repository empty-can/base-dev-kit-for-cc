#!/usr/bin/env bash
# =============================================================================
# start_claude_code.sh  ―  Claude Code ランチャー本体（bash 版）
# =============================================================================
# これ一つで、統制された環境変数と起動オプションが適用された状態で claude を起動する。
# 設定した環境変数はこのプロセスと子プロセス（claude）にのみ効くローカルスコープで、
# OS の環境変数や他アプリには影響しない。
#
# 読み込み関係:
#   start_claude_code
#     ├─ setup-environment.sh  → custom.env をロード＋チーム/組織統制 env を後勝ち固定
#     └─ option-settings.sh    → 利用者可変の起動オプション（OPTS 連想配列）
#   ＋ 本ファイル内の TEAM_OPTS → チーム統制の起動オプション（分類C）
#
# ⚠ ここで設定する env・オプションは foreground 起動の claude にのみ届く。
#    background / agent-view セッションには届かない（OS env・ディレクトリ設定を使う）。
# =============================================================================
set -euo pipefail

_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 1) 環境変数セットアップ（custom.env + 統制 env 後勝ち）------------------
# shellcheck source=/dev/null
. "${_ROOT_DIR}/.claude/launcher/setup-environment.sh"

# ---- 2) チーム統制の起動オプション（分類C）--------------------------------
# チームで揃えたい起動オプションはここに定義する（利用者は触らない）。
# 値を取らないフラグは値を "true" にする。
declare -A TEAM_OPTS=(
  # [--setting-sources]="project,user"
)

# ---- 3) 利用者可変の起動オプション（分類D・option-settings.sh）------------
declare -A OPTS=()
_OPTS_FILE="${_ROOT_DIR}/.claude/option-settings.sh"
if [ -f "${_OPTS_FILE}" ]; then
  # shellcheck source=/dev/null
  . "${_OPTS_FILE}"   # OPTS を定義（未作成なら空のまま）
fi

# ---- 4) claude コマンドを組み立て ------------------------------------------
# 後勝ちの意味を持たせるため TEAM_OPTS を後に置く（同一フラグはチーム値が優先）。
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
