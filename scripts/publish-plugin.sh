#!/usr/bin/env bash
# publish-plugin.sh — <Dev>(C-BDK) の指定 ref のプラグインを Marketplace リポジトリ <C-MKT> へ publish（層2・validate ゲート）
#
# publish-share.sh（層1 body の publish）の plugin 版。release-ready なプラグインを marketplace
# リポジトリへコピーし commit/push する意図的な公開操作で、push はここでしか行わない。
#
# 使い方:
#   ./scripts/publish-plugin.sh --marketplace <C-MKT のパス> --ref <ref> [--plugin <repo相対pluginディレクトリ>] [--name <plugin名>]
#     --marketplace  marketplace リポジトリ（<C-MKT>）クローンのパス（必須）
#     --ref          取り出し元 ref（必須）
#     --plugin       publish するプラグインの repo 相対ディレクトリ（既定: plugin）
#     --name         marketplace 内の plugin 名（既定: --plugin のベース名）
#
# 前提: `claude` CLI が PATH 上にあること（plugin validate ゲートに使用）。
# 終了コード: ゲート失敗・エラーで非0。
# 注記（ドラフト）: プラグイン組成フェーズ未了のため既定 --plugin=plugin は仮。marketplace.json の
#   エントリ整備は本スクリプト範囲外（コピー後にリマインドを表示）。
#
# ⚠ 本スクリプトは publish-share.sh と同じ防御を持たせること（片方だけ直した状態を作らない）。
#    --ref 必須 / DEV_ROOT の CWD 非依存 / 配布先ルート検査 / symlink 拒否 /
#    core.autocrlf=false / 展開の fail-closed / commit・push 失敗の検知 の 7 点。
set -uo pipefail

REF=""
PLUGIN_DIR="plugin"
MARKETPLACE=""
NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ref)         REF="${2:?--ref に値が必要}"; shift 2;;
    --plugin)      PLUGIN_DIR="${2:?--plugin に値が必要}"; shift 2;;
    --marketplace) MARKETPLACE="${2:?--marketplace に値が必要}"; shift 2;;
    --name)        NAME="${2:?--name に値が必要}"; shift 2;;
    *) echo "‼ 不明な引数: $1（使い方: $0 --marketplace <path> --ref <ref> [--plugin <dir>] [--name <name>]）" >&2; exit 2;;
  esac
done
[ -n "$MARKETPLACE" ] || { echo "‼ --marketplace <C-MKT のパス> が必要" >&2; exit 2; }

# ⚠ --ref に既定値を持たせない（publish-share.sh と同じ理由）。かつて既定は main だったが、
#    意図しない ref を無自覚に publish する事故を招く。publish する ref は毎回意識して選ぶ。
[ -n "$REF" ] || {
  echo "‼ --ref は必須です（既定値は廃止）。publish する ref を明示してください。" >&2
  echo "   例: $0 --marketplace <path> --ref v1.0.0" >&2
  exit 2; }
[ -n "$NAME" ] || NAME="$(basename "$PLUGIN_DIR")"

# 開発リポの位置はスクリプトの場所から解決する（CWD に依存させない。別リポジトリ内から
# 実行して、そのリポのプラグインを publish してしまう事故を防ぐ）。
HERE="$(cd "$(dirname "$0")" && pwd)"
DEV_ROOT="$(cd "$HERE/.." && pwd)"
git -C "$DEV_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "‼ 開発リポジトリが見つからない: $DEV_ROOT" >&2; exit 2; }

# marketplace の検査: .git が「ディレクトリ」であること（submodule の .git はファイル＝gitlink）。
# かつ、指定パスがそのリポジトリのルートそのものであること。緩めると submodule の checkout を
# 配布先に指定でき、ミラー処理が gitlink を壊して親リポジトリへ commit/push してしまう。
[ -d "$MARKETPLACE/.git" ] || {
  echo "‼ marketplace リポジトリが見つからない: $MARKETPLACE" >&2
  echo "   .git がディレクトリである独立クローンを指定してください（submodule の checkout は不可）。" >&2
  exit 2; }
# ルート判定はパス文字列の比較ではなく --show-prefix の空判定で行う（Git Bash の C:/ と /c/、
# MSYS のマウント別名、macOS の /tmp→/private/tmp など、同じ場所を指す表記が複数あるため）。
_mkt_prefix="$(git -C "$MARKETPLACE" rev-parse --show-prefix 2>/dev/null)"
if [ $? -ne 0 ] || [ -n "$_mkt_prefix" ]; then
  echo "‼ marketplace はリポジトリのルートを指す必要があります: $MARKETPLACE" >&2
  echo "   （リポジトリ内のサブディレクトリを指しています: ${_mkt_prefix:-判定不能}）" >&2
  exit 2
