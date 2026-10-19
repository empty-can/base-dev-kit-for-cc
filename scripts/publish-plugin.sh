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
#     --name         marketplace 内の plugin 名（既定: --plugin のベース名）。英数字と . _ - のみ・先頭は英数字・
#                    末尾は . 以外・Windows の予約デバイス名（CON / NUL / COM1 等。拡張子付きも）以外・128 文字以内。
#                    marketplace の plugins/ に大文字小文字だけが違う既存エントリがあれば中止する。
#                    plugin.json の name と一致しなければ中止する（name を読めない場合も中止）
#
# 前提: `claude` CLI が PATH 上にあること（plugin validate ゲートに使用）。
#       python 3（python3 / python の順に探す）が PATH 上にあること（plugin.json の name の照合に使用。無ければ中止）。
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
    --name)
      [ -n "${2:-}" ] || { echo "‼ --name に値が必要（空の名前は指定できない。既定名を使うなら --name を省略する）" >&2; exit 1; }
      NAME="$2"; shift 2;;
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

# plugin.json の name を照合するための python（無ければ 2-a で中止する。照合しないまま先へ進めない）
PY=""; command -v python3 >/dev/null 2>&1 && PY="python3"
[ -z "$PY" ] && command -v python >/dev/null 2>&1 && PY="python"

# NAME はそのまま plugins/<NAME> というパスに連結される。検証しないと `..` や `.` や
# スラッシュ入りの値で DEST が marketplace のルートや plugins/ 自体を指し、後段の
# 「.git 以外を全削除」がそこへ走る（実測: --name .. で全 plugin が消えた状態が push された）。
# 過去の CR-B（submodule を配布先に指定できて親リポを壊す）と同型の入力検証欠如。
# 加えて marketplace のエントリ名（install id の前半）の公式規則（英数字と . _ - のみ・先頭は英数字）に
# 合わない名前は validate が落とし、Claude Code は install できない。この規則は '.' '..' '/' '\' も構造的に排除する。
# ⚠ [A-Za-z] はロケールで意味が変わるため LC_ALL=C の grep で判定し、改行入りの値は先に弾く（grep は行単位）。
# ⚠ 末尾が . の名前も拒否する。Windows はパスの末尾のドットを落とすため plugins/foo. が既存の plugins/foo を指し、
#    後段のミラー（.git 以外を全削除）が別の plugin を消す。正規表現とは別の条件にしているのは、PS 版と同じ
#    正規表現の文字列を保つため（verify-kit が両版の正規表現を突き合わせる）。
# ⚠ Windows の予約デバイス名（CON / PRN / AUX / NUL / COM0〜COM9 / LPT0〜LPT9。大文字小文字を区別せず、
#    nul.txt のように拡張子が付いた形も）も拒否する。Windows では plugins\nul がフォルダではなくデバイスを指し、
#    ミラーとコピーが plugins/<名前> 以外に作用する。Linux / macOS で publish しても、Windows の clone では
#    checkout できないパスになる。判定は「最初の . より前」が予約名かどうか（foo.con は予約名ではない）。
if [[ "$NAME" == *$'\n'* ]] || [[ "$NAME" == *. ]] || ! printf '%s' "$NAME" | LC_ALL=C grep -Eqx '[A-Za-z0-9][A-Za-z0-9._-]{0,127}' \
   || printf '%s' "$NAME" | LC_ALL=C grep -Eiqx '(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\..*)?'; then
  echo "‼ plugin 名として不正: '$NAME'（英数字と . _ - のみ・先頭は英数字・末尾は . 以外・Windows の予約名（CON / NUL / COM1 等。拡張子付きも）以外・128 文字以内）" >&2; exit 2
fi

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

# marketplace の plugins/ に、大文字小文字だけが違う既存エントリ（--name Foo に対する plugins/foo）があれば中止する。
# Windows（と macOS の既定）のファイルシステムは大文字小文字を区別しないため plugins/Foo が既存の plugins/foo を指し、
# 後段のミラー（.git 以外を全削除）が別の plugin を消す（末尾の . を拒否したのと同じ故障クラス）。大文字小文字を
# 区別する OS で publish しても、Windows / macOS の clone では 2 つのフォルダが衝突する。
# 存在検査（[ -d plugins/Foo ]）では判定しない。それ自体が大文字小文字を無視して真になるため、エントリ名を
# 列挙して文字列で比べる。畳むのは ASCII だけ（名前は ASCII に限定済みで、PS 版と結果を揃えるため）。
# 完全一致のエントリ（通常の更新）は通す。破壊的な操作より前、取り出しや validate より前に判定する。
if [ -d "$MARKETPLACE/plugins" ]; then
  _lname="$(printf '%s' "$NAME" | LC_ALL=C tr 'A-Z' 'a-z')"
  for _e in "$MARKETPLACE/plugins"/*; do
    { [ -e "$_e" ] || [ -L "$_e" ]; } || continue
    _b="${_e##*/}"
    [ "$_b" = "$NAME" ] && continue
    if [ "$(printf '%s' "$_b" | LC_ALL=C tr 'A-Z' 'a-z')" = "$_lname" ]; then
      echo "‼ marketplace の plugins/ に大文字小文字だけが違う既存エントリがある: '$_b'（plugin 名 '$NAME'）。publish 中止" >&2
      echo "   Windows / macOS では同じフォルダを指し、ミラーが別の plugin を消します。既存の名前に揃えるか、別の名前にしてください。" >&2
      exit 2
    fi
  done
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

