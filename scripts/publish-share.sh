#!/usr/bin/env bash
# publish-share.sh — 指定 ref の .claude を共有本体 basic_dot_claude へ publish する（Sync A・手動ゲート）
#
# session 開始時の自動同期（refresh / pull --ff-only）とは別物。release-ready な .claude を
# 共有本体へ反映する意図的な操作で、publish はここでしか push しない。
# publish 対象は ref で明示指定する（既定値は無い）。checkout 不要で任意 ref を publish できる。
#
# 使い方:
#   ./scripts/publish-share.sh --ref <ref> [--share <basic_dot_claude のパス>]
#     --ref    publish する .claude の取り出し元 ref（必須）
#     --share  共有本体クローンのパス（既定: C:/cc-workspace/basic_dot_claude）
# 例:
#   ./scripts/publish-share.sh --ref v1.0.0                # リリースタグを publish
#   ./scripts/publish-share.sh --ref chore/groom-as-share  # 指定ブランチを publish（検証 run 等）
#
# ⚠ --ref に既定値を持たせない理由: かつて既定は main だったが、未 grooming の ref を
#    無自覚に publish する事故（内部レポートの公開リポ流出）を招く。publish する ref は
#    毎回意識して選ぶこと。payload に成果物が混入していれば check-assets が FAIL させる。
# 終了コード: ゲート失敗・エラーで非0。
set -uo pipefail

REF=""
SHARE_BODY="C:/cc-workspace/basic_dot_claude"
while [ $# -gt 0 ]; do
  case "$1" in
    --ref)   REF="${2:?--ref に値が必要}"; shift 2;;
    --share) SHARE_BODY="${2:?--share に値が必要}"; shift 2;;
    *) echo "‼ 不明な引数: $1（使い方: $0 --ref <ref> [--share <path>]）" >&2; exit 2;;
  esac
done

[ -n "$REF" ] || {
  echo "‼ --ref は必須です（既定値は廃止）。publish する ref を明示してください。" >&2
  echo "   例: $0 --ref v1.0.0" >&2
  exit 2; }

# 開発リポの位置はスクリプトの場所から解決する（CWD に依存させない。
# 別リポジトリ内から実行して、そのリポの .claude を publish してしまう事故を防ぐ）。
HERE="$(cd "$(dirname "$0")" && pwd)"
DEV_ROOT="$(cd "$HERE/.." && pwd)"
git -C "$DEV_ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "‼ 開発リポジトリが見つからない: $DEV_ROOT" >&2; exit 2; }

# 共有本体の検査: .git が「ディレクトリ」であること（submodule の .git はファイル＝gitlink）。
# かつ、指定パスがそのリポジトリのルートそのものであること。
# これを緩めると、submodule の checkout（例: basic_cc_project/.claude）を配布先に指定でき、
# ミラー処理が gitlink を壊して親リポジトリへ commit/push してしまう。
[ -d "$SHARE_BODY/.git" ] || {
  echo "‼ 共有本体（basic_dot_claude のクローン）が見つからない: $SHARE_BODY" >&2
  echo "   .git がディレクトリである独立クローンを指定してください（submodule の checkout は不可）。" >&2
  exit 2; }
_share_abs="$(cd "$SHARE_BODY" && pwd)"
_share_top="$(git -C "$SHARE_BODY" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$_share_top" ] && [ "$_share_abs" = "$_share_top" ] || {
  echo "‼ 共有本体はリポジトリのルートを指す必要があります: $SHARE_BODY" >&2
  echo "   （検出したルート: ${_share_top:-不明}）" >&2
  exit 2; }

git -C "$DEV_ROOT" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1 || { echo "‼ ref が存在しない: $REF" >&2; exit 2; }

# 1. 追跡ファイルのみを ref から取り出し（checkout 不要・個人/未追跡は構造的に除外）
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$DEV_ROOT" archive "$REF" .claude | tar -x -C "$tmp"   # → $tmp/.claude/

# 2. 安全弁: 取り出した .claude が空なら中止（共有本体の空上書きを防止）
[ -d "$tmp/.claude" ] && [ -n "$(ls -A "$tmp/.claude" 2>/dev/null)" ] || {
  echo "‼ $REF の .claude が空。publish 中止（共有本体を空で上書きしない）" >&2; exit 1; }

# 3. 衛生ゲート: check-assets を「取り出した実体」に対して実行（実際に publish する中身を検査）
bash "$HERE/check-assets.sh" "$tmp" || { echo "‼ check-assets FAIL。publish 中止" >&2; exit 1; }

# 4. /security-review は対話コマンドのため手動確認
read -r -p "→ $REF の内容について /security-review を実行済みなら y で続行: " ok
[ "$ok" = "y" ] || { echo "中止"; exit 1; }

# 5. 共有本体へミラー
#    dest 直下の資産だけを消し（.git とメタ 3 種は残す）、payload を上書きコピーする。
#    keep-list は「削除から守る」意味であって「payload より優先する」意味ではない。
#    payload に .gitignore 等が含まれる場合は payload 側が正（配布先の統制ファイルを
#    開発リポで一元管理するため）。PowerShell 版と挙動を揃えること。
find "$SHARE_BODY" -mindepth 1 -maxdepth 1 \
  ! -name '.git' ! -name '.gitignore' ! -name 'README.md' ! -name 'LICENSE' \
  -exec rm -rf {} +
cp -R "$tmp/.claude/." "$SHARE_BODY/"

# 6. 共有本体を commit & push
git -C "$SHARE_BODY" add -A || { echo "‼ add 失敗。publish 中止" >&2; exit 1; }
if git -C "$SHARE_BODY" diff --cached --quiet; then echo "変更なし。publish 不要"; exit 0; fi
git -C "$SHARE_BODY" commit -m "publish: sync .claude from base-dev-kit-for-cc@$(git -C "$DEV_ROOT" rev-parse --short "$REF") (ref: $REF)" || {
  echo "‼ commit 失敗。publish は完了していない" >&2; exit 1; }
git -C "$SHARE_BODY" push || {
  echo "‼ push 失敗。publish は完了していない（共有本体にローカルコミットが残っている）" >&2
  echo "   認証・保護ブランチ設定を確認し、$SHARE_BODY で push し直してください。" >&2
  exit 1; }

echo "✓ publish 完了（ref: $REF）。参照ハブ（basic_cc_project）で submodule を bump してください:"
echo "    git -C <basic_cc_project> submodule update --remote .claude"
echo "    git -C <basic_cc_project> add .claude && git -C <basic_cc_project> commit -m 'chore: bump .claude' && git -C <basic_cc_project> push"
