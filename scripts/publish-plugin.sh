#!/usr/bin/env bash
# publish-plugin.sh — <Dev>(C-BDK) の指定 ref のプラグインを Marketplace リポジトリ <C-MKT> へ publish（層2・validate ゲート）
#
# publish-share.sh（層1 body の publish）の plugin 版。release-ready なプラグインを marketplace
# リポジトリへコピーし commit/push する意図的な公開操作で、push はここでしか行わない。
# 取り出しは ref で指定（既定 main＝公開基準）。checkout 不要で任意 ref を publish できる。
#
# 使い方:
#   ./scripts/publish-plugin.sh --marketplace <C-MKT のパス> [--plugin <repo相対pluginディレクトリ>] [--ref <ref>] [--name <plugin名>]
#     --marketplace  marketplace リポジトリ（<C-MKT>）クローンのパス（必須）
#     --plugin       publish するプラグインの repo 相対ディレクトリ（既定: plugin）
#     --ref          取り出し元 ref（既定: main）
#     --name         marketplace 内の plugin 名（既定: --plugin のベース名）
#
# 前提: `claude` CLI が PATH 上にあること（plugin validate ゲートに使用）。
# 終了コード: ゲート失敗・エラーで非0。
# 注記（ドラフト）: プラグイン組成フェーズ未了のため既定 --plugin=plugin は仮。marketplace.json の
#   エントリ整備は本スクリプト範囲外（コピー後にリマインドを表示）。
set -uo pipefail

REF="main"
PLUGIN_DIR="plugin"
MARKETPLACE=""
NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ref)         REF="${2:?--ref に値が必要}"; shift 2;;
    --plugin)      PLUGIN_DIR="${2:?--plugin に値が必要}"; shift 2;;
    --marketplace) MARKETPLACE="${2:?--marketplace に値が必要}"; shift 2;;
    --name)        NAME="${2:?--name に値が必要}"; shift 2;;
    *) echo "‼ 不明な引数: $1（使い方: $0 --marketplace <path> [--plugin <dir>] [--ref <ref>] [--name <name>]）" >&2; exit 2;;
  esac
done
[ -n "$MARKETPLACE" ] || { echo "‼ --marketplace <C-MKT のパス> が必要" >&2; exit 2; }
[ -n "$NAME" ] || NAME="$(basename "$PLUGIN_DIR")"

DEV_ROOT="$(git rev-parse --show-toplevel)"

[ -d "$MARKETPLACE/.git" ] || { echo "‼ marketplace リポジトリが見つからない: $MARKETPLACE" >&2; exit 2; }
git -C "$DEV_ROOT" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1 || { echo "‼ ref が存在しない: $REF" >&2; exit 2; }

# 1. 追跡ファイルのみを ref から取り出し（checkout 不要・個人/未追跡は構造的に除外）
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$DEV_ROOT" archive "$REF" "$PLUGIN_DIR" 2>/dev/null | tar -x -C "$tmp" 2>/dev/null || {
  echo "‼ $REF から $PLUGIN_DIR を取り出せない（パス誤り? 未コミット?）" >&2; exit 1; }
SRC="$tmp/$PLUGIN_DIR"

# 2. 安全弁: 取り出したプラグインが空 / manifest 不在なら中止
[ -d "$SRC" ] && [ -n "$(ls -A "$SRC" 2>/dev/null)" ] || { echo "‼ $REF の $PLUGIN_DIR が空。中止" >&2; exit 1; }
[ -f "$SRC/.claude-plugin/plugin.json" ] || { echo "‼ $PLUGIN_DIR/.claude-plugin/plugin.json が無い（plugin ではない?）。中止" >&2; exit 1; }

# 3. ゲート: claude plugin validate（--strict）
command -v claude >/dev/null 2>&1 || { echo "‼ claude CLI が PATH に無い。validate できないため中止" >&2; exit 1; }
claude plugin validate --strict "$SRC" || { echo "‼ plugin validate FAIL。publish 中止" >&2; exit 1; }

# 4. /security-review は対話コマンドのため手動確認
read -r -p "→ $NAME について /security-review を実行済みなら y で続行: " ok
[ "$ok" = "y" ] || { echo "中止"; exit 1; }

# 5. marketplace へミラー（<C-MKT>/plugins/<name>/ を総入れ替え。.git は保護）
DEST="$MARKETPLACE/plugins/$NAME"
mkdir -p "$DEST"
find "$DEST" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -R "$SRC/." "$DEST/"

# 6. commit & push
git -C "$MARKETPLACE" add -A
if git -C "$MARKETPLACE" diff --cached --quiet; then echo "変更なし。publish 不要"; exit 0; fi
git -C "$MARKETPLACE" commit -m "publish: sync plugin '$NAME' from <Dev>@$(git -C "$DEV_ROOT" rev-parse --short "$REF") (ref: $REF)"
git -C "$MARKETPLACE" push

echo "✓ plugin '$NAME' を $DEST へ publish 完了（ref: $REF）。"
echo "  ※ <C-MKT>/.claude-plugin/marketplace.json に '$NAME' エントリがあるか確認してください（本スクリプトは marketplace.json を編集しません）。"
