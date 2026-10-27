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
#   組立順は claude <OPTS> <TEAM_OPTS> [--] <起動時引数>。各連想配列はキーの辞書順（C ロケール）で並べる
#   （PS 版は書いた順）。
#
# 出力の約束: ランチャー（本ファイルと setup-environment）自身の警告・エラーはすべて stderr に書く。stdout は claude の
#   出力だけにする（claude -p の結果を読むスクリプトに混ざらないように。PS 版も同じ）。
# ⚠ これは利用者が端末から起動するランチャーで、CLAUDE_CODE_PROCESS_WRAPPER / processWrapper に登録するもの
#    ではない。登録しても契約を満たさない（Claude Code の引数に起動オプションを足す、起動前に警告を出しうる。
#    PS 版は exec しない）うえ、Windows ではその設定自体が無視される。必要なら別の薄いスクリプトを作る
#    （契約: https://code.claude.com/docs/en/corporate-launcher#the-launcher-contract）。
# ⚠ プロンプトを起動時引数で渡すなら、フラグはすべてプロンプトより前に置くこと。値を複数取るフラグ
#    （--add-dir / --mcp-config / --tools 等）や値を省略できるフラグ（--debug / --resume 等）が組み立てた
#    オプションの最後に来ると、直後のプロンプトを値として取り込む（v2.1.302 で実測）。ランチャーは起動時引数が
#    全部 - で始まらない（＝プロンプトだけ）ときに限り -- を補う。"<prompt>" -p のような混在は補わない。
# ⚠ ここで設定する env が確実に届くのは、このランチャーが起動した foreground の claude だけ。
#    background セッション（/bg・← で送ったもの、claude --bg、agent view から dispatch したもの）は
#    background service（supervisor）配下の別プロセスとして起動し直され、構成を「そのディレクトリの
#    settings（env ブロックを含む）＋引き継がれた構成フラグ」から読む。起動元のシェルから届く env は
#    公式に列挙されたものだけ（PATH / CLAUDE_CODE_USE_BEDROCK・CLAUDE_CODE_USE_VERTEX /
#    ANTHROPIC_DEFAULT_*_MODEL / CLAUDE_CODE_EXTRA_BODY。ゲートウェイ変数は条件付き）。
#    それ以外の env（custom.env・setup-environment の値の大半）は dispatch 元ではなく supervisor の env から
#    受け継がれる（2026-10-20 Windows で実測）。supervisor は全端末で共有され、それを立ち上げたプロセスの env を継承する
#    ため、届くかは起動順次第で確実ではない ―― このランチャーから起動した claude が supervisor を立ち上げると、
#    以後は別の端末から dispatch した background セッションにも届き、dispatch 元に同名の値があっても supervisor
#    側の値が使われる。素のシェル等が先に立ち上げていると、このランチャー経由の claude --bg でも届かない
#    （例: CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD が欠け、--add-dir だけが引き継がれる）。
#    その env は supervisor が止まるまで（claude daemon stop --any 等）使われ、auto-update による自己再起動でも変わらない。
#    background にも効かせたい値は OS の環境変数（永続的なユーザー環境変数。Windows はユーザー環境変数、
#    macOS / Linux はログインシェルの profile）で設定すること。supervisor は最初に起動したシェルの env を
#    継承するので、どの端末から起動されても届く（既に動いている service には、それが起動した時点の env が使われる）。
#    公式 docs は ~/.claude/settings.json の env を勧めるが、キットは利用者に settings 系ファイルの
#    env を使わせない（誤って commit / push する、Claude から読める場所に値が残る、を避けるため）。組織で固定する値だけは managed settings の env（管理者の経路）に置く。
#    起動オプションは構成フラグ（--settings / --setting-sources / --add-dir / --plugin-dir / --mcp-config /
#    --strict-mcp-config / --fallback-model / --allow-dangerously-skip-permissions）だけが background へ引き継がれる。
#    参照: https://code.claude.com/docs/en/agent-view#settings-and-provider
# ⚠ サブコマンド（agents / remote-control など）はこのランチャー経由で起動しないこと。組み立てた起動
#    オプションが verb の「前」に付くため、remote-control は --settings 等が前にあると起動を拒否し、
#    agents は --add-dir / --mcp-config が前にあると `claude agents --json` が unknown option で失敗する
#    （claude --bg "<prompt>" のようなフラグ形式の background 起動は問題ない）。
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
#   - 値を 1 つだけ取るフラグは TEAM_OPTS が後段に付くためチーム値が後勝ちになる
#   - ただし起動時引数（"$@"）はさらに後ろに付くので、利用者が明示指定すれば上書きできる
#   - --add-dir のような反復可能フラグは上書きされず両方の値が渡る（累積する）
#   - 例外: --append-system-prompt とその -file 版は上書きではなく両方が使われる（v2.1.283 以降）。
#     --append-subagent-system-prompt とその -file 版は併用できない（OPTS と TEAM_OPTS に分けて書くとエラー）
# 強制したい統制は settings.json / managed settings 側で行うこと。ただし permissions.defaultMode の
#   auto / bypassPermissions はプロジェクトの .claude/settings.json / settings.local.json では無視される
#   （効かせるなら ~/.claude/settings.json または managed settings）。--permission-mode フラグは
#   settings の defaultMode より優先される。
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

