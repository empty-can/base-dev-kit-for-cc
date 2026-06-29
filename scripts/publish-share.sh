#!/usr/bin/env bash
# publish-share.sh — 指定 ref の .claude を共有本体 basic_dot_claude へ publish する（Sync A・手動ゲート）
#
# session 開始時の自動同期（refresh / pull --ff-only）とは別物。release-ready な .claude を
# 共有本体へ反映する意図的な操作で、publish はここでしか push しない。
# publish 対象は ref で指定（既定 main＝公開基準）。checkout 不要で任意 ref を publish できる。
#
# 使い方:
#   ./scripts/publish-share.sh [--ref <ref>] [--share <basic_dot_claude のパス>]
#     --ref    publish する .claude の取り出し元 ref（既定: main）
#     --share  共有本体クローンのパス（既定: C:/cc-workspace/basic_dot_claude）
# 例:
#   ./scripts/publish-share.sh                              # main を publish（定常運用）
#   ./scripts/publish-share.sh --ref chore/groom-as-share  # 指定ブランチを publish（理解run 等）
# 終了コード: ゲート失敗・エラーで非0。
set -uo pipefail

REF="main"
SHARE_BODY="C:/cc-workspace/basic_dot_claude"
while [ $# -gt 0 ]; do
  case "$1" in
    --ref)   REF="${2:?--ref に値が必要}"; shift 2;;
    --share) SHARE_BODY="${2:?--share に値が必要}"; shift 2;;
    *) echo "‼ 不明な引数: $1（使い方: $0 [--ref <ref>] [--share <path>]）" >&2; exit 2;;
  esac
done

DEV_ROOT="$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ -d "$SHARE_BODY/.git" ] || { echo "‼ 共有本体（basic_dot_claude のクローン）が見つからない: $SHARE_BODY" >&2; exit 2; }
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

# 5. 共有本体へミラー（メタ .git/README/LICENSE/.gitignore は残し、資産だけを総入れ替え）
find "$SHARE_BODY" -mindepth 1 -maxdepth 1 \
  ! -name '.git' ! -name '.gitignore' ! -name 'README.md' ! -name 'LICENSE' \
  -exec rm -rf {} +
cp -R "$tmp/.claude/." "$SHARE_BODY/"

# 6. 共有本体を commit & push
git -C "$SHARE_BODY" add -A
if git -C "$SHARE_BODY" diff --cached --quiet; then echo "変更なし。publish 不要"; exit 0; fi
git -C "$SHARE_BODY" commit -m "publish: sync .claude from base-dev-kit-for-cc@$(git -C "$DEV_ROOT" rev-parse --short "$REF") (ref: $REF)"
git -C "$SHARE_BODY" push

echo "✓ publish 完了（ref: $REF）。参照ハブ（basic_cc_project）で submodule を bump してください:"
echo "    git -C <basic_cc_project> submodule update --remote .claude"
echo "    git -C <basic_cc_project> add .claude && git -C <basic_cc_project> commit -m 'chore: bump .claude' && git -C <basic_cc_project> push"
