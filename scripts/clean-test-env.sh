#!/usr/bin/env bash
# clean-test-env.sh — クリーン隔離テスト環境を作って Claude Code を起動する（手順書 §5）
#
# 自分の ~/.claude / project 設定を切り離し、配布する <Share> の共有資産だけを検証する。
# 空の CLAUDE_CONFIG_DIR と、.claude / CLAUDE.md / .mcp.json を持たない空の作業ディレクトリを作り、
# <Share> を --add-dir / 環境変数 / --settings で結合して起動する。
#
# 使い方:
#   ./clean-test-env.sh [<Share-path>]
#     <Share-path> 省略時は結合なしの素のクリーンセッション（バイセクトの起点に使う）。
#   KEEP=1 ./clean-test-env.sh <Share>   # 終了後に一時ディレクトリを残す（既定は削除）
#   PERMISSION_MODE=auto ./clean-test-env.sh <Share>   # 起動モードを変える（既定 default。組み込み既定は版で変わるため固定している）
#     値は default / acceptEdits / plan / auto / dontAsk / bypassPermissions / manual のいずれか（大文字小文字を区別）。
#     それ以外は起動前に exit 2 で止める（PS 版の -PermissionMode と同じ値集合・同じメッセージ）。
#
# 注意:
#   - managed settings は system パスにあるためクリーンセッションでも適用され続ける。
#   - 認証情報は config dir ごとに分かれるため、初回は再ログインを求められる（全 OS。macOS も
#     Keychain エントリが CLAUDE_CONFIG_DIR ごとに別になる。ANTHROPIC_API_KEY 等の環境変数での認証は除く）。
#   - claude.ai アカウントの skills / plugins / connectors はクリーン config dir の settings.json で止めている。
#   - --settings は user settings と同格に効くため、本テストで観察できるのは方法 B（--add-dir + --settings）の
#     挙動であって、.claude/ を project として置く方法 A の挙動ではない（check-assets 3. の WARN 対象キーの扱いが違う）。
set -uo pipefail

SHARE="${1:-}"

# 権限モードの検証は、一時ディレクトリを作るより前に済ませる（PS 版と同じ順序・同じメッセージ・同じ終了コード）。
# 大文字小文字を区別する（claude に渡す値は公式の綴りに限る。以前の PS 版は ValidateSet が区別せず、AUTO をそのまま渡していた）。
# 既定値の default を使うのは未設定のときだけ（${…-…}）。設定済みで空の値は不正値として止める（PS 版の -PermissionMode '' と
# 同じ。以前の ${PERMISSION_MODE:-default} は空を黙って default にしていた）。
PERMISSION_MODE="${PERMISSION_MODE-default}"
case "$PERMISSION_MODE" in
  default|acceptEdits|plan|auto|dontAsk|bypassPermissions|manual) ;;
  *)
    echo "‼ 権限モードが不正: '$PERMISSION_MODE'（default / acceptEdits / plan / auto / dontAsk / bypassPermissions / manual のいずれか。大文字小文字を区別する）" >&2
    exit 2;;
esac

# <Share> の検査も一時ディレクトリを作るより前に済ませる（PS 版と同じ順序・同じ文言・同じ終了コード・stderr）。
# 以前は mktemp の後にあり、不正な <Share> でも一時ディレクトリの作成・削除の表示が出て、KEEP=1 なら残骸が残った。
SHARE_ABS=""
if [[ -n "$SHARE" ]]; then
  if [[ ! -d "$SHARE" ]]; then echo "‼ <Share> が見つかりません: $SHARE" >&2; exit 1; fi
  SHARE_ABS="$(cd "$SHARE" && pwd)"
fi

CFG="$(mktemp -d -t cc-clean-cfg-XXXXXX)"
WORK="$(mktemp -d -t cc-clean-work-XXXXXX)"