fi

git -C "$DEV_ROOT" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1 || { echo "‼ ref が存在しない: $REF" >&2; exit 2; }

# 0. symlink（mode 120000）を含む ref は publish しない。bash は tar が展開に失敗して止まるが、
#    PowerShell は zip 経由のため「ターゲットのパス文字列を中身とする通常ファイル」を配布して
#    しまう。実行者の OS でリリース可否が変わらないよう ref の段階で両版とも止める。
_links="$(git -C "$DEV_ROOT" ls-tree -r "$REF" -- "$PLUGIN_DIR" | awk -F'\t' '$1 ~ /^120000 / { print $2 }')"
if [ -n "$_links" ]; then
  echo "‼ plugin に symlink が含まれている。publish 中止（配布先で壊れたファイルになる）:" >&2
  echo "$_links" | sed 's/^/   /' >&2
  exit 1
fi

# 1. 追跡ファイルのみを ref から取り出し（checkout 不要・個人/未追跡は構造的に除外）
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# ⚠ core.autocrlf を明示的に無効化する。git archive は working-tree 変換（text/eol 属性 ＋
#    core.autocrlf）を適用するため、付けないと publisher のローカル設定で中身が変わる
#    （Git for Windows の既定は autocrlf=true）。eol=crlf 属性を持つファイルは属性が優先される。
# ⚠ 展開の成否を必ず検査する。取りこぼしたまま進むと、後段のミラーが「payload に無い」と
#    見なして配布先の該当ファイルを削除してしまう。
if ! git -c core.autocrlf=false -C "$DEV_ROOT" archive "$REF" "$PLUGIN_DIR" | tar -x -C "$tmp"; then
  echo "‼ $REF から $PLUGIN_DIR を取り出せない（パス誤り? 未コミット? 展開失敗?）。publish 中止" >&2
  exit 1
fi
SRC="$tmp/$PLUGIN_DIR"

# 2. 安全弁: 取り出したプラグインが空 / manifest 不在なら中止
[ -d "$SRC" ] && [ -n "$(ls -A "$SRC" 2>/dev/null)" ] || { echo "‼ $REF の $PLUGIN_DIR が空。中止" >&2; exit 1; }
[ -f "$SRC/.claude-plugin/plugin.json" ] || { echo "‼ $PLUGIN_DIR/.claude-plugin/plugin.json が無い（plugin ではない?）。中止" >&2; exit 1; }

# 2-b. 安全弁: 展開したファイル数が ref の追跡ファイル数と一致するか（fail-closed）
#      tar がエラーを出しても終了コードに現れないケースがあるため、件数でも裏を取る。
_expected="$(git -C "$DEV_ROOT" ls-tree -r --name-only "$REF" -- "$PLUGIN_DIR" | wc -l)"
_actual="$(find "$SRC" -type f | wc -l)"
if [ "$_expected" -ne "$_actual" ]; then
  echo "‼ plugin の展開に失敗（期待 ${_expected} ファイル / 実際 ${_actual} ファイル）。publish 中止" >&2
  echo "   ファイル名の文字コード・symlink・パス長が原因の可能性があります。" >&2
  exit 1
fi

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

# 6. commit & push（失敗を握りつぶさない。publish 未完了なのに ✓ を出さない）
git -C "$MARKETPLACE" add -A || { echo "‼ add 失敗。publish 中止" >&2; exit 1; }
if git -C "$MARKETPLACE" diff --cached --quiet; then echo "変更なし。publish 不要"; exit 0; fi
git -C "$MARKETPLACE" commit -m "publish: sync plugin '$NAME' from <Dev>@$(git -C "$DEV_ROOT" rev-parse --short "$REF") (ref: $REF)" || {
  echo "‼ commit 失敗。publish は完了していない" >&2; exit 1; }
git -C "$MARKETPLACE" push || {
  echo "‼ push 失敗。publish は完了していない（marketplace にローカルコミットが残っている）" >&2
  echo "   認証・保護ブランチ設定を確認し、$MARKETPLACE で push し直してください。" >&2
  exit 1; }

echo "✓ plugin '$NAME' を $DEST へ publish 完了（ref: $REF）。"
echo "  ※ <C-MKT>/.claude-plugin/marketplace.json に '$NAME' エントリがあるか確認してください（本スクリプトは marketplace.json を編集しません）。"
