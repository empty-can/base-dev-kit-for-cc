#!/usr/bin/env bash
# publish-share.sh — <Dev>（本リポジトリ）の .claude を共有本体 basic_dot_claude へ publish する
#
# これは Sync A（手動・公開前ゲート付き）。session 開始時の自動同期（refresh / pull --ff-only）
# とは別物で、「develop→main を経た release-ready な .claude を共有本体へ反映する」意図的な操作。
# refresh では決して push しない／publish はここでしか push しない。
#
# 使い方:   ./scripts/publish-share.sh [basic_dot_claude のローカルパス]
#           省略時は既定 C:/cc-workspace/basic_dot_claude
# 前提:     main ブランチで実行（公開基準）。
# 終了コード: ゲート失敗・エラーで非0。
set -uo pipefail

DEV_ROOT="$(git rev-parse --show-toplevel)"
SHARE_BODY="${1:-C:/cc-workspace/basic_dot_claude}"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ -d "$SHARE_BODY/.git" ] || { echo "‼ 共有本体（basic_dot_claude のクローン）が見つからない: $SHARE_BODY" >&2; exit 2; }

# 1. 公開基準ブランチ（main）確認
branch="$(git -C "$DEV_ROOT" rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || { echo "‼ publish は main で実行してください（現在: $branch）" >&2; exit 1; }

# 2. 衛生ゲート: check-assets（個人ファイル混入・無視されるキー・JSON 不正を検出。FAIL で中止）
bash "$HERE/check-assets.sh" "$DEV_ROOT" || { echo "‼ check-assets FAIL。publish 中止" >&2; exit 1; }

# 3. /security-review は対話コマンドのため手動確認（リマインド）
read -r -p "→ Claude Code で /security-review を実行済みなら y で続行: " ok
[ "$ok" = "y" ] || { echo "中止"; exit 1; }

# 4. .claude の「Git 追跡ファイルのみ」を共有本体へミラー（個人/未追跡ファイルは構造的に除外される）
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$DEV_ROOT" archive HEAD .claude | tar -x -C "$tmp"   # tracked のみ → $tmp/.claude/
# 共有本体のリポ・メタ（.git/README/LICENSE/.gitignore）は残し、資産だけを総入れ替え
find "$SHARE_BODY" -mindepth 1 -maxdepth 1 \
  ! -name '.git' ! -name '.gitignore' ! -name 'README.md' ! -name 'LICENSE' \
  -exec rm -rf {} +
cp -R "$tmp/.claude/." "$SHARE_BODY/"

# 5. 共有本体を commit & push
git -C "$SHARE_BODY" add -A
if git -C "$SHARE_BODY" diff --cached --quiet; then
  echo "変更なし。publish 不要"; exit 0
fi
git -C "$SHARE_BODY" commit -m "publish: sync .claude from base-dev-kit-for-cc@$(git -C "$DEV_ROOT" rev-parse --short HEAD)"
git -C "$SHARE_BODY" push

echo "✓ publish 完了。参照ハブ（basic_cc_project）側で submodule を bump してください:"
echo "    git -C <basic_cc_project> submodule update --remote .claude"
echo "    git -C <basic_cc_project> add .claude && git -C <basic_cc_project> commit -m 'chore: bump .claude' && git -C <basic_cc_project> push"