cleanup() {
  if [[ "${KEEP:-0}" == "1" ]]; then
    echo "[clean-test-env] 一時ディレクトリを残しました: $CFG  $WORK"
  else
    rm -rf "$CFG" "$WORK"
    echo "[clean-test-env] 一時ディレクトリを削除しました（残すには KEEP=1）"
  fi
}
trap cleanup EXIT

echo "[clean-test-env] CLAUDE_CONFIG_DIR = $CFG"
echo "[clean-test-env] 作業ディレクトリ   = $WORK"

export CLAUDE_CONFIG_DIR="$CFG"
# アカウント同期で <Share> 以外の skills / plugins / connectors が混入するのを止める（v2.1.275 以降、
# claude.ai アカウントでログインした端末セッションは、アカウントで有効な skills / plugins を
# config dir 配下へ自動で取り込んで読み込む）。クリーン config dir の user settings として置く。
printf '%s\n' '{"syncClaudeAiSkills": false, "syncClaudeAiPlugins": false, "disableClaudeAiConnectors": true}' > "$CFG/settings.json"
# CLAUDE_CONFIG_DIR を差し替えても、環境変数で直接読み込まれる plugin は切り離せない
# （CLAUDE_CODE_PLUGIN_DIRS は --plugin-dir と同じ扱いで読み込まれる。v2.1.280〜）。呼び出し元から継がない。
unset CLAUDE_CODE_PLUGIN_DIRS CLAUDE_CODE_PLUGIN_SEED_DIR CLAUDE_CODE_PLUGIN_CACHE_DIR
# 資産の読み込み自体を止める変数が呼び出し元にあると、検証が黙って無意味になる
for _v in CLAUDE_CODE_SAFE_MODE CLAUDE_CODE_SIMPLE CLAUDE_CODE_RESTRICTED CLAUDE_CODE_DISABLE_CLAUDE_MDS; do
  [[ -n "${!_v:-}" ]] && echo "[clean-test-env] ⚠ $_v=${!_v} が設定されている（<Share> の資産が読み込まれない）"
done

# 起動時の権限モードを固定する。未指定だと Claude Code の組み込み既定に従い、その既定は版で
# 変わっている（v2.1.283〜 端末の対話セッションは auto）。クリーン config dir には user の
# defaultMode も無いため、固定しないと検証結果が CC の版に依存する。
cli=(--permission-mode "$PERMISSION_MODE")
echo "[clean-test-env] 起動モード: --permission-mode $PERMISSION_MODE"

if [[ -n "$SHARE_ABS" ]]; then
  cli+=(--add-dir "$SHARE_ABS")
  export CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1   # CLAUDE.md / .claude/CLAUDE.md / .claude/rules/*.md / CLAUDE.local.md も結合（skills / agents / commands は変数なしでも来る）
  echo "[clean-test-env] 結合: --add-dir $SHARE_ABS（+ CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1）"
  # ⚠ --settings は「コマンドライン」層で、user settings に置けるキーなら何でも効く（project より強い）。
  #    .claude/ を project として置く方法 A では無視されるキー（check-assets 3 の WARN 対象）も
  #    ここでは有効になるため、本テストの結果は方法 B の挙動であって方法 A の挙動ではない。
  #    なお --setting-sources で project を外してはならない（--add-dir の skills / agents / commands は
  #    project ソース経由でロードされ、外すと <Share> の資産が読み込まれない）。
  if [[ -f "$SHARE_ABS/.claude/settings.json" ]]; then
    cli+=(--settings "$SHARE_ABS/.claude/settings.json")  # --add-dir からは enabledPlugins / extraKnownMarketplaces しか来ないので明示
    echo "[clean-test-env] 結合: --settings $SHARE_ABS/.claude/settings.json"
  fi
fi

echo "[clean-test-env] 起動中... (起動後は /memory /context /status /doctor /skills /agents で検証)"
cd "$WORK"
claude "${cli[@]}"