# option-settings（OPTS）と TEAM_OPTS の --add-dir がネットワークパス（UNC）の形なら起動前に警告する（止めない）。
# Claude Code は起動時に渡されたネットワークパスを外して起動し（v2.1.257 以降）、v2.1.305 以降の対話起動ではその警告が
# デバッグログにしか出ない。<Share> を UNC で書くとキット無しで黙って起動するので、画面に出せるランチャーが知らせる。
# チームが <Share> を固定するのは TEAM_OPTS なので、そこも同じ判定で見る（2026-10-27 の判断 J-3。それまでは option-settings
# だけ）。警告文の先頭で値の出どころ（option-settings か TEAM_OPTS か）を示し、順は OPTS → TEAM_OPTS（PS 版と同じ）。
# 判定は綴りだけ（\\ か // で始まるか。解決するとネットワークへ触れてしまう）。起動時引数の --add-dir は見ない（利用者が
# 並べた引数は守らない。設計 §5-3 の責任分界）。[--add-dir=<パス>] のような = 形のキーも見ない（キーが --add-dir そのものの
# 値だけ。設計 §5-4）。本文は PS 版と同じ文言（出どころの表記も同じ）で、前置きだけ違う（bash 版は「⚠ 」、PS 版は
# 「警告: 」。PS 版は CP932 で書く [Console]::Error に ⚠ を使わない）。
_warn_unc_add_dir() { # $1=値の出どころ（警告文の先頭に出す） $2=--add-dir の値
  case "$2" in
    '\\'*|'//'*)
      printf '⚠ %s の --add-dir %s はネットワークパスの形です。ネットワークパスは v2.1.257 以降拒否され、v2.1.305 以降は警告がデバッグログにしか出ないため、Claude Code はこのディレクトリを黙って外して起動します。ドライブ文字に割り当てて指定してください。\n' \
        "$1" "$2" >&2 ;;
  esac
}
_warn_unc_add_dir 'option-settings' "${OPTS[--add-dir]:-}"
_warn_unc_add_dir 'start_claude_code のチーム統制（TEAM_OPTS / $TeamOpts）' "${TEAM_OPTS[--add-dir]:-}"

# ---- 4) claude コマンドを組み立て ------------------------------------------
# TEAM_OPTS を後に置くことで、同じフラグを OPTS にも書いた場合はチーム値が後勝ちする。
_args=()
_append_opts() {
  local -n _map="$1"
  local k v
  local -a _keys=()
  # 連想配列の列挙順は不定（ハッシュ順）なので、キーをソートして組立順を決定的にする。
  # 空のまま printf '%s\0' に渡すと NUL が 1 個出て空キー（＝空文字の引数）になるため、先に抜ける。
  if [ "${#_map[@]}" -eq 0 ]; then
    return 0
  fi
  mapfile -d '' -t _keys < <(printf '%s\0' "${!_map[@]}" | LC_ALL=C sort -z)
  for k in "${_keys[@]}"; do
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

# 値を複数取る／値を省略できるフラグが _args の最後だと、直後のプロンプトを値として取り込む（冒頭の注意）。
# 起動時引数が全部非フラグ（＝プロンプトだけ）のときに限り -- で区切る。フラグを含む場合（混在を含む）は
# 素の claude と同じく利用者の並べ方に任せる。組み立てたオプションが無いときは素の claude と同じ引数列にする。
if [ "${#_args[@]}" -gt 0 ] && [ "$#" -gt 0 ]; then
  _only_positional=1
  for _a in "$@"; do
    case "$_a" in
      -*) _only_positional=0; break ;;
    esac
  done
  if [ "${_only_positional}" -eq 1 ]; then
    _args+=("--")
  fi
fi

# ---- 5) 起動（追加引数はそのまま claude へ委譲）------------------------------
exec claude "${_args[@]}" "$@"