# 2-a. marketplace 側の名前（--name）と plugin.json の name が一致しなければ中止する（PS 版と同じ文言・終了コード）。
#      警告だけでは止まらない: --name を誤ると、後段のミラー（plugins/<名前> の .git 以外を全削除してコピー）が
#      別の plugin の中身を置き換えたまま公開 push まで進む（例: statusline の資材を --name pre-compact で publish）。
#      name を読めない（UTF-8 / JSON として不正・最上位がオブジェクトでない・name が無いか文字列でない）場合も、
#      照合できないので中止する。python が無い場合も同じ（照合しないまま先へ進めない）。
#      照合は python の中で文字列の完全一致として行い、結果を終了コードで返す（0=一致 / 3=不一致 / 4=読めない）。
#      標準出力の name は表示にだけ使う。
# ⚠ name はバイト列（UTF-8）で書き出す。テキストで書くと Windows ではパイプのコードページ（cp932 等）で符号化され、
#    表せない文字で例外になる。CRLF への変換も起きない。
# ⚠ encoding は utf-8-sig（先頭の BOM 1 個を読み飛ばす。PS 版も同じ）。utf-8 だと BOM 付きの plugin.json を読めない。
[ -n "$PY" ] || {
  echo "‼ python が無いため $PLUGIN_DIR/.claude-plugin/plugin.json の name を照合できない。中止" >&2
  echo "   python 3（python3 / python の順に探す）を PATH に置いて再実行してください。" >&2
  exit 1; }
_mname="$("$PY" -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8-sig") as f:
        j = json.load(f)
except Exception:
    sys.exit(4)
v = j.get("name") if isinstance(j, dict) else None
if not isinstance(v, str):
    sys.exit(4)
sys.stdout.buffer.write(v.encode("utf-8", "replace"))
sys.exit(0 if v == sys.argv[2] else 3)
' "$SRC/.claude-plugin/plugin.json" "$NAME" 2>/dev/null)"
_rc=$?
case "$_rc" in
  0) ;;
  3) echo "‼ $PLUGIN_DIR/.claude-plugin/plugin.json の name（'$_mname'）と marketplace 側の名前（'$NAME'）が違う。中止" >&2
     echo "   このまま進むと、ミラーが marketplace の plugins/$NAME をこの plugin の中身で置き換えて公開します。" >&2
     echo "   どちらが正しいか確かめ、marketplace 側の名前（marketplace.json のエントリ名も）と plugin.json の name を揃えてください。" >&2
     exit 1;;
  4) echo "‼ $PLUGIN_DIR/.claude-plugin/plugin.json の name を読めない（UTF-8 / JSON として不正・最上位がオブジェクトでない・name が無いか文字列でない）。中止" >&2
     exit 1;;
  *) echo "‼ python（$PY）で $PLUGIN_DIR/.claude-plugin/plugin.json の name を照合できない（python の終了コード $_rc）。中止" >&2
     exit 1;;
esac

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
#    終了コード: 0=合格（--strict では警告もゼロ）/ 1=不合格 / 2=validator 自体の失敗（パス不可読等）。どちらも中止。
claude plugin validate --strict "$SRC"; _rc=$?
if [ "$_rc" -ne 0 ]; then
  [ "$_rc" -eq 2 ] && echo "‼ validate 自体が失敗した（パス不可読等。plugin の不合格ではない）。publish 中止" >&2 \
                   || echo "‼ plugin validate FAIL。publish 中止" >&2
  exit 1
fi

# 4. /security-review は対話コマンドのため手動確認
read -r -p "→ $NAME について /security-review を実行済みなら y で続行: " ok
[ "$ok" = "y" ] || { echo "中止"; exit 1; }

# 5. marketplace へミラー（<C-MKT>/plugins/<name>/ を総入れ替え。.git は保護）
#    ⚠ 各手順の失敗を必ず検査する（set -e は使っていない）。ここを素通しにすると、
#       rm や cp が部分的に失敗しても後段の commit/push へ進み、混合状態や削除だけの
#       コミットが「✓ publish 完了」の表示とともに公開される。
DEST="$MARKETPLACE/plugins/$NAME"
if [ -e "$DEST" ] && [ ! -d "$DEST" ]; then
  echo "‼ 配布先 $DEST がディレクトリではない（ファイルが占有している）。publish 中止" >&2; exit 1
fi
mkdir -p "$DEST" || { echo "‼ 配布先ディレクトリを作れない: $DEST。publish 中止" >&2; exit 1; }
find "$DEST" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} + \
  || { echo "‼ 配布先の旧資材を削除できない: $DEST。publish 中止" >&2; exit 1; }
cp -R "$SRC/." "$DEST/" || { echo "‼ 配布先へコピーできない: $DEST。publish 中止" >&2; exit 1; }

# 5-b. 出口検査: コピーしたファイル数が payload と一致するか（2-b と対称の fail-closed）
_copied="$(find "$DEST" -type f -not -path "$DEST/.git/*" | wc -l)"
if [ "$_copied" -ne "$_actual" ]; then
  echo "‼ ミラーの結果が payload と一致しない（payload ${_actual} / 配布先 ${_copied}）。publish 中止" >&2
  exit 1
fi

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
