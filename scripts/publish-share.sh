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
# 指定パスがリポジトリの「ルート」かを --show-prefix で判定する（空＝ルート）。
#
# ⚠ パス文字列を比較してはいけない。同じ場所を指す複数の表記が存在するため:
#   - Git Bash: rev-parse は C:/... を返し pwd は /c/... を返す
#   - MSYS のマウント別名: /c/Users/<user>/AppData/Local/Temp/... と /tmp/... は同一
#   - macOS: /tmp は /private/tmp への symlink
# いずれも「正しい配布先を誤って拒否する」形で効く。--show-prefix なら表記に依存しない。
_share_prefix="$(git -C "$SHARE_BODY" rev-parse --show-prefix 2>/dev/null)"
if [ $? -ne 0 ] || [ -n "$_share_prefix" ]; then
  echo "‼ 共有本体はリポジトリのルートを指す必要があります: $SHARE_BODY" >&2
  echo "   （リポジトリ内のサブディレクトリを指しています: ${_share_prefix:-判定不能}）" >&2
  exit 2
fi

git -C "$DEV_ROOT" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1 || { echo "‼ ref が存在しない: $REF" >&2; exit 2; }

# 0. symlink（mode 120000）を含む ref は publish しない。
#    bash 版は tar が symlink の展開に失敗するので後段の検査で止まるが、PowerShell 版は
#    zip 経由のため「ターゲットのパス文字列を中身とする通常ファイル」として配布してしまう
#    （データが化けたまま公開される）。実行者の OS でリリース可否が変わらないよう、
#    ref の段階で両版とも止める。PowerShell 版の 0 と対称。
_links="$(git -C "$DEV_ROOT" ls-tree -r "$REF" -- .claude | awk -F'\t' '$1 ~ /^120000 / { print $2 }')"
if [ -n "$_links" ]; then
  echo "‼ payload に symlink が含まれている。publish 中止（配布先で壊れたファイルになる）:" >&2
  echo "$_links" | sed 's/^/   /' >&2
  exit 1
fi

# 1. 追跡ファイルのみを ref から取り出し（checkout 不要・個人/未追跡は構造的に除外）
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# ⚠ core.autocrlf を明示的に無効化する。git archive は working-tree 変換（text/eol 属性 ＋
#    core.autocrlf）を適用するため、これを付けないと publisher のローカル設定で payload の
#    中身が変わる。Git for Windows の既定は autocrlf=true なので、普通に clone した Windows
#    開発者が publish すると配布リポのほぼ全ファイルが CRLF で書き換わり、同じ ref なのに
#    publish するマシン次第で配布内容が変わる（実測: 19 ファイル中 18 ファイルの blob が相違）。
#    eol=crlf 属性を持つファイル（launcher/*.ps1）は属性が優先されるため CRLF のまま。
#    PowerShell 版と対称にすること。
# ⚠ 展開の成否を必ず検査する。取りこぼしたまま先へ進むと、後段のミラー処理が
#    「payload に無い」と見なして配布先の該当ファイルを削除してしまう。
#    （tar は不正なファイル名・長すぎるパス等で個別エントリの展開に失敗し得る）
if ! git -c core.autocrlf=false -C "$DEV_ROOT" archive "$REF" .claude | tar -x -C "$tmp"; then   # → $tmp/.claude/
  echo "‼ $REF の payload を展開できない。publish 中止（部分的な payload で配布先を壊さない）" >&2
  exit 1
fi

# 2. 安全弁: 取り出した .claude が空なら中止（共有本体の空上書きを防止）
[ -d "$tmp/.claude" ] && [ -n "$(ls -A "$tmp/.claude" 2>/dev/null)" ] || {
  echo "‼ $REF の .claude が空。publish 中止（共有本体を空で上書きしない）" >&2; exit 1; }

# 2-b. 安全弁: 展開したファイル数が ref の追跡ファイル数と一致するか（fail-closed）
#      tar がエラーを出しても終了コードに現れないケースがあるため、件数でも裏を取る。
#      PowerShell 版の 2-b と対称（片方の OS だけ防御が無い状態を作らない）。
_expected="$(git -C "$DEV_ROOT" ls-tree -r --name-only "$REF" -- .claude | wc -l)"
_actual="$(find "$tmp/.claude" -type f | wc -l)"
if [ "$_expected" -ne "$_actual" ]; then
  echo "‼ payload の展開に失敗（期待 ${_expected} ファイル / 実際 ${_actual} ファイル）。publish 中止" >&2
  echo "   ファイル名の文字コード・symlink・パス長が原因の可能性があります。" >&2
  exit 1
fi

# 3. 衛生ゲート: check-assets を「取り出した実体」に対して実行（実際に publish する中身を検査）
#    --payload で実体基準を強制する。付けないと、TMPDIR が git worktree 配下のマシンでは
#    check-assets が payload を「追跡基準」で検査してしまい、成果物の混入も統制ファイルの
#    不在も WARN へ退化してゲートが素通しになる（呼び出し側は層を知っているのだから明示する）。
bash "$HERE/check-assets.sh" --payload "$tmp" || { echo "‼ check-assets FAIL。publish 中止" >&2; exit 1; }

# 4. /security-review は対話コマンドのため手動確認
read -r -p "→ $REF の内容について /security-review を実行済みなら y で続行: " ok
[ "$ok" = "y" ] || { echo "中止"; exit 1; }

# 5. 共有本体へミラー
#    dest 直下の資産だけを消し（.git とメタ 3 種は残す）、payload を上書きコピーする。
#    keep-list は「削除から守る」意味であって「payload より優先する」意味ではない。
#    payload に .gitignore 等が含まれる場合は payload 側が正（配布先の統制ファイルを
#    開発リポで一元管理するため）。PowerShell 版と挙動を揃えること。
#    ⚠ 各手順の失敗を必ず検査する（set -e は使っていない）。素通しにすると rm や cp が
#       部分的に失敗しても後段の commit/push へ進み、混合状態や削除だけのコミットが
#       「✓ publish 完了」の表示とともに公開される。publish-plugin.sh の 5 と対称。
find "$SHARE_BODY" -mindepth 1 -maxdepth 1 \
  ! -name '.git' ! -name '.gitignore' ! -name '.gitattributes' ! -name 'README.md' ! -name 'LICENSE' \
  -exec rm -rf {} + || { echo "‼ 共有本体の旧資材を削除できない: $SHARE_BODY。publish 中止" >&2; exit 1; }
cp -R "$tmp/.claude/." "$SHARE_BODY/" || { echo "‼ 共有本体へコピーできない: $SHARE_BODY。publish 中止" >&2; exit 1; }

# 5-b. 出口検査: 配布先に着地したファイル数が payload と一致するか（2-b と対称の fail-closed）
#      keep-list（README.md / LICENSE 等）は payload に無くても残るため、payload 側の
#      ファイルが全て存在するかで照合する。
_missing=0
while IFS= read -r -d '' _f; do
  _rel="${_f#"$tmp/.claude/"}"
  [ -e "$SHARE_BODY/$_rel" ] || { echo "   欠落: $_rel" >&2; _missing=$((_missing + 1)); }
done < <(find "$tmp/.claude" -type f -print0)
if [ "$_missing" -ne 0 ]; then
  echo "‼ ミラーの結果に payload のファイルが ${_missing} 件欠落している。publish 中止" >&2
  exit 1
fi

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
