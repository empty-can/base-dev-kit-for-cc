#!/usr/bin/env bash
# =============================================================================
# verify-kit.sh — bash 版と PowerShell 版のスクリプトを実際に走らせ、結果の一致を検査する
# =============================================================================
# ルート CLAUDE.md の「bash 版と PowerShell 版は両方直し、両版を実際に走らせて結果が一致することを
# 確認する」をスクリプトで担保する。verify-kit.ps1 と対称で、どちらから呼んでも同じ系統
# （bash / pwsh 7 / Windows PowerShell 5.1）を駆動し、同じ判定を出す。
#   構成: 各版は「自系統で実スクリプトを走らせ、正規化した結果をファイルへ書く probe」を持つ。
#         比較役（引数なしで起動した側）は全系統の probe を子プロセスで呼び、結果を突き合わせる。
#         入力と期待値は verify-kit.d/（UTF-8・LF・BOM なし）を両版で共有する。
#
# 使い方:  ./scripts/verify-kit.sh [-v]
#   -v              詳細（差分・probe のログ）を表示する
#   --probe <out>   （内部用）bash 系統の probe を実行し、結果を <out> へ書く
# 終了コード: FAIL が 1 件以上で 1、なければ 0（CI 利用可）。引数の誤り等は 2。
#
# 要件: bash 4.4 以上（mapfile -d）・git 2.32 以上・python 3（python3 / python）・pwsh 7（Windows PowerShell 5.1 は任意）。
#   - git 2.32 以上: 一時リポジトリに対して実物の git を使う検査は、GIT_CONFIG_GLOBAL（2.32 で追加）に空のファイルを渡して
#     利用者の global 設定を読ませない。起動時に版を確かめ、2.32 未満なら publish-plugin の plugin.json の name 照合
#     （実物の git で一時リポジトリから取り出す項目）を理由付きで SKIP にする（他の項目は続行する）。check-assets の
#     git 層の fixture も同じ変数で隔離しているが、こちらは書き込みが一時リポジトリの init / add / commit だけなので SKIP しない。
#   - python 3: check-assets.sh の settings.json 検査と publish-plugin.sh の name 照合が使う。
#   - pwsh 7: PowerShell 版の検査と bash 版との比較。5.1 は見つかれば同じ検査を走らせる（publish 系は #requires -Version 7）。
# 注記: Linux / macOS では /usr/bin/python3 があるため、publish-plugin の「python 無し」のケース（PATH を /usr/bin:/bin に
#   絞って python を外す）は python を外せず SKIP になる（Windows の Git Bash では外せる）。
#
# 安全上の約束（手作業の検証で、Git Bash の PATH に Windows 形式のパスを渡したため実物の claude が
# 2 回起動した。以下はコードで強制している）:
#   - 実物の claude を起動するのは --version だけ。同じ一時ツリー・同じ引数を先にスタブで流し、
#     claude に届く引数が "--version" 1 個だけであることを確かめてから実物を呼ぶ。
#   - それ以外はスタブ。スタブは POSIX 形式の一時ディレクトリに置き、PATH="<stub>:/usr/bin:/bin"
#     （実物が見つからない PATH）で実行し、起動前に command -v の解決先がスタブであることを確かめる。
#   - リポジトリの .claude/ には何も作らない。ランチャーと setup-environment は一時ツリーへ
#     コピーしてから実行する（どちらも自身の位置からルートを解決する）。
#   - publish-plugin は --name 検証が git / ファイル書き込みより前にあることを確かめたうえで、
#     名前検証で止まるケースと、その直後の副作用の無い前提条件（存在しない marketplace）で止まる
#     ケースだけを、git と claude をスタブにした PATH で実行する。大文字小文字違いの検査は一時ディレクトリの
#     偽 marketplace に対して同じスタブの PATH で実行する（中止されなくても、スタブの git は何も出力しない
#     ため取り出しで止まり、ミラーには到達しない。一時ファイルもケースのディレクトリの中に作らせる）。
#   - publish-plugin の plugin.json の name 照合（2-a）は、取り出しまで進ませるため実物の git を使う。対象は
#     一時ディレクトリに作ったリポジトリだけ: 開発リポは publish-plugin のコピーと plugin.json を 1 コミットした
#     一時リポジトリ（スクリプトは自身の位置から開発リポを決める）、marketplace は remote の無い一時リポジトリ。
#     claude だけのスタブディレクトリ・実物の git のディレクトリ・/usr/bin:/bin の PATH（python を要するケースでは
#     python のディレクトリを末尾に足す。先頭側に置くと WindowsApps の WSL 用 bash.exe が拾われる）で実行し、起動前に
#     claude の解決先がスタブ、git の解決先が実物、marketplace に remote が無いことを確かめる。stdin は空なので
#     照合を通っても確認プロンプトで止まる。git の設定は空の一時ファイルに隔離する（global / system を読まない）。
#   - publish-plugin / publish-share の引数の検証は、引数の解析と必須の検査で止まるケースだけを、git と claude をスタブにした
#     同じ PATH で実行する。marketplace / 共有本体の値は一時ディレクトリの中の存在しないパスにし（検査が欠けていても
#     「見つからない」で止まる）、既定値が実物の共有本体を指す --share の省略は使わない。
#   - check-assets の追跡基準（git 層）の fixture も実物の git を使うが、対象は一時ディレクトリに作ったリポジトリだけで、
#     書くのはその中の init / add / commit だけ（check-assets 自身は読むだけ）。git の設定は同じく隔離する。
#   - 実スクリプトを呼ぶ。実スクリプトで検査できない項目は再実装で代用せず SKIP にする。
# =============================================================================
set -uo pipefail

VK_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VK_SELF="$VK_SCRIPTS/$(basename "${BASH_SOURCE[0]}")"
VK_ROOT="$(cd "$VK_SCRIPTS/.." && pwd)"
VK_FIX="$VK_SCRIPTS/verify-kit.d"
VK_PS1="$VK_SCRIPTS/verify-kit.ps1"

VERBOSE=0
PROBE_OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift;;
    --probe) PROBE_OUT="${2:?--probe に出力先が必要}"; shift 2;;
    -h|--help) sed -n '3,/^set -uo/p' "$VK_SELF" | sed '$d'; exit 0;;
    *) echo "‼ 不明な引数: $1（使い方: $0 [-v]）" >&2; exit 2;;
  esac
done

# mapfile -d（NUL 区切り）を使うため 4.4 以上。
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  echo "‼ bash 4.4 以上が必要です（現在: ${BASH_VERSION}）" >&2; exit 2
fi
[ -d "$VK_FIX" ] || { echo "‼ fixture ディレクトリが無い: $VK_FIX" >&2; exit 2; }

VK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/verify-kit.XXXXXX")" || { echo "‼ 一時ディレクトリを作れない" >&2; exit 2; }
# POSIX 形式に揃える（TMPDIR が Windows 形式でも、スタブを置く PATH 要素が必ず /… になるように）。
VK_TMP="$(cd "$VK_TMP" && pwd)"
trap 'rm -rf "$VK_TMP"' EXIT
trap 'exit 130' INT TERM

vk_native(){ if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }
vk_sq(){ local s="${1//\'/\'\\\'\'}"; printf "'%s'" "$s"; }

# =============================================================================
# probe（自系統で実スクリプトを走らせ、正規化した結果を fd 3 へ書く）
#   行は「タグ<TAB>値」、節は「@@ 名前」。最後に「@@ end」を書く（無ければ比較役は異常終了とみなす）。
#   出力の形式・順序は verify-kit.ps1 の probe と揃えること。
# =============================================================================
sec(){ printf '@@ %s\n' "$1" >&3; }
put(){ printf '%s\t%s\n' "$1" "$2" >&3; }

# 行ごとに from→to の置換（リテラル）を施し、最後に \ を / へ揃える（PowerShell 版の出力と比較するため）。
vk_norm(){
  local l i
  local -a a=("$@")
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    for ((i = 0; i + 1 < ${#a[@]}; i += 2)); do
      [ -n "${a[i]}" ] && l="${l//"${a[i]}"/${a[i+1]}}"
    done
    printf '%s\n' "${l//\\//}"
  done
}

# スタブ（実物の代わりに、受け取った引数を 1 行 1 引数で <名前>.args へ、環境を <名前>.env へ書く）
vk_mkstub(){
  local f="$STUB/$1"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "# verify-kit のスタブ（実物の $1 の代わり。引数と環境を記録して終わるだけ）"
    printf '%s\n' 'd="${VERIFY_KIT_STUB_DIR:-}"'
    printf '%s\n' '[ -n "$d" ] || exit 97'
    printf '%s\n' ": > \"\$d/$1.args\""
    printf '%s\n' "for a in \"\$@\"; do printf '%s\\n' \"\$a\" >> \"\$d/$1.args\"; done"
    printf '%s\n' '{'
    printf '%s\n' '  for v in CLAUDE_CONFIG_DIR CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD CLAUDE_CODE_PLUGIN_DIRS \'
    printf '%s\n' '           CLAUDE_CODE_PLUGIN_SEED_DIR CLAUDE_CODE_PLUGIN_CACHE_DIR; do'
    printf '%s\n' "    if [ -n \"\${!v+x}\" ]; then printf 'ENV\\t%s=%s\\n' \"\$v\" \"\${!v}\"; else printf 'ENV\\t%s=<unset>\\n' \"\$v\"; fi"
    printf '%s\n' '  done'
    printf '%s\n' "  printf 'CWD\\t%s\\n' \"\$PWD\""
    printf '%s\n' "} > \"\$d/$1.env\""
    printf '%s\n' "printf '%s\\n' '$1' >> \"\$d/calls\""
    printf '%s\n' 'exit 0'
  } > "$f"
  chmod +x "$f"
}

# 実物が見つからない PATH でスタブへの解決を確かめてから実行する。
#   使い方: vk_stubbed <スタブ出力先> <確かめるコマンド名…> -- <実行するコマンド…>
#   解決先がスタブでなければ実行せず「ASSERT ng」を出す。実行したら「ASSERT ok」「RC <終了コード>」。
vk_stubbed(){
  local sd="$1"; shift
  local -a names=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do names+=("$1"); shift; done
  shift
  mkdir -p "$sd"
  (
    export PATH="$STUB:/usr/bin:/bin" VERIFY_KIT_STUB_DIR="$sd"
    for n in "${names[@]}"; do
      r="$(command -v "$n" 2>/dev/null || true)"
      if [ "$r" != "$STUB/$n" ]; then
        put ASSERT "ng $n の解決先がスタブでない（${r:-見つからない}）。実行しない"; exit 0
      fi
    done
    put ASSERT ok
    "$@" > "$sd/stdout" 2> "$sd/stderr" < /dev/null
    put RC "$?"
  )
}

# $1=stdout を受けたファイル。‼ で始まる行があれば 0。publish 系の中止の文言は両版とも stderr に出す約束なので、
# stdout にあれば誤り（呼び出し側は分類を stdout-msg にする）
vk_stdout_msg(){ [ -f "$1" ] && [ "$(grep -c '^‼' "$1")" -gt 0 ]; }

vk_put_args(){ # $1=スタブ出力先 … RAN（スタブが動いた証拠＝引数ファイルの有無）と ARG を出す
  local a
  if [ -f "$1/claude.args" ]; then
    put RAN yes
    while IFS= read -r a || [ -n "$a" ]; do put ARG "$a"; done < "$1/claude.args"
  else
    put RAN no
  fi
}

# ---- 構文 ---------------------------------------------------------------------
probe_syntax(){
  sec syntax
  if [ "${#FILES[@]}" -eq 0 ]; then put SKIP "git でファイル一覧を取得できない"; return; fi
  local f msg
  for f in "${FILES[@]}"; do
    case "$f" in *.sh|*.sh.template) ;; *) continue;; esac
    [ -f "$VK_ROOT/$f" ] || continue
    if msg="$("$BASH" -n "$VK_ROOT/$f" 2>&1)"; then put OK "$f"; else put NG "$f: $(printf '%s\n' "$msg" | head -n 1)"; fi
  done
}

# ---- 保存形式（バイト単位。CR は tr で数える。Git Bash の grep / awk は CR を剥がすので使わない）---
probe_format(){
  sec format
  if [ "${#FILES[@]}" -eq 0 ]; then put SKIP "git でファイル一覧を取得できない"; return; fi
  local f p bom cr lf
  for f in "${FILES[@]}"; do
    p="$VK_ROOT/$f"; [ -f "$p" ] || continue
    bom="$(head -c 3 "$p" | od -An -tx1 | tr -d ' \n')"
    cr="$(tr -cd '\r' < "$p" | wc -c)"
    lf="$(tr -cd '\n' < "$p" | wc -c)"
    printf 'F\t%s\t%s\t%s\t%s\n' "$f" "$bom" "$((cr))" "$((lf))" >&3
  done
}

# ---- option-settings テンプレ（全項目を有効化したコピーと原本をロード）--------------------
probe_optset(){
  sec optset
  local tpl="$VK_ROOT/.claude/launcher/option-settings.sh.template" d="$VK_TMP/optset" n k
  mkdir -p "$d"
  if [ ! -f "$tpl" ]; then put LOAD "ng テンプレートが無い"; return; fi
  put LINES "$(grep -cE '^[[:space:]]*# \[--' "$tpl")"
  sed -E 's/^([[:space:]]*)# (\[--)/\1\2/' "$tpl" > "$d/all.sh"
  # ランチャーと同じ set -euo pipefail の下でロードする
  if ( set -euo pipefail; . "$d/all.sh"; printf '%s\n' "${!OPTS[@]}" ) > "$d/keys" 2> "$d/err"; then
    put LOAD ok
    while IFS= read -r k; do put KEY "$k"; done < <(LC_ALL=C sort "$d/keys")
  else
    put LOAD "ng $(head -n 1 "$d/err")"
  fi
  if n="$( set -euo pipefail; . "$tpl"; printf '%s' "${#OPTS[@]}" )" 2> "$d/err0"; then
    put ORIG "ok $n"
  else
    put ORIG "ng $(head -n 1 "$d/err0")"
  fi
}

# ---- setup-environment（一時ツリーの .claude/launcher/ で実行）------------------------
vk_envdiff(){ # $1=実行前 $2=実行後（env -0）→ 新規・変更は「名前=値」、削除は「-名前」
  local kv k
  declare -A B=() A=()
  while IFS= read -r -d '' kv; do k="${kv%%=*}"; [ -n "$k" ] && B["$k"]="${kv#*=}"; done < "$1"
  while IFS= read -r -d '' kv; do
    k="${kv%%=*}"
    { [ -n "$k" ] && [ "$k" != "_" ]; } || continue
    A["$k"]=1
    if [ -z "${B[$k]+x}" ] || [ "${B[$k]}" != "${kv#*=}" ]; then printf '%s\n' "$kv"; fi
  done < "$2"
  for k in "${!B[@]}"; do
    { [ "$k" = "_" ] || [ -n "${A[$k]+x}" ]; } || printf -- '-%s\n' "$k"
  done
}

vk_setupenv_run(){ # $1=一時ツリー。呼び出し元に同名の変数があると変化を観測できないので、対象の名前を先に外す
  local d="$1" v
  for v in $(compgen -e); do
    case "${v^^}" in VERIFY_KIT*|CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD) unset "$v";; esac
  done
  env -0 > "$d/before"
  . "$d/.claude/launcher/setup-environment.sh" 2> "$d/warn"
  env -0 > "$d/after"
}

probe_setupenv(){
  local c d l
  for c in plain bomcrlf; do
    sec "setupenv $c"
    d="$VK_TMP/setupenv-$c"; mkdir -p "$d/.claude/launcher"
    cp "$VK_ROOT/.claude/launcher/setup-environment.sh" "$d/.claude/launcher/"
    if [ "$c" = plain ]; then
      cp "$VK_FIX/custom.env.fixture" "$d/.claude/custom.env"
    else
      { printf '\357\273\277'; awk '{ printf "%s\r\n", $0 }' "$VK_FIX/custom.env.fixture"; } > "$d/.claude/custom.env"
    fi
    if ! ( vk_setupenv_run "$d" ); then
      put ERR "setup-environment.sh の実行に失敗した"
      continue
    fi
    while IFS= read -r l; do
      case "$l" in -*) put UNSET "${l#-}";; *) put SET "$l";; esac
    done < <(vk_envdiff "$d/before" "$d/after" | LC_ALL=C sort)
    while IFS= read -r l || [ -n "$l" ]; do put WARN "${l#⚠ }"; done < "$d/warn"
  done
}

# ---- ランチャー（スタブ）と実物 --version ------------------------------------------
LAUNCHER_GUARD=""
vk_mktree(){ # $1=ツリー $2=opts|none（opts なら launcher-opts.tsv から .claude/option-settings.sh を作る）
  local t="$1" k v
  mkdir -p "$t/.claude/launcher"
  cp "$VK_ROOT/start_claude_code.sh" "$t/"
  cp "$VK_ROOT/.claude/launcher/setup-environment.sh" "$t/.claude/launcher/"
  [ "$2" = opts ] || return 0
  {
    printf 'declare -A OPTS=(\n'
    while IFS=$'\t' read -r k v || [ -n "$k" ]; do
      case "$k" in ''|'#'*) continue;; esac
      printf '  [%s]=%s\n' "$k" "$(vk_sq "$v")"
    done < "$VK_FIX/launcher-opts.tsv"
    printf ')\n'
  } > "$t/.claude/option-settings.sh"
}

vk_case_names(){ awk -F'\t' '$1 == "case" { print $2 }' "$VK_FIX/launcher-cases.txt"; }
vk_case_opts(){ awk -F'\t' -v c="$1" '$1 == "case" && $2 == c { print $3 }' "$VK_FIX/launcher-cases.txt"; }
vk_case_tag(){ # $1=ケース $2=in|out
  awk -v c="$1" -v t="$2" 'BEGIN { FS = "\t" } $1 == "case" { cur = $2; next } cur == c && $1 == t { sub(/^[^\t]*\t/, ""); print }' \
    "$VK_FIX/launcher-cases.txt"
}

probe_launcher(){
  local L="$VK_TMP/launcher" c o
  local -a cin
  mkdir -p "$L"
  # 一時ツリーへのコピーで隔離できるのは、ランチャーが自身の位置からルートを解決しているときだけ
  grep -qF '_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' "$VK_ROOT/start_claude_code.sh" \
    || LAUNCHER_GUARD="ng start_claude_code.sh がルートを自身の位置から解決していない（一時ツリーで隔離できないため実行しない）"
  vk_mktree "$L/tree-opts" opts
  vk_mktree "$L/tree-none" none
  while IFS= read -r c; do
    sec "launcher $c"
    if [ -n "$LAUNCHER_GUARD" ]; then put ASSERT "$LAUNCHER_GUARD"; continue; fi
    o="$(vk_case_opts "$c")"
    mapfile -t cin < <(vk_case_tag "$c" in)
    vk_stubbed "$L/run-$c" claude -- "$BASH" "$L/tree-$o/start_claude_code.sh" ${cin[@]+"${cin[@]}"}
    vk_put_args "$L/run-$c"
  done < <(vk_case_names)
}

probe_version(){
  local L="$VK_TMP/launcher" sd="$VK_TMP/launcher/run-version" real out rc
  sec version-stub
  if [ -n "$LAUNCHER_GUARD" ]; then
    put ASSERT "$LAUNCHER_GUARD"
  else
    vk_stubbed "$sd" claude -- "$BASH" "$L/tree-none/start_claude_code.sh" --version
    vk_put_args "$sd"
  fi
  sec version
  if [ -n "$LAUNCHER_GUARD" ] || [ ! -f "$sd/claude.args" ] || [ "$(wc -l < "$sd/claude.args")" -ne 1 ] \
     || [ "$(head -n 1 "$sd/claude.args")" != "--version" ]; then
    put PRECHECK "ng スタブで確かめた claude への引数が --version 1 個ではない（実物は起動しない）"; return
  fi
  put PRECHECK ok
  real="$(command -v claude 2>/dev/null || true)"
  if [ -z "$real" ]; then put SKIP "claude が PATH に無い"; return; fi
  case "$real" in "$STUB"/*) put PRECHECK "ng 実物の解決先がスタブになっている"; return;; esac
  if command -v timeout >/dev/null 2>&1; then
    out="$(cd "$VK_TMP" && timeout 120 "$BASH" "$L/tree-none/start_claude_code.sh" --version 2> "$L/version.err" < /dev/null)"; rc=$?
  else
    out="$(cd "$VK_TMP" && "$BASH" "$L/tree-none/start_claude_code.sh" --version 2> "$L/version.err" < /dev/null)"; rc=$?
  fi
  put RC "$rc"
  put OUT "$(printf '%s\n' "$out" | tr -d '\r' | sed -n '1p')"
}

# ---- check-assets -------------------------------------------------------------
# fixture のケース（check-assets.expect の 1 列目。probe と比較役が同じ順で使う。verify-kit.ps1 の $CaCases と同じ）
CA_CASES=(ume clean broken bom worktree pcase pexact gcase gexact hidden dupkey pmulti wtcase)
# リンク（Windows はジャンクション、それ以外は symlink）を作るケース。作れない系統はそのケースを SKIP し、比較役の
# drop_skipping は項目単位で系統を除くので、ほかのケースを巻き添えにしないよう別の項目（item_ca_links）で判定する。
CA_LINK_CASES=(junction)
# $1=作るリンク $2=実体のディレクトリ。Windows は mklink /J（管理者権限不要。MSYS の ln -s はディレクトリを複製するので
# 使えない）、それ以外は ln -s。リンクとして見える（[ -L ]。Git Bash はジャンクションを symlink として扱う）ときだけ 0
vk_mklink(){
  if command -v cygpath >/dev/null 2>&1; then
    command -v cmd.exe >/dev/null 2>&1 || return 1
    MSYS2_ARG_CONV_EXCL='*' cmd.exe /d /c mklink /J "$(cygpath -w "$1")" "$(cygpath -w "$2")" > /dev/null 2>&1 || return 1
  else
    ln -s "$2" "$1" 2> /dev/null || return 1
  fi
  [ -L "$1" ]
}
probe_checkassets(){
  local c s rc l cfg
  sec "checkassets root"
  if ! command -v git >/dev/null 2>&1; then
    put SKIP "git が無い（リポジトリルートを追跡基準で検査できない）"
  else
    "$BASH" "$VK_ROOT/scripts/check-assets.sh" "$VK_ROOT" > "$VK_TMP/ca-root.out" 2> "$VK_TMP/ca-root.err"; rc=$?
    put RC "$rc"
    while IFS= read -r l; do put O "$l"; done < <(vk_norm "$VK_ROOT" "<ROOT>" < "$VK_TMP/ca-root.out")
  fi
  # ケースごとの payload は check-assets.expect の冒頭に記した内容で作る（verify-kit.ps1 と同じ）。
  # g で始まるケースは一時の git リポジトリ（ルート＝追跡基準）で、それ以外は --payload（実体基準）で検査する。
  for c in "${CA_CASES[@]}" "${CA_LINK_CASES[@]}"; do
    sec "checkassets $c"
    if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
      put SKIP "python が無い（check-assets.sh の settings.json 検査が動かない）"; continue
    fi
    case "$c" in g*) command -v git >/dev/null 2>&1 || { put SKIP "git が無い（一時リポジトリを作れない）"; continue; };; esac
    s="$VK_TMP/ca-$c"; mkdir -p "$s/.claude"
    cp "$VK_ROOT/.claude/.gitignore" "$VK_ROOT/.claude/.gitattributes" "$s/.claude/"
    printf '# verify-kit fixture\n' > "$s/.claude/CLAUDE.md"
    case "$c" in
      bom) { printf '\357\273\277'; cat "$VK_FIX/settings-clean.json"; } > "$s/.claude/settings.json";;
      worktree)
        cp "$VK_FIX/settings-clean.json" "$s/.claude/settings.json"
        mkdir -p "$s/.claude/worktrees/wt/.claude/evals/results";;
      wtcase)
        cp "$VK_FIX/settings-clean.json" "$s/.claude/settings.json"
        mkdir -p "$s/.claude/Worktrees/evals/results";;
      pcase) cp "$VK_FIX/settings-envcase.json" "$s/.claude/settings.json";;
      pexact|gcase|gexact|junction|hidden|pmulti) cp "$VK_FIX/settings-clean.json" "$s/.claude/settings.json";;
      *) cp "$VK_FIX/settings-$c.json" "$s/.claude/settings.json";;
    esac
    case "$c" in
      junction)
        # .claude/x は外のディレクトリ（evals/results と絶対パスを書いたファイルを持つ）へのリンク、.claude/y/evals/results は
        # リンクそのもの（空のディレクトリへ）。実体はケースのディレクトリの中（.claude の外）に置く
        mkdir -p "$s/outside-x/evals/results" "$s/outside-y" "$s/.claude/y/evals"
        printf '%s\n' 'C:\Users\verify-kit\linked' > "$s/outside-x/evals/results/r.md"
        if ! vk_mklink "$s/.claude/x" "$s/outside-x" || ! vk_mklink "$s/.claude/y/evals/results" "$s/outside-y"; then
          put SKIP "ジャンクション / シンボリックリンクを作れない"; continue
        fi;;
      ume)
        cp "$VK_FIX/abspath-mixed.md" "$s/.claude/"
        printf '%s\n' 'C:\Users\verify-kit\work' > "$s/.claude/win-file-encoding-abspath.md"
        yes 'C:\Users\verify-kit\big' | head -n 20000 > "$s/.claude/big-abspath.md"
        # 25 バイトの行 + x を 7975 バイト（計 8000）の直後に NUL。NUL が先頭 8000 バイトの外なのでテキスト扱い
        { printf '%s\n' 'C:\Users\verify-kit\late'; printf '%7975s' '' | tr ' ' x; printf '\000tail\n'; } > "$s/.claude/late-nul-abspath.md";;
      hidden)
        # 隠し属性のファイルと、隠し属性のディレクトリの中のファイル（どちらも絶対パスを書く）。名前も . で始める
        # （Windows 以外の .NET は . 始まりを隠しとみなす）。find は属性を見ないが、fixture は PS 版と同じにする
        mkdir -p "$s/.claude/.hidden-dir"
        printf '%s\n' 'C:\Users\verify-kit\hidden' > "$s/.claude/.hidden-abspath.md"
        printf '%s\n' 'C:\Users\verify-kit\hidden' > "$s/.claude/.hidden-dir/abspath.md"
        if command -v cygpath >/dev/null 2>&1 && command -v attrib.exe >/dev/null 2>&1; then
          attrib.exe +h "$(cygpath -w "$s/.claude/.hidden-abspath.md")" > /dev/null 2>&1
          attrib.exe +h "$(cygpath -w "$s/.claude/.hidden-dir")" > /dev/null 2>&1
        fi;;
      clean)
        cp "$VK_FIX/abspath-allowed.md" "$s/.claude/"
        { printf 'verify-kit\000'; printf '%s\n' 'C:\Users\verify-kit\binary'; } > "$s/.claude/binary-abspath.bin";;
      pcase|gcase)
        mkdir -p "$s/.claude/Reports" "$s/.claude/plugin-x/Evals/Results"
        printf 'verify-kit\n' > "$s/.claude/Reports/x.md"; printf '{}\n' > "$s/.claude/plugin-x/Evals/Results/r.json";;
      pexact|gexact)
        mkdir -p "$s/.claude/reports" "$s/.claude/plugin-x/evals/results"
        printf 'verify-kit\n' > "$s/.claude/reports/x.md"; printf '{}\n' > "$s/.claude/plugin-x/evals/results/r.json"
        if [ "$c" = gexact ]; then
          mkdir -p "$s/.claude/plugin-x0/evals/results"; printf '{}\n' > "$s/.claude/plugin-x0/evals/results/r.json"
        fi;;
      pmulti)
        # 並びの検査。/ 区切りの序数順と \ 区切り・カルチャ順・列挙の順で前後が入れ替わる名前を混ぜる（列挙は先頭 5 件）
        for d in p p-x p0 pZ p_ pa; do mkdir -p "$s/.claude/$d/evals/results"; done
        mkdir -p "$s/.claude/a"
        printf '%s\n' 'C:\Users\verify-kit\multi' > "$s/.claude/a/y.md"
        printf '%s\n' 'C:\Users\verify-kit\multi' > "$s/.claude/a0.md";;
    esac
    case "$c" in
      g*)
        # 利用者の global / system 設定を読まない（一時リポジトリの作成も check-assets の git 呼び出しも）
        : > "$s.gitconfig"; cfg="$(vk_native "$s.gitconfig")"
        if [ "$c" = gcase ]; then
          mkdir -p "$s/.claude/Work"; printf 'verify-kit\n' > "$s/.claude/Work/w.md"
          # 日本語名の追跡ファイル（絶対パスを含む）。git 層の 2-e の一覧が 3 系統で一致すること（PS 版は ls-files -z を UTF-8 で読む）
          printf '%s\n' 'C:\Users\verify-kit\jp' > "$s/.claude/日本語-abspath.md"
          set -- .claude/Reports/x.md .claude/plugin-x/Evals/Results/r.json .claude/日本語-abspath.md
        else
          set -- .claude/reports/x.md .claude/plugin-x/evals/results/r.json .claude/plugin-x0/evals/results/r.json
        fi
        if ! { vk_tgit "$cfg" init -q "$s" \
               && vk_tgit "$cfg" -C "$s" add -- .claude/.gitignore .claude/.gitattributes .claude/CLAUDE.md .claude/settings.json \
               && vk_tgit "$cfg" -C "$s" add -f -- "$@" && vk_tgit "$cfg" -C "$s" commit -q -m verify-kit; } > "$s.setup" 2>&1; then
          put RC setup-ng; continue
        fi
        GIT_CONFIG_GLOBAL="$cfg" GIT_CONFIG_NOSYSTEM=1 "$BASH" "$VK_ROOT/scripts/check-assets.sh" "$s" > "$s.out" 2> "$s.err"; rc=$?;;
      *) "$BASH" "$VK_ROOT/scripts/check-assets.sh" --payload "$s" > "$s.out" 2> "$s.err"; rc=$?;;
    esac
    put RC "$rc"
    while IFS= read -r l; do put O "$l"; done < <(vk_norm "$s" "<SHARE>" < "$s.out")
  done
}

# ---- clean-test-env（スタブ・KEEP=1。一時ディレクトリは TMPDIR で自分の一時領域の中へ作らせる）------
vk_cte_run(){ # $1=作業領域。PRE を置いた呼び出し元として clean-test-env.sh を呼び、実行後の環境を AFTER に残す
  local d="$1" tag kv k v rc
  while IFS=$'\t' read -r tag kv || [ -n "$tag" ]; do
    [ "$tag" = PRE ] || continue
    k="${kv%%=*}"; v="${kv#*=}"
    if [ "$v" = "<unset>" ]; then unset "$k"; else export "$k=$v"; fi
  done < "$VK_FIX/clean-test-env.txt"
  unset PERMISSION_MODE
  TMPDIR="$d/tmp" KEEP=1 "$BASH" "$VK_ROOT/scripts/clean-test-env.sh" "$VK_ROOT" > "$d/cte.out" 2> "$d/cte.err"
  rc=$?
  while IFS=$'\t' read -r tag kv || [ -n "$tag" ]; do
    [ "$tag" = PRE ] || continue
    k="${kv%%=*}"
    if [ -n "${!k+x}" ]; then printf 'AFTER\t%s=%s\n' "$k" "${!k}"; else printf 'AFTER\t%s=<unset>\n' "$k"; fi
  done < "$VK_FIX/clean-test-env.txt" > "$d/after"
  return "$rc"
}

probe_cleanenv(){
  local d="$VK_TMP/cleanenv" sd="$VK_TMP/cleanenv/stub-out" cfg="" work="" l
  local -a nm
  sec cleanenv
  mkdir -p "$d/tmp" "$sd"
  vk_stubbed "$sd" claude -- vk_cte_run "$d"
  if [ -f "$sd/claude.env" ]; then
    cfg="$(sed -n 's/^ENV\tCLAUDE_CONFIG_DIR=//p' "$sd/claude.env")"
    work="$(sed -n 's/^CWD\t//p' "$sd/claude.env")"
  fi
  # 一時 config dir → <CFG>、作業ディレクトリ → <WORK>、<Share> → <R>
  nm=("$cfg" "<CFG>" "$work" "<WORK>" "$VK_ROOT" "<R>")
  if [ -f "$sd/claude.args" ]; then
    put RAN yes
    while IFS= read -r l; do put ARG "$l"; done < <(vk_norm "${nm[@]}" < "$sd/claude.args")
  else
    put RAN no
  fi
  [ -f "$sd/claude.env" ] && vk_norm "${nm[@]}" < "$sd/claude.env" >&3
  if [ -n "$cfg" ] && [ -f "$cfg/settings.json" ]; then
    put SETTINGS "$(tr -d '\r\n' < "$cfg/settings.json")"
  else
    put SETTINGS "<なし>"
  fi
  [ -f "$d/after" ] && cat "$d/after" >&3
  if [ -f "$d/cte.out" ]; then
    while IFS= read -r l; do put O "$l"; done < <(vk_norm "${nm[@]}" < "$d/cte.out")
  fi
}

# ---- clean-test-env の不正な権限モード（スタブ。起動前に止まり claude が呼ばれないこと）-------------
probe_cleanenv_badmode(){
  local d="$VK_TMP/cleanenv-bad" tag m i=0 l
  while IFS=$'\t' read -r tag m || [ -n "$tag" ]; do
    [ "$tag" = BADMODE ] || continue
    i=$((i + 1))
    sec "cleanenv-badmode $i"
    put MODE "$m"
    mkdir -p "$d/case$i/tmp"
    [ "$m" = '<empty>' ] && m=""   # 空文字列（設定済みで空）
    vk_stubbed "$d/case$i" claude -- env PERMISSION_MODE="$m" TMPDIR="$d/case$i/tmp" KEEP=1 \
      "$BASH" "$VK_ROOT/scripts/clean-test-env.sh" "$VK_ROOT"
    vk_put_args "$d/case$i"
    # stdout は O、stderr は E として別タグで残す（エラー文が stderr のみにあることを判定するため）
    while IFS= read -r l; do put O "$l"; done < <(cat "$d/case$i/stdout" 2>/dev/null | vk_norm "$VK_ROOT" "<R>")
    while IFS= read -r l; do put E "$l"; done < <(cat "$d/case$i/stderr" 2>/dev/null | vk_norm "$VK_ROOT" "<R>")
  done < "$VK_FIX/clean-test-env.txt"
}

# ---- clean-test-env の存在しない <Share>（スタブ・KEEP=1。一時ディレクトリを作る前に止まり claude が呼ばれないこと）----
probe_cleanenv_badshare(){
  local d="$VK_TMP/cleanenv-badshare" l
  sec cleanenv-badshare
  mkdir -p "$d/tmp"
  vk_stubbed "$d" claude -- env -u PERMISSION_MODE TMPDIR="$d/tmp" KEEP=1 \
    "$BASH" "$VK_ROOT/scripts/clean-test-env.sh" "$d/no-such-share"
  vk_put_args "$d"
  while IFS= read -r l; do [ -z "$l" ] || put O "$l"; done < <(cat "$d/stdout" 2>/dev/null | vk_norm "$d" "<D>")
  while IFS= read -r l; do [ -z "$l" ] || put E "$l"; done < <(cat "$d/stderr" 2>/dev/null | vk_norm "$d" "<D>")
  put LEFT "$(ls -A "$d/tmp" | wc -l | tr -d ' ')"
}

# ---- publish-plugin の --name 検証 ----------------------------------------------
probe_pubname(){
  local pp="$VK_ROOT/scripts/publish-plugin.sh" d="$VK_TMP/pubname" nl sl i eb ep name out rc cls calls re ang=""
  sec pubname
  mkdir -p "$d"
  # --name 検証（{0,127} を含む行）が、最初の副作用コマンド（git / ファイル操作 / claude 等）より前にあること
  nl="$(grep -n -F '{0,127}' "$pp" | grep -v -E '^[0-9]+:[[:space:]]*#' | head -n 1 | cut -d: -f1)"
  sl="$(grep -n -E '(^|[^A-Za-z0-9_.-])(git|mktemp|mkdir|cp|mv|rm|tar|claude|curl|wget|tee|touch)([^A-Za-z0-9_.-]|$)' "$pp" \
        | grep -v -E '^[0-9]+:[[:space:]]*#' | head -n 1 | cut -d: -f1)"
  if [ -n "$nl" ] && [ -n "$sl" ] && [ "$nl" -lt "$sl" ]; then
    put ORDER "ok 名前検証 ${nl} 行目 < 最初の副作用 ${sl} 行目"
    put MODE real
    i=0
    while IFS=$'\t' read -r eb ep name || [ -n "$eb" ]; do
      case "$eb" in ''|'#'*) continue;; esac
      i=$((i + 1))
      vk_stubbed "$d/case$i" git claude -- "$BASH" "$pp" --marketplace "$d/no-such-marketplace" \
        --ref verify-kit-dummy-ref --name "$name" 3> "$d/assert$i"
      # 中止の文言は stderr だけを見る（stdout に ‼ の行があれば stdout-msg。両版とも stderr に出す約束）
      out="$(cat "$d/case$i/stderr" 2>/dev/null)"
      rc="$(sed -n 's/^RC\t//p' "$d/assert$i")"
      cls=other
      if grep -q "^ASSERT"$'\t'"ok" "$d/assert$i"; then
        case "$out" in
          *"plugin 名として不正"*) [ "$rc" = 2 ] && cls=reject;;
          *"marketplace リポジトリが見つからない"*) [ "$rc" = 2 ] && cls=accept;;
          *"--name に値が必要"*|*"-Name に値が必要"*) [ "$rc" = 1 ] && cls=argerr;;
        esac
        vk_stdout_msg "$d/case$i/stdout" && cls=stdout-msg
      else
        cls=assert-ng
        [ -n "$ang" ] || ang="$(sed -n 's/^ASSERT\t//p' "$d/assert$i")"
      fi
      calls=0
      [ -f "$d/case$i/calls" ] && calls="$(wc -l < "$d/case$i/calls")"
      put CASE "$i $cls rc=${rc:--} stubcalls=$((calls))"
    done < "$VK_FIX/plugin-names.tsv"
    put ASSERT "${ang:-ok}"
  else
    # 順序を確かめられないときは実スクリプトを実行しない。検証の正規表現を抽出して各ケースを当てる（フォールバック）
    put ORDER "ng 名前検証=${nl:-?} 行目 / 最初の副作用=${sl:-?} 行目"
    put MODE fallback
    re="$(grep -o -E "grep -Eqx '[^']+'" "$pp" | head -n 1 | sed -E "s/^grep -Eqx '//; s/'\$//")"
    put REGEX "$re"
    i=0
    while IFS=$'\t' read -r eb ep name || [ -n "$eb" ]; do
      case "$eb" in ''|'#'*) continue;; esac
      i=$((i + 1))
      if [ -n "$re" ] && printf '%s' "$name" | LC_ALL=C grep -Eqx -- "$re"; then cls=accept; else cls=reject; fi
      put CASE "$i $cls rc=- stubcalls=0"
    done < "$VK_FIX/plugin-names.tsv"
  fi
}

# ---- publish-plugin の大文字小文字違い（一時ディレクトリの偽 marketplace）------------------
# 偽 marketplace は .git を空のディレクトリ、plugins/<既存>/ に目印のファイルを置いて作る。結果は
# 「clash（取り出しより前に exit 2）/ pass（取り出し＝git archive まで進んだ）/ other」と、既存エントリが無傷か。
probe_pubcase(){
  local pp="$VK_ROOT/scripts/publish-plugin.sh" d="$VK_TMP/pubcase" i=0 exp ent name out rc cls arch intact ang=""
  sec pubcase
  mkdir -p "$d"
  while IFS=$'\t' read -r exp ent name || [ -n "$exp" ]; do
    case "$exp" in ''|'#'*) continue;; esac
    i=$((i + 1))
    mkdir -p "$d/mkt$i/.git" "$d/mkt$i/plugins/$ent" "$d/case$i/tmp"
    printf 'verify-kit\n' > "$d/mkt$i/plugins/$ent/sentinel.txt"
    vk_stubbed "$d/case$i" git claude -- env TMPDIR="$d/case$i/tmp" "$BASH" "$pp" --marketplace "$d/mkt$i" \
      --ref verify-kit-dummy-ref --name "$name" 3> "$d/assert$i"
    out="$(cat "$d/case$i/stderr" 2>/dev/null)"   # 中止の文言は stderr だけを見る（probe_pubname と同じ）
    rc="$(sed -n 's/^RC\t//p' "$d/assert$i")"
    # スタブの git.args は最後の呼び出しの引数。取り出しまで進んだら最後は archive になる
    arch=no
    [ -f "$d/case$i/git.args" ] && grep -qx archive "$d/case$i/git.args" && arch=yes
    intact=no
    [ -f "$d/mkt$i/plugins/$ent/sentinel.txt" ] && [ "$(ls -A "$d/mkt$i/plugins")" = "$ent" ] && intact=yes
    cls=other
    if grep -q "^ASSERT"$'\t'"ok" "$d/assert$i"; then
      case "$out" in
        *"大文字小文字だけが違う既存エントリ"*) [ "$rc" = 2 ] && [ "$arch" = no ] && cls=clash;;
        *) [ "$arch" = yes ] && cls=pass;;
      esac
      vk_stdout_msg "$d/case$i/stdout" && cls=stdout-msg
    else
      cls=assert-ng
      [ -n "$ang" ] || ang="$(sed -n 's/^ASSERT\t//p' "$d/assert$i")"
    fi
    put CASE "$i $cls rc=${rc:--} archive=$arch intact=$intact"
  done < "$VK_FIX/plugin-case.tsv"
  put ASSERT "${ang:-ok}"
}

# ---- publish-plugin の plugin.json の name 照合（一時の開発リポと marketplace・実物の git・claude はスタブ）-------
# 一時リポジトリ用の git（$1=空の設定ファイル。利用者の global / system 設定を読まない。作者は固定）
vk_tgit(){
  local cfg="$1"; shift
  GIT_CONFIG_GLOBAL="$cfg" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=verify-kit GIT_AUTHOR_EMAIL=verify-kit@invalid \
    GIT_COMMITTER_NAME=verify-kit GIT_COMMITTER_EMAIL=verify-kit@invalid git "$@"
}
# 結果は「pass（照合を通って validate＝claude スタブまで進んだ）/ mismatch / unreadable / nopython / skip / other」と、
# 一時 marketplace が無傷か（目印のファイルが残り、ほかに何も無く、commit も index への追加も無い）。
# 中止のときは文言（‼ の行と字下げの続き）を MSG に書き、比較役が bash / pwsh で突き合わせる。
probe_pubmanifest(){
  local pp="$VK_ROOT/scripts/publish-plugin.sh" d="$VK_TMP/pubman" cst="$VK_TMP/stub-claude" i=0 ang=""
  local realgit gitdir pydir cfg eb ep py bom name json dev mkt cs path a rc out val intact cls l
  sec pubmanifest
  realgit="$(command -v git 2>/dev/null || true)"
  if [ -z "$realgit" ]; then put SKIP "git が無い（一時リポジトリを作れない）"; return; fi
  # 起動時に確かめた git の版（probe_main）。GIT_CONFIG_GLOBAL が効かない版では実行しない
  if [ -n "$VK_GIT_WHY" ]; then put SKIP "$VK_GIT_WHY"; return; fi
  gitdir="${realgit%/*}"
  pydir="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  pydir="${pydir%/*}"
  mkdir -p "$d" "$cst"
  ( STUB="$cst"; vk_mkstub claude )
  cfg="$(vk_native "$d/gitconfig")"
  : > "$d/gitconfig"
  while IFS=$'\t' read -r eb ep py bom name json || [ -n "$eb" ]; do
    case "$eb" in ''|'#'*) continue;; esac
    i=$((i + 1))
    if [ "$eb" = - ]; then put CASE "$i -"; continue; fi
    dev="$d/dev$i"; mkt="$d/mkt$i"; cs="$d/case$i"
    mkdir -p "$dev/scripts" "$dev/plugin/.claude-plugin" "$mkt/plugins/$name" "$cs/tmp"
    cp "$pp" "$dev/scripts/publish-plugin.sh"
    { if [ "$bom" = yes ]; then printf '\357\273\277'; fi; printf '%s\n' "$json"; } > "$dev/plugin/.claude-plugin/plugin.json"
    printf 'verify-kit\n' > "$mkt/plugins/$name/sentinel.txt"
    if ! { vk_tgit "$cfg" init -q "$dev" && vk_tgit "$cfg" -C "$dev" add plugin \
           && vk_tgit "$cfg" -C "$dev" commit -q -m verify-kit && vk_tgit "$cfg" init -q "$mkt"; } > "$cs/setup.log" 2>&1; then
      put CASE "$i setup-ng"; continue
    fi
    # python のディレクトリは最後に置く（Windows の python3 は WindowsApps にあり、そこには WSL の bash.exe 等の
    # 別名もある。前に置くとスタブの #!/usr/bin/env bash が WSL を起動しようとする（実測））
    path="$cst:$gitdir:/usr/bin:/bin"
    if [ "$py" = yes ] && [ -n "$pydir" ]; then path+=":$pydir"; fi
    (
      export PATH="$path" VERIFY_KIT_STUB_DIR="$cs" TMPDIR="$cs/tmp" GIT_CONFIG_GLOBAL="$cfg" GIT_CONFIG_NOSYSTEM=1
      r="$(command -v claude 2>/dev/null || true)"
      if [ "$r" != "$cst/claude" ]; then printf 'ng claude の解決先がスタブでない（%s）。実行しない\n' "${r:-見つからない}" > "$cs/assert"; exit 0; fi
      r="$(command -v git 2>/dev/null || true)"
      if [ "$r" != "$realgit" ]; then printf 'ng git の解決先が実物でない（%s）。実行しない\n' "${r:-見つからない}" > "$cs/assert"; exit 0; fi
      r="$(command -v bash 2>/dev/null || true)"
      if [ -z "$r" ] || ! [ "$r" -ef "$BASH" ]; then printf 'ng bash の解決先が %s でない（%s）。実行しない\n' "$BASH" "${r:-見つからない}" > "$cs/assert"; exit 0; fi
      r="$(git -C "$mkt" remote 2>&1)" || r="git remote が失敗した: $r"
      if [ -n "$r" ]; then printf 'ng 一時 marketplace に remote がある（%s）。実行しない\n' "$r" > "$cs/assert"; exit 0; fi
      r="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
      if [ "$py" = yes ] && [ -z "$r" ]; then printf 'skip python が見つからない\n' > "$cs/assert"; exit 0; fi
      if [ "$py" = no ] && [ -n "$r" ]; then printf 'skip python を PATH から外せない（%s）\n' "$r" > "$cs/assert"; exit 0; fi
      printf 'ok\n' > "$cs/assert"
      "$BASH" "$dev/scripts/publish-plugin.sh" --marketplace "$mkt" --ref HEAD --name "$name" \
        > "$cs/stdout" 2> "$cs/stderr" < /dev/null
      printf '%s\n' "$?" > "$cs/rc"
    )
    a="$(cat "$cs/assert" 2>/dev/null)"
    case "$a" in
      ok) ;;
      skip\ *) put CASE "$i skip ${a#skip }"; continue;;
      *) [ -n "$ang" ] || ang="${a:-ng 事前確認の結果が無い}"; put CASE "$i assert-ng"; continue;;
    esac
    rc="$(cat "$cs/rc" 2>/dev/null)"
    out="$(cat "$cs/stderr" 2>/dev/null)"   # 中止の文言は stderr だけを見る（probe_pubname と同じ）
    val=no
    if [ -f "$cs/claude.args" ] && grep -qx validate "$cs/claude.args"; then val=yes; fi
    intact=no
    if [ -f "$mkt/plugins/$name/sentinel.txt" ] && [ "$(ls -A "$mkt/plugins")" = "$name" ] \
       && [ "$(ls -A "$mkt" | LC_ALL=C sort | tr '\n' ' ')" = ".git plugins " ] \
       && ! vk_tgit "$cfg" -C "$mkt" rev-parse -q --verify HEAD > /dev/null 2>&1 \
       && [ -z "$(vk_tgit "$cfg" -C "$mkt" ls-files 2>&1)" ]; then
      intact=yes
    fi
    cls=other
    case "$out" in
      *"の name（"*"が違う。中止"*) [ "$rc" = 1 ] && [ "$val" = no ] && cls=mismatch;;
      *"の name を読めない"*) [ "$rc" = 1 ] && [ "$val" = no ] && cls=unreadable;;
      *"python が無いため"*) [ "$rc" = 1 ] && [ "$val" = no ] && cls=nopython;;
      *) [ "$val" = yes ] && cls=pass;;
    esac
    vk_stdout_msg "$cs/stdout" && cls=stdout-msg
    put CASE "$i $cls rc=${rc:--} validate=$val intact=$intact"
    if [ "$cls" != pass ]; then
      while IFS= read -r l; do
        case "$l" in '‼'*|'   '*) put MSG "$i $l";; esac
      done <<< "$out"
    fi
  done < "$VK_FIX/plugin-manifest.tsv"
  put ASSERT "${ang:-ok}"
}

# ---- publish-plugin / publish-share の引数の検証（スタブ。引数の解析と必須の検査で止まること）---------------
# 結果は「ref / mkt / value（期待どおりの中止）/ stdout-msg / other」。stderr の行は、スクリプトのパスを <SCRIPT>、一時
# ディレクトリを <D>、オプションの綴りを PS 版の -Ref 等へ揃えて E に書く（比較役が bash / pwsh で突き合わせる）。
# 値の <nomkt> / <noshare> は一時ディレクトリの中の存在しないパスなので、検査が欠けていても「見つからない」で止まる。
probe_pubargs(){
  local d="$VK_TMP/pubargs" i=0 line a script rc cls calls ang="" err first
  local -a f av
  sec pubargs
  mkdir -p "$d"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    i=$((i + 1))
    IFS=$'\t' read -r -a f <<< "$line"
    if [ "${#f[@]}" -lt 3 ] || [ "${f[1]}" = - ]; then put CASE "$i -"; continue; fi
    case "${f[0]}" in
      plugin) script="$VK_ROOT/scripts/publish-plugin.sh";;
      share) script="$VK_ROOT/scripts/publish-share.sh";;
      *) put CASE "$i badfixture"; continue;;
    esac
    av=()
    for a in "${f[@]:3}"; do
      case "$a" in
        '<empty>') av+=("");;
        '<nomkt>') av+=("$d/no-such-marketplace");;
        '<noshare>') av+=("$d/no-such-share");;
        *) av+=("$a");;
      esac
    done
    vk_stubbed "$d/case$i" git claude -- "$BASH" "$script" ${av[@]+"${av[@]}"} 3> "$d/assert$i"
    rc="$(sed -n 's/^RC\t//p' "$d/assert$i")"
    cls=other
    if grep -q "^ASSERT"$'\t'"ok" "$d/assert$i"; then
      first="$(grep -m1 '^‼' "$d/case$i/stderr" 2>/dev/null)"
      case "$first" in
        *"は必須です（既定値は廃止）"*) [ "$rc" = 2 ] && cls=ref;;
        *"<C-MKT のパス> が必要"*) [ "$rc" = 2 ] && cls=mkt;;
        *"に値が必要"*) [ "$rc" = 1 ] && cls=value;;
      esac
      vk_stdout_msg "$d/case$i/stdout" && cls=stdout-msg
    else
      cls=assert-ng
      [ -n "$ang" ] || ang="$(sed -n 's/^ASSERT\t//p' "$d/assert$i")"
    fi
    calls=0
    [ -f "$d/case$i/calls" ] && calls="$(wc -l < "$d/case$i/calls")"
    put CASE "$i $cls rc=${rc:--} stubcalls=$((calls))"
    if [ -f "$d/case$i/stderr" ]; then
      while IFS= read -r err; do [ -z "$err" ] || put E "$i $err"; done < <(vk_norm "$script" "<SCRIPT>" "$d" "<D>" \
        --marketplace -Marketplace --ref -Ref --plugin -Plugin --name -Name --share -ShareBody < "$d/case$i/stderr")
    fi
  done < "$VK_FIX/publish-args.tsv"
  put ASSERT "${ang:-ok}"
}

# GIT_CONFIG_GLOBAL（git 2.32 で追加）に対応した版か。$1=git --version の出力。対応していれば何も出さず、していなければ
# SKIP の理由を出す（verify-kit.ps1 の Get-GitCfgWhy と同じ判定・同じ文言）
vk_git_cfg_why(){
  if [[ "$1" =~ ^git\ version\ ([0-9]+)\.([0-9]+) ]]; then
    if [ "${BASH_REMATCH[1]}" -gt 2 ] || { [ "${BASH_REMATCH[1]}" -eq 2 ] && [ "${BASH_REMATCH[2]}" -ge 32 ]; }; then return 0; fi
    printf 'git %s.%s は 2.32 未満（GIT_CONFIG_GLOBAL が効かず、一時リポジトリの git から利用者の global 設定を隔離できない）' \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf 'git の版を判定できない（%s）' "$1"
  fi
}

probe_main(){
  exec 3> "$PROBE_OUT" || exit 2
  # 起動時に git の版を確かめる（満たさなければ plugin.json の name 照合だけを SKIP にする。理由は VK_GIT_WHY）
  VK_GIT_WHY=""
  if command -v git >/dev/null 2>&1; then VK_GIT_WHY="$(vk_git_cfg_why "$(git --version 2>/dev/null)")"; fi
  STUB="$VK_TMP/stub"; mkdir -p "$STUB"
  vk_mkstub claude
  vk_mkstub git
  FILES=()
  if command -v git >/dev/null 2>&1; then
    mapfile -d '' -t FILES < <(git -C "$VK_ROOT" -c core.quotepath=false ls-files -z --cached --others --exclude-standard 2>/dev/null \
                                 | LC_ALL=C sort -z -u)
  fi
  sec meta
  put SYSTEM bash
  put VERSION "$BASH_VERSION"
  put EDITION -
  probe_syntax
  probe_format
  probe_optset
  probe_setupenv
  probe_launcher
  probe_version
  probe_checkassets
  probe_cleanenv
  probe_cleanenv_badmode
  probe_cleanenv_badshare
  probe_pubname
  probe_pubcase
  probe_pubmanifest
  probe_pubargs
  sec end
  exec 3>&-
}

if [ -n "$PROBE_OUT" ]; then
  probe_main
  exit 0
fi

# =============================================================================
# 比較役（全系統の probe を呼んで突き合わせる）。判定の内容・文言は verify-kit.ps1 と揃えること。
# =============================================================================
NPASS=0; NFAIL=0; NSKIP=0
SYS_ALL=(bash pwsh ps51)
declare -A SYS_STATE=() SYS_WHY=() SYS_LABEL=([bash]="bash" [pwsh]="pwsh 7" [ps51]="5.1") SYS_VER=()
declare -A SYS_NAME=([bash]="bash" [pwsh]="pwsh" [ps51]="Windows PowerShell")

verdict(){ # $1=PASS|FAIL|SKIP $2=項目 $3=理由
  case "$1" in PASS) NPASS=$((NPASS + 1));; FAIL) NFAIL=$((NFAIL + 1));; SKIP) NSKIP=$((NSKIP + 1));; esac
  printf '  [%s] %s: %s\n' "$1" "$2" "$3"
}
detail_file(){ [ "$VERBOSE" -eq 1 ] || return 0; sed -n '1,40p' "$1" | sed 's/^/         | /'; }
# FAIL の詳細（-v のときだけ差分を出す）。差分の対象は set_diff で先に登録しておく
DIFF_A=""; DIFF_B=""; DIFF_LABEL=""
set_diff(){ DIFF_A="$1"; DIFF_B="$2"; DIFF_LABEL="$3"; }
fail_diff(){ # $1=項目 $2=理由
  verdict FAIL "$1" "$2"
  if [ "$VERBOSE" -eq 1 ] && [ -n "$DIFF_A" ]; then
    printf '         | %s
' "$DIFF_LABEL"
    diff "$DIFF_A" "$DIFF_B" | sed -n '1,20p' | sed 's/^/         | /'
  fi
  DIFF_A=""; DIFF_B=""
}

getsec(){ awk -v h="@@ $2" '$0 == h { f = 1; next } /^@@ / { f = 0 } f' "$VK_TMP/r-$1.txt"; }
val(){ printf '%s\n' "${1#*$'\t'}"; }   # 「タグ<TAB>値」の値

# 系統の一覧から、結果のある系統（ok / crashed）を返す。missing は除く
usable(){ local s; for s in "$@"; do [ "${SYS_STATE[$s]}" = missing ] || printf '%s\n' "$s"; done; }
labels(){ local s out=""; for s in "$@"; do out+="${out:+ / }${SYS_LABEL[$s]}"; done; printf '%s' "$out"; }
missing_note(){ # 対象系統のうち無いものを「（5.1: 理由）」の形で返す
  local s out=""
  for s in "$@"; do [ "${SYS_STATE[$s]}" = missing ] && out+="${out:+、}${SYS_LABEL[$s]}: ${SYS_WHY[$s]}"; done
  [ -n "$out" ] && printf '（%s）' "$out"
}
crashed_in(){ local s; for s in "$@"; do [ "${SYS_STATE[$s]}" = crashed ] && { printf '%s' "$s"; return 0; }; done; return 1; }

# 期待値ファイルの鍵（行頭の列）が列挙に存在するかを逆方向にも照合する。鍵を書き間違えた行は、列挙側の照合（ケースごとに
# 期待値の行があるか）では見えず、黙って無視されたまま PASS になりうる。不正があれば理由を stdout に出して 1 を返す
# （verify-kit.ps1 の Test-FixKeys と同じ文言）。# 始まりと空行は対象外。
vk_check_keys(){ # $1=verify-kit.d のファイル名 $2=許可する鍵（空白区切り） $3=列挙の説明 $4=必要な列数（省略可）
  local f="$1" allow="$2" what="$3" min="${4:-0}" line key w ok n
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    key="${line%%$'\t'*}"
    ok=0
    for w in $allow; do [ "$w" = "$key" ] && { ok=1; break; }; done
    if [ "$ok" -eq 0 ]; then printf '%s: 行頭の鍵「%s」が%sに無い（行: %s）\n' "$f" "$key" "$what" "$line"; return 1; fi
    if [ "$min" -gt 0 ]; then
      n="$(printf '%s' "$line" | tr -cd '\t' | wc -c)"
      if [ "$((n + 1))" -lt "$min" ]; then printf '%s: 列が足りない（%s 列必要）（行: %s）\n' "$f" "$min" "$line"; return 1; fi
    fi
  done < "$VK_FIX/$f"
  return 0
}
# launcher-cases.txt: 行頭タグ（case / in / out）・case 行の名前と opts|none・case より前の in / out を検査する
vk_check_launcher_cases(){
  local f=launcher-cases.txt line key rest name o seen=0
  vk_check_keys "$f" "case in out" "定義済みの行頭タグ（case / in / out）" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    key="${line%%$'\t'*}"
    if [ "$key" = case ]; then
      seen=1
      rest="${line#*$'\t'}"; [ "$rest" = "$line" ] && rest=""
      name="${rest%%$'\t'*}"
      o=""; case "$rest" in *$'\t'*) o="${rest#*$'\t'}"; o="${o%%$'\t'*}";; esac
      if [ -z "$name" ]; then printf '%s: case 行の名前が空（行: %s）\n' "$f" "$line"; return 1; fi
      case "$o" in opts|none) ;; *) printf '%s: case 行の第 3 列は opts か none（行: %s）\n' "$f" "$line"; return 1;; esac
    elif [ "$seen" -eq 0 ]; then
      printf '%s: case 行より前に %s 行がある（行: %s）\n' "$f" "$key" "$line"; return 1
    fi
  done < "$VK_FIX/$f"
  return 0
}

# 系統ごとの節を書き出して全系統一致かを調べる。食い違えば SAME_A / SAME_B に系統を入れて 1 を返す
SAME_A=""; SAME_B=""
same_all(){ # $1=節 $2=フィルタ（sed 式。空なら無し） 残り=系統
  local secn="$1" flt="$2"; shift 2
  local s first=""
  for s in "$@"; do
    if [ -n "$flt" ]; then getsec "$s" "$secn" | sed "$flt" > "$VK_TMP/c-$s"; else getsec "$s" "$secn" > "$VK_TMP/c-$s"; fi
    if [ -z "$first" ]; then first="$s"; elif ! cmp -s "$VK_TMP/c-$first" "$VK_TMP/c-$s"; then
      SAME_A="$first"; SAME_B="$s"
      set_diff "$VK_TMP/c-$first" "$VK_TMP/c-$s" "${SYS_LABEL[$first]} と ${SYS_LABEL[$s]} の差分（$secn）:"
      return 1
    fi
  done
  return 0
}

find_exe(){ local c; for c in "$@"; do command -v "$c" 2>/dev/null && return 0; done; return 1; }

run_probes(){
  local s exe ed
  for s in "${SYS_ALL[@]}"; do SYS_STATE[$s]=missing; done
  SYS_STATE[bash]=ok
  PWSH_EXE="$(find_exe pwsh pwsh.exe || true)"
  PS51_EXE="$(find_exe powershell.exe || true)"
  [ -n "$PWSH_EXE" ] && SYS_STATE[pwsh]=ok || SYS_WHY[pwsh]="pwsh が見つからない"
  [ -n "$PS51_EXE" ] && SYS_STATE[ps51]=ok || SYS_WHY[ps51]="powershell.exe が見つからない"
  [ -f "$VK_PS1" ] || { SYS_STATE[pwsh]=missing; SYS_STATE[ps51]=missing; SYS_WHY[pwsh]="verify-kit.ps1 が無い"; SYS_WHY[ps51]="verify-kit.ps1 が無い"; }
  for s in "${SYS_ALL[@]}"; do
    [ "${SYS_STATE[$s]}" = ok ] || continue
    case "$s" in
      bash) "$BASH" "$VK_SELF" --probe "$VK_TMP/r-bash.txt" > "$VK_TMP/log-bash.txt" 2>&1 < /dev/null;;
      pwsh) "$PWSH_EXE" -NoProfile -ExecutionPolicy Bypass -File "$(vk_native "$VK_PS1")" -Probe -Out "$(vk_native "$VK_TMP/r-pwsh.txt")" \
              > "$VK_TMP/log-pwsh.txt" 2>&1 < /dev/null;;
      ps51) "$PS51_EXE" -NoProfile -ExecutionPolicy Bypass -File "$(vk_native "$VK_PS1")" -Probe -Out "$(vk_native "$VK_TMP/r-ps51.txt")" \
              > "$VK_TMP/log-ps51.txt" 2>&1 < /dev/null;;
    esac
    if [ ! -f "$VK_TMP/r-$s.txt" ] || [ "$(tail -n 1 "$VK_TMP/r-$s.txt")" != "@@ end" ]; then
      SYS_STATE[$s]=crashed; SYS_WHY[$s]="probe が異常終了した"
      touch "$VK_TMP/r-$s.txt"
    fi
    ed="$(getsec "$s" meta | sed -n 's/^EDITION\t//p')"
    SYS_VER[$s]="$(getsec "$s" meta | sed -n 's/^VERSION\t//p')"
    # powershell.exe が Desktop 版（5.1）でない、pwsh が Core 版でない、のいずれかなら系統として扱わない
    if [ "${SYS_STATE[$s]}" = ok ]; then
      case "$s:$ed" in
        pwsh:Core|ps51:Desktop|bash:-) ;;
        *) SYS_STATE[$s]=missing; SYS_WHY[$s]="想定と違うエディション（${ed:-不明}）";;
      esac
    fi
  done
}

# ---- 各検査 -------------------------------------------------------------------
item_syntax(){ # $1=系統 $2=項目名
  local s="$1" t="$2" n ng
  if [ "${SYS_STATE[$s]}" = missing ]; then verdict SKIP "$t" "${SYS_WHY[$s]}"; return; fi
  if [ "${SYS_STATE[$s]}" = crashed ]; then verdict FAIL "$t" "probe が異常終了した（-v でログ）"; return; fi
  getsec "$s" syntax > "$VK_TMP/i-syn"
  if grep -q '^SKIP' "$VK_TMP/i-syn"; then verdict SKIP "$t" "$(val "$(grep -m1 '^SKIP' "$VK_TMP/i-syn")")"; return; fi
  n="$(grep -c -E $'^(OK|NG)\t' "$VK_TMP/i-syn")"
  ng="$(grep -c $'^NG\t' "$VK_TMP/i-syn")"
  if [ "$n" -eq 0 ]; then verdict FAIL "$t" "対象ファイルが無い"; return; fi
  if [ "$ng" -gt 0 ]; then verdict FAIL "$t" "${ng}/${n} ファイルでエラー: $(val "$(grep -m1 $'^NG\t' "$VK_TMP/i-syn")")"; return; fi
  verdict PASS "$t" "${n} ファイル エラー 0"
}

fmt_class(){ # 保存形式の区分: ps（BOM + CRLF）/ lfnobom（CR 0・BOM なし）/ lf（CR 0）/ none（対象外）
  case "$1" in
    scripts/verify-kit.d/*) echo lfnobom; return;;
  esac
  case "${1##*/}" in
    *.ps1|*.psm1|*.psd1|*.ps1.template) echo ps;;
    *.sh|*.sh.template) echo lfnobom;;
    *.md|*.json|*.template|.gitignore) echo lf;;
    *) echo none;;
  esac
}

item_format(){
  local t="保存形式（BOM / CR / LF）" c d n=0 nps=0 nlf=0 nnone=0 bad=0 first="" tag rel bom cr lf cls
  local -a S
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  getsec "${S[0]}" format > "$VK_TMP/i-fmt"
  if grep -q '^SKIP' "$VK_TMP/i-fmt"; then verdict SKIP "$t" "$(val "$(grep -m1 '^SKIP' "$VK_TMP/i-fmt")")"; return; fi
  if ! same_all format "" "${S[@]}"; then
    fail_diff "$t" "計測が ${SYS_LABEL[$SAME_A]} と ${SYS_LABEL[$SAME_B]} で食い違う（計測方法の不備を疑う）"; return
  fi
  while IFS=$'\t' read -r tag rel bom cr lf; do
    [ "$tag" = F ] || continue
    n=$((n + 1)); cls="$(fmt_class "$rel")"
    case "$cls" in
      ps) nps=$((nps + 1))
          if [ "$bom" != efbbbf ] || [ "$cr" -ne "$lf" ] || [ "$lf" -eq 0 ]; then
            bad=$((bad + 1)); [ -n "$first" ] || first="$rel（BOM=$bom CR=$cr LF=$lf。期待: BOM efbbbf・CR 数 = LF 数）"
          fi;;
      lf|lfnobom) nlf=$((nlf + 1))
          if [ "$cr" -ne 0 ] || { [ "$cls" = lfnobom ] && [ "$bom" = efbbbf ]; }; then
            bad=$((bad + 1)); [ -n "$first" ] || first="$rel（BOM=$bom CR=$cr。期待: CR 0$([ "$cls" = lfnobom ] && echo '・BOM なし')）"
          fi;;
      *) nnone=$((nnone + 1));;
    esac
  done < "$VK_TMP/i-fmt"
  if [ "$bad" -gt 0 ]; then verdict FAIL "$t" "${bad} ファイル不適合: $first"; return; fi
  verdict PASS "$t" "${n} ファイル（BOM+CRLF ${nps}・LF ${nlf}・対象外 ${nnone}）適合。計測は $(labels "${S[@]}") で一致$(missing_note "${SYS_ALL[@]}")"
}

item_version(){
  local t="ランチャー 実物 claude --version" s c pre rc out ver="" nskip=0 why=""
  local -a S
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  for s in "${S[@]}"; do
    getsec "$s" version > "$VK_TMP/i-ver"
    pre="$(sed -n 's/^PRECHECK\t//p' "$VK_TMP/i-ver")"
    if [ "$pre" != ok ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: ${pre:-事前確認の結果が無い}"; return; fi
    if grep -q '^SKIP' "$VK_TMP/i-ver"; then nskip=$((nskip + 1)); why="$(val "$(grep -m1 '^SKIP' "$VK_TMP/i-ver")")"; continue; fi
    rc="$(sed -n 's/^RC\t//p' "$VK_TMP/i-ver")"; out="$(sed -n 's/^OUT\t//p' "$VK_TMP/i-ver")"
    if [ "$rc" != 0 ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: exit ${rc:-?}（出力: ${out}）"; return; fi
    if ! [[ "$out" =~ ^[0-9]+\.[0-9]+\.[0-9]+\ \(Claude\ Code\)$ ]]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 版表示の形式が違う（${out}）"; return; fi
    if [ -z "$ver" ]; then ver="$out"; elif [ "$ver" != "$out" ]; then verdict FAIL "$t" "系統間で版が違う（${ver} / ${out}）"; return; fi
  done
  if [ "$nskip" -eq "${#S[@]}" ]; then verdict SKIP "$t" "$why"; return; fi
  verdict PASS "$t" "$(labels "${S[@]}") とも ${ver}・exit 0（事前にスタブで引数が --version 1 個と確認）$(missing_note "${SYS_ALL[@]}")"
}

item_launcher(){
  local t="ランチャー 引数列（スタブ）" s c cs n=0 a bad
  local -a S CASES
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  if ! bad="$(vk_check_launcher_cases)"; then verdict FAIL "$t" "$bad"; return; fi
  mapfile -t CASES < <(vk_case_names)
  for cs in "${CASES[@]}"; do
    n=$((n + 1))
    vk_case_tag "$cs" out > "$VK_TMP/i-exp"
    for s in "${S[@]}"; do
      getsec "$s" "launcher $cs" > "$VK_TMP/i-l"
      a="$(sed -n 's/^ASSERT\t//p' "$VK_TMP/i-l")"
      if [ "$a" != ok ]; then verdict FAIL "$t" "${SYS_LABEL[$s]} ${cs}: ${a:-結果が無い}"; return; fi
      if ! grep -q $'^RAN\tyes' "$VK_TMP/i-l"; then verdict FAIL "$t" "${SYS_LABEL[$s]} ${cs}: スタブが起動していない"; return; fi
      sed -n 's/^ARG\t//p' "$VK_TMP/i-l" > "$VK_TMP/i-act"
      if ! cmp -s "$VK_TMP/i-exp" "$VK_TMP/i-act"; then
        set_diff "$VK_TMP/i-exp" "$VK_TMP/i-act" "期待（<）と ${SYS_LABEL[$s]} ${cs}（>）の差分:"
        fail_diff "$t" "${SYS_LABEL[$s]} ${cs}: claude に届いた引数列が期待と違う"; return
      fi
      if ! grep -q $'^RC\t0$' "$VK_TMP/i-l"; then verdict FAIL "$t" "${SYS_LABEL[$s]} ${cs}: ランチャーの終了コードが 0 でない"; return; fi
    done
  done
  verdict PASS "$t" "${n} ケース（プロンプトのみ＝-- 挿入・フラグ先行・引数なし・オプション無し。= を含むキーあり）× $(labels "${S[@]}") が期待どおり$(missing_note "${SYS_ALL[@]}")"
}

item_launcher_stalerc(){
  local t='ランチャー 古い $LASTEXITCODE を返さない（スタブ）' s c a
  local -a S
  mapfile -t S < <(usable pwsh ps51)
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "PowerShell 系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  for s in "${S[@]}"; do
    getsec "$s" launcher-stalerc > "$VK_TMP/i-sr"
    a="$(sed -n 's/^ASSERT	//p' "$VK_TMP/i-sr")"
    if [ "$a" != ok ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: ${a:-結果が無い}"; return; fi
    if ! grep -q $'^RC	0$' "$VK_TMP/i-sr"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 呼び出し元の古い \$LASTEXITCODE（7）が返った（RC=$(sed -n 's/^RC	//p' "$VK_TMP/i-sr")）"; return; fi
  done
  verdict PASS "$t" "$(labels "${S[@]}") とも、呼び出し元に \$LASTEXITCODE=7 が残り claude スタブが設定しなくても exit 0$(missing_note pwsh ps51)"
}

item_optset(){
  local t="option-settings テンプレ（全項目を有効化してロード）" s c d lines nk
  local -a S
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  for s in "${S[@]}"; do
    getsec "$s" optset > "$VK_TMP/i-o"
    if ! grep -q $'^LOAD\tok$' "$VK_TMP/i-o"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 全項目版がロードできない（$(sed -n 's/^LOAD\t//p' "$VK_TMP/i-o")）"; return; fi
    if ! grep -q $'^ORIG\tok 0$' "$VK_TMP/i-o"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 原本（全コメント）のロード結果が想定外（$(sed -n 's/^ORIG\t//p' "$VK_TMP/i-o")）"; return; fi
    lines="$(sed -n 's/^LINES\t//p' "$VK_TMP/i-o")"; nk="$(grep -c $'^KEY\t' "$VK_TMP/i-o")"
    if [ "$lines" != "$nk" ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 有効化した ${lines} 行に対しキーが ${nk} 個（重複キー?）"; return; fi
  done
  if ! same_all optset "" "${S[@]}"; then
    fail_diff "$t" "キー集合が ${SYS_LABEL[$SAME_A]} と ${SYS_LABEL[$SAME_B]} で違う"; return
  fi
  verdict PASS "$t" "${nk} キーが $(labels "${S[@]}") で一致。原本もロード可$(missing_note "${SYS_ALL[@]}")"
}

item_setupenv(){
  local t="setup-environment（custom.env fixture）" s c cs k first="" bad="" allow
  local -a S
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  if ! bad="$(vk_check_keys setup-environment.expect "SET" "定義済みの行頭タグ（SET）")"; then verdict FAIL "$t" "$bad"; return; fi
  sed -n 's/^SET\t//p' "$VK_FIX/setup-environment.expect" > "$VK_TMP/i-exp"
  : > "$VK_TMP/i-allow"
  for s in "${S[@]}"; do
    for cs in plain bomcrlf; do
      getsec "$s" "setupenv $cs" > "$VK_TMP/i-se"
      if grep -q '^ERR' "$VK_TMP/i-se"; then verdict FAIL "$t" "${SYS_LABEL[$s]} ${cs}: $(val "$(grep -m1 '^ERR' "$VK_TMP/i-se")")"; return; fi
      # 許容差: Windows は空値の環境変数を保持できない（PS 版は警告して設定しない）
      sed -n 's/^WARN\tcustom\.env の \(.*\) は空値のため設定しません.*/\1/p' "$VK_TMP/i-se" > "$VK_TMP/i-empty"
      while IFS= read -r k; do
        grep -qxF "${k}=" "$VK_TMP/i-exp" || { bad="${SYS_LABEL[$s]} ${cs}: 空値の警告が出た ${k} は fixture で空値ではない"; break; }
      done < "$VK_TMP/i-empty"
      [ -z "$bad" ] || { verdict FAIL "$t" "$bad"; return; }
      grep -vxF -f <(sed 's/$/=/' "$VK_TMP/i-empty") "$VK_TMP/i-exp" > "$VK_TMP/i-exp-s" || true
      sed -n 's/^SET\t//p' "$VK_TMP/i-se" > "$VK_TMP/i-act"
      if ! cmp -s "$VK_TMP/i-exp-s" "$VK_TMP/i-act"; then
        set_diff "$VK_TMP/i-exp-s" "$VK_TMP/i-act" "期待（<）と ${SYS_LABEL[$s]} ${cs}（>）の差分:"
        fail_diff "$t" "${SYS_LABEL[$s]} ${cs}: 設定された環境変数が期待と違う"; return
      fi
      if grep -q '^UNSET' "$VK_TMP/i-se"; then verdict FAIL "$t" "${SYS_LABEL[$s]} ${cs}: 環境変数を削除している"; return; fi
      cat "$VK_TMP/i-empty" >> "$VK_TMP/i-allow"
      # 系統間・ケース間の比較用（空値の SET 行と空値の警告を除いた形）
      grep -v -E $'^SET\t[^=]*=$|^WARN\tcustom\\.env の .* は空値のため設定しません' "$VK_TMP/i-se" > "$VK_TMP/n-$s-$cs" || true
      if [ -z "$first" ]; then first="$VK_TMP/n-$s-$cs"
      elif ! cmp -s "$first" "$VK_TMP/n-$s-$cs"; then
        set_diff "$first" "$VK_TMP/n-$s-$cs" "最初の系統・ケース（<）と ${SYS_LABEL[$s]} ${cs}（>）の差分:"
        fail_diff "$t" "${SYS_LABEL[$s]} ${cs}: 設定結果か警告が他の系統・ケースと違う"; return
      fi
    done
  done
  allow="$(LC_ALL=C sort -u "$VK_TMP/i-allow" | tr '\n' ' ' | sed 's/ $//')"
  verdict PASS "$t" "plain / BOM+CRLF × $(labels "${S[@]}") で設定結果・警告が一致し期待どおり${allow:+（許容差: Windows は空値の env を設定しない: ${allow}）}$(missing_note "${SYS_ALL[@]}")"
}

# ランチャーの内部変数名の集合は 3 か所に同じ名前が並ぶ: setup-environment.sh の case "${_key}" in 直後の IFS|…) 行、
# setup-environment.ps1 の $LauncherInternalKeys 配列、docs/launcher/launcher-implementation-plan.md の「内部変数名**（…）」の
# 列挙。片方だけ直すと分類A ガードの穴が黙って開く（custom.env fixture だけでは気付けない）ので、名前の集合を抽出して突き合わせる。
# 形が崩れて抽出できないときも FAIL にする（黙って PASS にしない）。verify-kit.ps1 の Item-InternalKeys と同じ手順・文言。
item_internal_keys(){
  local t="setup-environment 内部変数名の集合（sh / ps1 / docs）" d="$VK_TMP/ik"
  local shf="$VK_ROOT/.claude/launcher/setup-environment.sh" psf="$VK_ROOT/.claude/launcher/setup-environment.ps1"
  local mdf="$VK_ROOT/docs/launcher/launcher-implementation-plan.md"
  local f n line rest seg tok block left name absent diffs="" idre='^[A-Za-z_][A-Za-z0-9_]*$'
  mkdir -p "$d"
  for f in "$shf" "$psf" "$mdf"; do
    [ -f "$f" ] || { verdict FAIL "$t" "ファイルが無い: ${f#"$VK_ROOT"/}"; return; }
  done
  # sh: case "${_key}" in の次の行（名前|名前|…)）
  n="$(grep -cF 'case "${_key}" in' "$shf")"
  if [ "$n" -ne 1 ]; then verdict FAIL "$t" "setup-environment.sh: case \"\${_key}\" in の行が 1 個ではない（${n} 個）"; return; fi
  line="$(grep -F -A1 'case "${_key}" in' "$shf" | sed -n 2p | tr -d '\r')"
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
  if ! [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*(\|[A-Za-z_][A-Za-z0-9_]*)*\)$ ]]; then
    verdict FAIL "$t" "setup-environment.sh: case 行の形（名前|名前|…)）が崩れていて抽出できない: ${line}"; return
  fi
  printf '%s\n' "${line%)}" | tr '|' '\n' | LC_ALL=C sort -u > "$d/sh.txt"
  # ps1: $LauncherInternalKeys = @( … ) の中の '名前'
  n="$(tr -d '\r' < "$psf" | grep -c '^\$LauncherInternalKeys = @($')"
  if [ "$n" -ne 1 ]; then verdict FAIL "$t" "setup-environment.ps1: \$LauncherInternalKeys = @( の行が 1 個ではない（${n} 個）"; return; fi
  block="$(tr -d '\r' < "$psf" | awk '/^\$LauncherInternalKeys = @\($/ { on = 1; next } on && /^\)$/ { print "@@closed"; exit } on { print }')"
  if [ "$(printf '%s\n' "$block" | tail -n 1)" != "@@closed" ]; then verdict FAIL "$t" "setup-environment.ps1: \$LauncherInternalKeys の閉じ ) が行頭に見つからない"; return; fi
  block="$(printf '%s\n' "$block" | sed '$d')"
  left="$(printf '%s\n' "$block" | sed -E "s/'[A-Za-z_][A-Za-z0-9_]*'//g; s/[,[:space:]]//g")"
  if [ -n "$left" ]; then verdict FAIL "$t" "setup-environment.ps1: 配列の形（'名前', '名前', …）が崩れていて抽出できない: ${left}"; return; fi
  printf '%s\n' "$block" | grep -oE "'[A-Za-z_][A-Za-z0-9_]*'" | tr -d "'" | LC_ALL=C sort -u > "$d/ps1.txt"
  if [ ! -s "$d/ps1.txt" ]; then verdict FAIL "$t" "setup-environment.ps1: \$LauncherInternalKeys に名前が 1 個も無い"; return; fi
  # docs: 「内部変数名**（…）」の括弧内。名前は `…` で囲まれ、start_claude_code.sh のようなファイル名は名前に数えない
  n="$(tr -d '\r' < "$mdf" | grep -F '内部変数名**（' | grep -cF '`_SENSITIVE_KEYS`')"
  if [ "$n" -ne 1 ]; then verdict FAIL "$t" "launcher-implementation-plan.md: 「内部変数名**（」と \`_SENSITIVE_KEYS\` を含む行が 1 行ではない（${n} 行）"; return; fi
  line="$(tr -d '\r' < "$mdf" | grep -F '内部変数名**（' | grep -F '`_SENSITIVE_KEYS`')"
  rest="${line#*'内部変数名**（'}"
  seg="${rest%%）*}"
  if [ "$seg" = "$rest" ]; then verdict FAIL "$t" "launcher-implementation-plan.md: 内部変数名の列挙の閉じ括弧 ） が見つからない"; return; fi
  : > "$d/docs.txt"
  while IFS= read -r tok; do
    tok="${tok//\`/}"
    if [[ "$tok" =~ $idre ]]; then printf '%s\n' "$tok" >> "$d/docs.txt"
    elif ! [[ "$tok" =~ ^[A-Za-z0-9_.-]+\.sh$ ]]; then
      verdict FAIL "$t" "launcher-implementation-plan.md: 内部変数名の列挙に名前でもファイル名でもない \`${tok}\` がある"; return
    fi
  done < <(printf '%s\n' "$seg" | grep -o '`[^`]*`')
  left="$(printf '%s\n' "$seg" | sed 's/`[^`]*`//g' | LC_ALL=C grep -o '[A-Za-z_]' | tr -d '\n')"
  if [ -n "$left" ]; then verdict FAIL "$t" "launcher-implementation-plan.md: 内部変数名の列挙にバッククォートで囲まれていない英字がある: ${left}"; return; fi
  LC_ALL=C sort -u -o "$d/docs.txt" "$d/docs.txt"
  if [ ! -s "$d/docs.txt" ]; then verdict FAIL "$t" "launcher-implementation-plan.md: 内部変数名の列挙に名前が 1 個も無い"; return; fi
  while IFS= read -r name; do
    absent=""
    grep -qxF -- "$name" "$d/sh.txt" || absent+="${absent:+・}sh"
    grep -qxF -- "$name" "$d/ps1.txt" || absent+="${absent:+・}ps1"
    grep -qxF -- "$name" "$d/docs.txt" || absent+="${absent:+・}docs"
    [ -z "$absent" ] || diffs+="${diffs:+、}${name}（${absent} に無い）"
  done < <(cat "$d/sh.txt" "$d/ps1.txt" "$d/docs.txt" | LC_ALL=C sort -u)
  if [ -n "$diffs" ]; then verdict FAIL "$t" "名前の集合が一致しない: ${diffs}"; return; fi
  verdict PASS "$t" "sh / ps1 / docs の 3 者で同じ集合（$(wc -l < "$d/sh.txt" | tr -d ' ') 個: $(tr '\n' ' ' < "$d/sh.txt" | sed 's/ $//')）"
}

item_ca_root(){
  local t="check-assets リポジトリルート" s c d nw nf
  local -a S
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  drop_skipping "checkassets root" -- "${S[@]}"
  if [ "${#KEPT[@]}" -eq 0 ]; then verdict SKIP "$t" "$SKIP_NOTE"; return; fi
  S=("${KEPT[@]}")
  if ! same_all "checkassets root" "" "${S[@]}"; then
    fail_diff "$t" "出力が ${SYS_LABEL[$SAME_A]} と ${SYS_LABEL[$SAME_B]} で違う"; return
  fi
  getsec "${S[0]}" "checkassets root" > "$VK_TMP/i-ca"
  nf="$(grep -c -E $'^O\t[[:space:]]*\\[FAIL\\]' "$VK_TMP/i-ca")"; nw="$(grep -c -E $'^O\t[[:space:]]*\\[WARN\\]' "$VK_TMP/i-ca")"
  if ! grep -q $'^RC\t0$' "$VK_TMP/i-ca"; then verdict FAIL "$t" "FAIL ${nf} 件（exit $(sed -n 's/^RC\t//p' "$VK_TMP/i-ca")）"; return; fi
  verdict PASS "$t" "$(labels "${S[@]}") の出力が一致・FAIL=0（WARN ${nw}）$(missing_note "${SYS_ALL[@]}")${SKIP_NOTE:+（${SKIP_NOTE}）}"
}

# 指定した節のどれかで SKIP を出した系統を除く。残りを KEPT に、除いた系統と理由を SKIP_NOTE に入れる
KEPT=(); SKIP_NOTE=""
drop_skipping(){ # 節… -- 系統…
  local -a secs=()
  local s n l
  while [ "$1" != "--" ]; do secs+=("$1"); shift; done
  shift
  KEPT=(); SKIP_NOTE=""
  for s in "$@"; do
    l=""
    for n in "${secs[@]}"; do l="$(getsec "$s" "$n" | grep -m1 '^SKIP')" && break; done
    if [ -n "$l" ]; then SKIP_NOTE+="${SKIP_NOTE:+、}${SYS_LABEL[$s]}: $(val "$l")"; else KEPT+=("$s"); fi
  done
}

# check-assets の fixture のケースを全系統で突き合わせ、期待値と照合する（item_ca_fixture / item_ca_links が使う）。
#   $1=項目名 $2=PASS の説明 残り=ケース。期待値ファイルの鍵は CA_CASES と CA_LINK_CASES を合わせた列挙に照らす
ca_cases_check(){
  local t="$1" desc="$2" s c d cs erc tag frag n bad all; shift 2
  local -a S secs=() cases=("$@")
  all="${CA_CASES[*]} ${CA_LINK_CASES[*]}"
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  if ! bad="$(vk_check_keys check-assets.expect "$all" "ケースの列挙（${all}）" 4)"; then verdict FAIL "$t" "$bad"; return; fi
  for cs in "${cases[@]}"; do secs+=("checkassets $cs"); done
  drop_skipping "${secs[@]}" -- "${S[@]}"
  if [ "${#KEPT[@]}" -eq 0 ]; then verdict SKIP "$t" "$SKIP_NOTE"; return; fi
  S=("${KEPT[@]}")
  for cs in "${cases[@]}"; do
    n="$(cut -f1 "$VK_FIX/check-assets.expect" | grep -cx -- "$cs")"   # grep -q は SIGPIPE を招くので件数で受ける
    if [ "${n:-0}" -eq 0 ]; then verdict FAIL "$t" "${cs}: check-assets.expect に期待値が無い"; return; fi
    if ! same_all "checkassets $cs" "" "${S[@]}"; then
      fail_diff "$t" "${cs}: 判定が ${SYS_LABEL[$SAME_A]} と ${SYS_LABEL[$SAME_B]} で違う"; return
    fi
    getsec "${S[0]}" "checkassets $cs" > "$VK_TMP/i-cf"
    while IFS=$'\t' read -r c erc tag frag; do
      [ "$c" = "$cs" ] || continue
      if ! grep -q "^RC"$'\t'"${erc}\$" "$VK_TMP/i-cf"; then verdict FAIL "$t" "${cs}: 終了コードが期待（${erc}）と違う"; return; fi
      # タグ - はタグの無い行（ファイル一覧）も対象にする。grep -q の SIGPIPE を避けるため件数で受ける
      if [ "$tag" = - ]; then
        n="$(sed -n 's/^O\t[[:space:]]*//p' "$VK_TMP/i-cf" | grep -cF -- "$frag")"
      else
        n="$(sed -n 's/^O\t[[:space:]]*//p' "$VK_TMP/i-cf" | grep -F "[$tag]" | grep -cF -- "$frag")"
      fi
      if [ "${n:-0}" -eq 0 ]; then
        verdict FAIL "$t" "${cs}: [${tag}] ${frag} の行が無い"; return
      fi
    done < <(grep -v '^#' "$VK_FIX/check-assets.expect")
  done
  verdict PASS "$t" "${#cases[@]} ケース × $(labels "${S[@]}") で同一判定・期待どおり（${desc}）$(missing_note "${SYS_ALL[@]}")${SKIP_NOTE:+（${SKIP_NOTE}）}"
}
item_ca_fixture(){
  ca_cases_check "check-assets fixture（U/M/E・無害・壊れた JSON・BOM・重複キー・worktree・大文字小文字違い・バイナリ・隠し属性・並び順）" \
    "U/M/E と絶対パス混在は WARN・無害は PASS・壊れた JSON と BOM 付きと重複キー・worktree の混入は FAIL・成果物の大文字小文字違いは payload で FAIL・git で WARN（Worktrees にも 2-c' は降りない）、env キーの大文字小文字違いは WARN で、完全一致は従来どおり・先頭 8000 バイトに NUL があれば 2-e の対象外・隠し属性も数える・一覧は序数順" \
    "${CA_CASES[@]}"
}
item_ca_links(){
  ca_cases_check "check-assets リンク（ジャンクション / シンボリックリンク）" \
    "リンクは辿らず、…/results のディレクトリとしても数えない（2-c' は PASS）・リンク先のファイルを 2-e で読まない" \
    "${CA_LINK_CASES[@]}"
}

item_cleanenv(){
  local t="clean-test-env（スタブ）" s c a frag first="" bad
  local -a S
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  if ! bad="$(vk_check_keys clean-test-env.txt "PRE OUTHAS ARG ENV CWD SETTINGS AFTER BADMODE BADRC BADOUT BADSHARERC BADSHAREOUT" "定義済みの行頭タグ（PRE / OUTHAS / ARG / ENV / CWD / SETTINGS / AFTER / BADMODE / BADRC / BADOUT / BADSHARERC / BADSHAREOUT）")"; then verdict FAIL "$t" "$bad"; return; fi
  grep -E $'^(ARG|ENV|CWD|SETTINGS|AFTER)\t' "$VK_FIX/clean-test-env.txt" > "$VK_TMP/i-exp"
  for s in "${S[@]}"; do
    getsec "$s" cleanenv > "$VK_TMP/i-ce"
    a="$(sed -n 's/^ASSERT\t//p' "$VK_TMP/i-ce")"
    if [ "$a" != ok ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: ${a:-結果が無い}"; return; fi
    if ! grep -q $'^RAN\tyes' "$VK_TMP/i-ce"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: スタブが起動していない"; return; fi
    if ! grep -q $'^RC\t0$' "$VK_TMP/i-ce"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 終了コードが 0 でない"; return; fi
    grep -E $'^(ARG|ENV|CWD|SETTINGS|AFTER)\t' "$VK_TMP/i-ce" > "$VK_TMP/i-act"
    if ! cmp -s "$VK_TMP/i-exp" "$VK_TMP/i-act"; then
      set_diff "$VK_TMP/i-exp" "$VK_TMP/i-act" "期待（<）と ${SYS_LABEL[$s]}（>）の差分:"
      fail_diff "$t" "${SYS_LABEL[$s]}: 起動引数・環境・生成 settings・復元のいずれかが期待と違う"; return
    fi
    while IFS=$'\t' read -r c frag; do
      [ "$c" = OUTHAS ] || continue
      grep -q "^O"$'\t' "$VK_TMP/i-ce" && sed -n 's/^O\t//p' "$VK_TMP/i-ce" | grep -qF -- "$frag" \
        || { verdict FAIL "$t" "${SYS_LABEL[$s]}: 出力に「${frag}」が無い"; return; }
    done < "$VK_FIX/clean-test-env.txt"
    # PS 版だけが出す「環境変数を元に戻しました」（$env: の復元。bash は子プロセスなので不要）を除いて比較する
    grep $'^O\t' "$VK_TMP/i-ce" | grep -v '環境変数を元に戻しました' > "$VK_TMP/n-ce-$s" || true
    if [ -z "$first" ]; then first="$VK_TMP/n-ce-$s"
    elif ! cmp -s "$first" "$VK_TMP/n-ce-$s"; then
      set_diff "$first" "$VK_TMP/n-ce-$s" "最初の系統（<）と ${SYS_LABEL[$s]}（>）の出力の差分:"
      fail_diff "$t" "${SYS_LABEL[$s]}: 出力が他の系統と違う"; return
    fi
  done
  verdict PASS "$t" "$(labels "${S[@]}"): 起動引数・同期停止 settings・plugin 系 env の切り離しと呼び出し元の復元が期待どおりで一致$(missing_note "${SYS_ALL[@]}")"
}

item_cleanenv_badmode(){
  local t="clean-test-env 不正な権限モード（スタブ）" s c i n erc frag m a modes=""
  local -a S
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  n="$(grep -c $'^BADMODE\t' "$VK_FIX/clean-test-env.txt")"
  erc="$(sed -n 's/^BADRC\t//p' "$VK_FIX/clean-test-env.txt" | head -n 1)"
  frag="$(sed -n 's/^BADOUT\t//p' "$VK_FIX/clean-test-env.txt" | head -n 1)"
  if [ "$n" -eq 0 ] || [ -z "$erc" ] || [ -z "$frag" ]; then verdict FAIL "$t" "fixture に BADMODE / BADRC / BADOUT が無い"; return; fi
  for ((i = 1; i <= n; i++)); do
    m="$(sed -n 's/^BADMODE\t//p' "$VK_FIX/clean-test-env.txt" | sed -n "${i}p")"
    modes+="${modes:+ / }${m}"
    for s in "${S[@]}"; do
      getsec "$s" "cleanenv-badmode $i" > "$VK_TMP/i-bm"
      a="$(sed -n 's/^ASSERT\t//p' "$VK_TMP/i-bm")"
      if [ "$a" != ok ]; then verdict FAIL "$t" "${SYS_LABEL[$s]} '${m}': ${a:-結果が無い}"; return; fi
      if [ "$(sed -n 's/^MODE\t//p' "$VK_TMP/i-bm")" != "$m" ]; then verdict FAIL "$t" "${SYS_LABEL[$s]} ${i} 件目: ケースの対応が取れない"; return; fi
      if ! grep -q $'^RAN\tno$' "$VK_TMP/i-bm"; then verdict FAIL "$t" "${SYS_LABEL[$s]} '${m}': 不正な権限モードのまま claude を起動した"; return; fi
      if ! grep -q "^RC"$'\t'"${erc}\$" "$VK_TMP/i-bm"; then verdict FAIL "$t" "${SYS_LABEL[$s]} '${m}': 終了コードが期待（${erc}）と違う（$(sed -n 's/^RC\t//p' "$VK_TMP/i-bm")）"; return; fi
      if [ "$(sed -n 's/^E\t//p' "$VK_TMP/i-bm" | grep -cF -- "$frag")" -eq 0 ]; then verdict FAIL "$t" "${SYS_LABEL[$s]} '${m}': stderr に「${frag}」が無い"; return; fi
      if [ "$(sed -n 's/^O\t//p' "$VK_TMP/i-bm" | grep -cF -- "$frag")" -ne 0 ]; then verdict FAIL "$t" "${SYS_LABEL[$s]} '${m}': エラー文が stdout にも出ている（stderr のみのはず）"; return; fi
    done
    if ! same_all "cleanenv-badmode $i" "" "${S[@]}"; then
      fail_diff "$t" "'${m}': 出力が ${SYS_LABEL[$SAME_A]} と ${SYS_LABEL[$SAME_B]} で違う"; return
    fi
  done
  verdict PASS "$t" "${n} ケース（${modes}）× $(labels "${S[@]}") とも claude 起動前に exit ${erc} で停止し、出力が一致$(missing_note "${SYS_ALL[@]}")"
}

item_cleanenv_badshare(){
  local t="clean-test-env 存在しない <Share>（スタブ）" s c erc frag a
  local -a S
  mapfile -t S < <(usable "${SYS_ALL[@]}")
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "実行できる系統が無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  erc="$(sed -n 's/^BADSHARERC\t//p' "$VK_FIX/clean-test-env.txt" | head -n 1)"
  frag="$(sed -n 's/^BADSHAREOUT\t//p' "$VK_FIX/clean-test-env.txt" | head -n 1)"
  if [ -z "$erc" ] || [ -z "$frag" ]; then verdict FAIL "$t" "fixture に BADSHARERC / BADSHAREOUT が無い"; return; fi
  for s in "${S[@]}"; do
    getsec "$s" cleanenv-badshare > "$VK_TMP/i-bs"
    a="$(sed -n 's/^ASSERT\t//p' "$VK_TMP/i-bs")"
    if [ "$a" != ok ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: ${a:-結果が無い}"; return; fi
    if ! grep -q $'^RAN\tno$' "$VK_TMP/i-bs"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 存在しない <Share> のまま claude を起動した"; return; fi
    if ! grep -q "^RC"$'\t'"${erc}\$" "$VK_TMP/i-bs"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 終了コードが期待（${erc}）と違う（$(sed -n 's/^RC\t//p' "$VK_TMP/i-bs")）"; return; fi
    if [ "$(sed -n 's/^E\t//p' "$VK_TMP/i-bs" | grep -cF -- "$frag")" -eq 0 ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: stderr に「${frag}」が無い"; return; fi
    if [ "$(sed -n 's/^O\t//p' "$VK_TMP/i-bs" | grep -cF -- "$frag")" -ne 0 ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: エラー文が stdout にも出ている（stderr のみのはず）"; return; fi
    if ! grep -q $'^LEFT\t0$' "$VK_TMP/i-bs"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 一時領域に残骸がある（$(sed -n 's/^LEFT\t//p' "$VK_TMP/i-bs") 個。一時ディレクトリを作る前に止まっていない）"; return; fi
  done
  if ! same_all cleanenv-badshare "" "${S[@]}"; then
    fail_diff "$t" "出力が ${SYS_LABEL[$SAME_A]} と ${SYS_LABEL[$SAME_B]} で違う"; return
  fi
  verdict PASS "$t" "$(labels "${S[@]}") とも一時ディレクトリを作る前に exit ${erc} で停止（claude 未起動・残骸なし・文言は stderr のみ）し、出力が一致$(missing_note "${SYS_ALL[@]}")"
}

item_pubname(){
  local t="publish-plugin --name 検証" s c m modes="" i cls rest exp col idx nacc=0 nrej=0 narg=0 nother=0 eb ep name note=""
  local -a S
  mapfile -t S < <(usable bash pwsh)
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "bash / pwsh 7 がどちらも無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  for s in "${S[@]}"; do
    getsec "$s" pubname > "$VK_TMP/p-$s"
    m="$(sed -n 's/^MODE\t//p' "$VK_TMP/p-$s")"; modes+="$m "
    if [ "$m" = real ] && ! grep -q $'^ASSERT\tok' "$VK_TMP/p-$s"; then
      verdict FAIL "$t" "${SYS_LABEL[$s]}: $(sed -n 's/^ASSERT\t//p' "$VK_TMP/p-$s" | grep -v '^ok' | head -n 1)"; return
    fi
  done
  if [[ "$modes" == *fallback* ]]; then
    # 名前検証の順序を確かめられなかった版がある: 実スクリプトは実行せず、抽出した正規表現どうしの比較に落とす
    if [ "${#S[@]}" -lt 2 ]; then verdict SKIP "$t" "順序を確認できず、比較相手の系統も無い"; return; fi
    for s in "${S[@]}"; do
      sed -n 's/^REGEX\t//p' "$VK_TMP/p-$s" | sed -E 's/^\^//; s/(\\z|\$)$//' > "$VK_TMP/rx-$s"
      grep $'^CASE\t' "$VK_TMP/p-$s" | sed -E 's/ rc=.*//' > "$VK_TMP/pc-$s"
    done
    if cmp -s "$VK_TMP/rx-${S[0]}" "$VK_TMP/rx-${S[1]}" && cmp -s "$VK_TMP/pc-${S[0]}" "$VK_TMP/pc-${S[1]}"; then
      verdict PASS "$t" "フォールバック（名前検証が副作用より前にあると確認できず、実スクリプトは未実行）: 抽出した正規表現と $(wc -l < "$VK_TMP/pc-${S[0]}") ケースの判定が bash / pwsh で一致"
    else
      verdict FAIL "$t" "フォールバック（実スクリプト未実行）: 抽出した正規表現かケースの判定が bash / pwsh で違う"
    fi
    return
  fi
  for s in "${S[@]}"; do
    if ! grep -q $'^ORDER\tok' "$VK_TMP/p-$s"; then verdict FAIL "$t" "${SYS_LABEL[$s]}: 順序確認の結果が無い"; return; fi
    [ "$s" = bash ] && col=1 || col=2
    idx=0
    while IFS=$'\t' read -r eb ep name || [ -n "$eb" ]; do
      case "$eb" in ''|'#'*) continue;; esac
      idx=$((idx + 1))
      [ "$col" = 1 ] && exp="$eb" || exp="$ep"
      rest="$(grep -m1 "^CASE"$'\t'"${idx} " "$VK_TMP/p-$s" | cut -f2-)"
      cls="$(printf '%s' "$rest" | cut -d' ' -f2)"
      if [ "$cls" != "$exp" ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: '${name}' は ${exp} のはずが ${cls:-結果なし}（${rest}）"; return; fi
      # 名前検証で止まるケースでは git も claude も呼ばれていない（＝検証が副作用より前）。通過したケースではスタブの git が呼ばれる
      case "$cls" in
        accept) [[ "$rest" =~ stubcalls=[1-9] ]] || { verdict FAIL "$t" "${SYS_LABEL[$s]}: '${name}' で git スタブが呼ばれていない"; return; };;
        *) [[ "$rest" =~ stubcalls=0$ ]] || { verdict FAIL "$t" "${SYS_LABEL[$s]}: '${name}' の拒否より前に git / claude が呼ばれた"; return; };;
      esac
      if [ "$s" = "${S[0]}" ]; then
        if [ "$eb" = "$ep" ]; then
          case "$eb" in accept) nacc=$((nacc + 1));; argerr) narg=$((narg + 1));; *) nrej=$((nrej + 1));; esac
        else
          nother=$((nother + 1))
        fi
      fi
    done < "$VK_FIX/plugin-names.tsv"
  done
  [ "$nother" -gt 0 ] && note="・両版で期待が異なるケース ${nother} 件（plugin-names.tsv の列どおり）"
  verdict PASS "$t" "実スクリプト（git / claude はスタブ）で受理 ${nacc}・拒否 ${nrej}・引数エラー ${narg}${note}。$(labels "${S[@]}") とも期待どおり、拒否ケースでは git / claude 未呼び出し（5.1 は #requires -Version 7 のため対象外）$(missing_note bash pwsh)"
}

item_pubcase(){
  local t="publish-plugin 大文字小文字だけが違う既存エントリ（偽 marketplace）" s c exp ent name idx rest cls nclash=0 npass=0
  local -a S
  mapfile -t S < <(usable bash pwsh)
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "bash / pwsh 7 がどちらも無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  for s in "${S[@]}"; do
    getsec "$s" pubcase > "$VK_TMP/pk-$s"
    if ! grep -q $'^ASSERT\tok$' "$VK_TMP/pk-$s"; then
      verdict FAIL "$t" "${SYS_LABEL[$s]}: $(sed -n 's/^ASSERT\t//p' "$VK_TMP/pk-$s" | head -n 1)"; return
    fi
    idx=0
    while IFS=$'\t' read -r exp ent name || [ -n "$exp" ]; do
      case "$exp" in ''|'#'*) continue;; esac
      idx=$((idx + 1))
      rest="$(grep -m1 "^CASE"$'\t'"${idx} " "$VK_TMP/pk-$s" | cut -f2-)"
      cls="$(printf '%s' "$rest" | cut -d' ' -f2)"
      if [ "$cls" != "$exp" ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: plugins/${ent} に対する '${name}' は ${exp} のはずが ${cls:-結果なし}（${rest}）"; return; fi
      [[ "$rest" == *" intact=yes" ]] || { verdict FAIL "$t" "${SYS_LABEL[$s]}: '${name}' で既存の plugins/${ent} が変化した（${rest}）"; return; }
      if [ "$s" = "${S[0]}" ]; then
        case "$exp" in clash) nclash=$((nclash + 1));; *) npass=$((npass + 1));; esac
      fi
    done < "$VK_FIX/plugin-case.tsv"
  done
  verdict PASS "$t" "実スクリプト（git / claude はスタブ）で中止 ${nclash}・通過 ${npass}。$(labels "${S[@]}") とも期待どおり、中止は取り出しより前に exit 2・既存エントリは無傷（5.1 は #requires -Version 7 のため対象外）$(missing_note bash pwsh)"
}

item_pubmanifest(){
  local t="publish-plugin plugin.json の name 照合（一時リポジトリ）" s c eb ep py bom name json idx exp rest cls note="" ncmp=0 cmpnote=""
  local npass=0 nmis=0 nunr=0 nnopy=0
  local -a S RUN=()
  local -A SEEN=() CLS=()
  mapfile -t S < <(usable bash pwsh)
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "bash / pwsh 7 がどちらも無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  for s in "${S[@]}"; do
    getsec "$s" pubmanifest > "$VK_TMP/pm-$s"
    if grep -q '^SKIP' "$VK_TMP/pm-$s"; then note+="${note:+、}${SYS_LABEL[$s]}: $(val "$(grep -m1 '^SKIP' "$VK_TMP/pm-$s")")"; continue; fi
    if ! grep -q $'^ASSERT\tok$' "$VK_TMP/pm-$s"; then
      verdict FAIL "$t" "${SYS_LABEL[$s]}: $(sed -n 's/^ASSERT\t//p' "$VK_TMP/pm-$s" | head -n 1)"; return
    fi
    RUN+=("$s")
  done
  if [ "${#RUN[@]}" -eq 0 ]; then verdict SKIP "$t" "$note"; return; fi
  for s in "${RUN[@]}"; do
    idx=0
    while IFS=$'\t' read -r eb ep py bom name json || [ -n "$eb" ]; do
      case "$eb" in ''|'#'*) continue;; esac
      idx=$((idx + 1))
      [ "$s" = bash ] && exp="$eb" || exp="$ep"
      [ "$exp" = - ] && continue
      rest="$(grep -m1 "^CASE"$'\t'"${idx} " "$VK_TMP/pm-$s" | cut -f2-)"
      cls="$(printf '%s' "$rest" | cut -d' ' -f2)"
      CLS[$s:$idx]="$cls"
      if [ "$cls" = skip ]; then note+="${note:+、}${SYS_LABEL[$s]} ケース ${idx}: ${rest#* skip }"; continue; fi
      if [ "$cls" != "$exp" ]; then
        verdict FAIL "$t" "${SYS_LABEL[$s]}: ケース ${idx}（名前 '${name}'・${json}）は ${exp} のはずが ${cls:-結果なし}（${rest}）"; return
      fi
      [[ "$rest" == *" intact=yes" ]] || { verdict FAIL "$t" "${SYS_LABEL[$s]}: ケース ${idx} で一時 marketplace が変化した（${rest}）"; return; }
      if [ "$cls" != pass ] && ! grep -q "^MSG"$'\t'"${idx} ‼" "$VK_TMP/pm-$s"; then
        verdict FAIL "$t" "${SYS_LABEL[$s]}: ケース ${idx}（${cls}）で中止の文言（‼ の行）が無い"; return
      fi
      if [ -z "${SEEN[$idx]:-}" ]; then
        SEEN[$idx]=1
        case "$cls" in pass) npass=$((npass + 1));; mismatch) nmis=$((nmis + 1));; unreadable) nunr=$((nunr + 1));; nopython) nnopy=$((nnopy + 1));; esac
      fi
    done < "$VK_FIX/plugin-manifest.tsv"
  done
  # 両版で同じ中止になるケースは、文言（MSG）と終了コードが一致すること
  if [ "${#RUN[@]}" -eq 2 ]; then
    idx=0
    while IFS=$'\t' read -r eb ep py bom name json || [ -n "$eb" ]; do
      case "$eb" in ''|'#'*) continue;; esac
      idx=$((idx + 1))
      [ "$eb" = "$ep" ] || continue
      case "$eb" in pass|-) continue;; esac
      [ "${CLS[bash:$idx]:-}" = "$eb" ] && [ "${CLS[pwsh:$idx]:-}" = "$eb" ] || continue
      for s in bash pwsh; do
        grep "^MSG"$'\t'"${idx} " "$VK_TMP/pm-$s" > "$VK_TMP/pmm-$s"
        grep -m1 "^CASE"$'\t'"${idx} " "$VK_TMP/pm-$s" | sed -E 's/.* (rc=[^ ]*) .*/\1/' >> "$VK_TMP/pmm-$s"
      done
      if ! cmp -s "$VK_TMP/pmm-bash" "$VK_TMP/pmm-pwsh"; then
        set_diff "$VK_TMP/pmm-bash" "$VK_TMP/pmm-pwsh" "bash と pwsh 7 の差分（ケース ${idx}）:"
        fail_diff "$t" "ケース ${idx}（${eb}）の中止の文言か終了コードが bash / pwsh 7 で違う"; return
      fi
      ncmp=$((ncmp + 1))
    done < "$VK_FIX/plugin-manifest.tsv"
    cmpnote="・中止の文言と終了コードは bash / pwsh 7 で一致（${ncmp} ケース）"
  fi
  verdict PASS "$t" "実スクリプトのコピー（一時の開発リポ・remote の無い一時 marketplace・実物の git・claude はスタブ・stdin は空）で通過 ${npass}・不一致で中止 ${nmis}・読めずに中止 ${nunr}・python 無しで中止 ${nnopy}。$(labels "${RUN[@]}") とも期待どおり、中止は validate より前に exit 1・marketplace は無傷（commit も index への追加も無い）${cmpnote}${note:+（SKIP: ${note}）}（5.1 は #requires -Version 7 のため対象外）$(missing_note bash pwsh)"
}

item_pubargs(){
  local t="publish-plugin / publish-share 引数の検証（スタブ）" s c line idx exp rest cls bad nref=0 nmkt=0 nval=0 nbash=0 ncmp=0 cmpnote=""
  local -a S f
  mapfile -t S < <(usable bash pwsh)
  if [ "${#S[@]}" -eq 0 ]; then verdict SKIP "$t" "bash / pwsh 7 がどちらも無い"; return; fi
  if c="$(crashed_in "${S[@]}")"; then verdict FAIL "$t" "${SYS_LABEL[$c]} の probe が異常終了した"; return; fi
  if ! bad="$(vk_check_keys publish-args.tsv "plugin share" "対象（plugin / share）" 3)"; then verdict FAIL "$t" "$bad"; return; fi
  for s in "${S[@]}"; do
    getsec "$s" pubargs > "$VK_TMP/pa-$s"
    if ! grep -q $'^ASSERT\tok$' "$VK_TMP/pa-$s"; then
      verdict FAIL "$t" "${SYS_LABEL[$s]}: $(sed -n 's/^ASSERT\t//p' "$VK_TMP/pa-$s" | head -n 1)"; return
    fi
    idx=0
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue;; esac
      idx=$((idx + 1))
      IFS=$'\t' read -r -a f <<< "$line"
      [ "$s" = bash ] && exp="${f[1]}" || exp="${f[2]}"
      [ "$exp" = - ] && continue
      rest="$(grep -m1 "^CASE"$'\t'"${idx} " "$VK_TMP/pa-$s" | cut -f2-)"
      cls="$(printf '%s' "$rest" | cut -d' ' -f2)"
      if [ "$cls" != "$exp" ]; then verdict FAIL "$t" "${SYS_LABEL[$s]}: ケース ${idx}（${line}）は ${exp} のはずが ${cls:-結果なし}（${rest}）"; return; fi
      [[ "$rest" =~ stubcalls=0$ ]] || { verdict FAIL "$t" "${SYS_LABEL[$s]}: ケース ${idx} で中止より前に git / claude が呼ばれた（${rest}）"; return; }
      if [ "$s" = "${S[0]}" ]; then
        case "$exp" in ref) nref=$((nref + 1));; mkt) nmkt=$((nmkt + 1));; value) nval=$((nval + 1));; esac
        [ "${f[2]}" = - ] && nbash=$((nbash + 1))
      fi
    done < "$VK_FIX/publish-args.tsv"
  done
  # 両版で同じ期待のケースは、stderr の行（正規化済み）と終了コードが一致すること
  if [ "${#S[@]}" -eq 2 ]; then
    idx=0
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue;; esac
      idx=$((idx + 1))
      IFS=$'\t' read -r -a f <<< "$line"
      [ "${f[1]}" = "${f[2]}" ] && [ "${f[1]}" != - ] || continue
      for s in bash pwsh; do
        grep "^E"$'\t'"${idx} " "$VK_TMP/pa-$s" > "$VK_TMP/pam-$s"
        grep -m1 "^CASE"$'\t'"${idx} " "$VK_TMP/pa-$s" | sed -E 's/.* (rc=[^ ]*) .*/\1/' >> "$VK_TMP/pam-$s"
      done
      if ! cmp -s "$VK_TMP/pam-bash" "$VK_TMP/pam-pwsh"; then
        set_diff "$VK_TMP/pam-bash" "$VK_TMP/pam-pwsh" "bash と pwsh 7 の差分（ケース ${idx}）:"
        fail_diff "$t" "ケース ${idx}（${f[1]}）の中止の文言（stderr）か終了コードが bash / pwsh 7 で違う"; return
      fi
      ncmp=$((ncmp + 1))
    done < "$VK_FIX/publish-args.tsv"
    cmpnote="・stderr の文言と終了コードは bash / pwsh 7 で一致（${ncmp} ケース）"
  fi
  verdict PASS "$t" "実スクリプト（git / claude はスタブ）で必須の ref が空・省略 ${nref}・marketplace が空・省略 ${nmkt}（exit 2）・既定値のあるオプションに空 ${nval}（exit 1）。うち値の欠けた末尾のオプション ${nbash} は bash のみ（pwsh はバインドで拒否）。$(labels "${S[@]}") とも期待どおり、中止の文言は stderr のみ・git / claude 未呼び出し${cmpnote}（5.1 は #requires -Version 7 のため対象外）$(missing_note bash pwsh)"
}

LEFT_PATHS=(".claude/option-settings.sh" ".claude/option-settings.ps1" ".claude/custom.env"
            ".claude/launcher/option-settings.sh" ".claude/launcher/option-settings.ps1" ".claude/launcher/custom.env")
snapshot_left(){ local p; for p in "${LEFT_PATHS[@]}"; do [ -e "$VK_ROOT/$p" ] && printf '%s\n' "$p"; done; }

item_left(){
  local t="リポジトリ .claude/ に試験用ファイルを作っていない" p new=""
  snapshot_left > "$VK_TMP/left-after"
  while IFS= read -r p; do grep -qxF "$p" "$VK_TMP/left-before" || new+="${new:+ }$p"; done < "$VK_TMP/left-after"
  if [ -n "$new" ]; then verdict FAIL "$t" "実行中に作られた: $new"; return; fi
  if [ -s "$VK_TMP/left-before" ]; then
    verdict PASS "$t" "新規作成なし（実行前からある個人実体: $(tr '\n' ' ' < "$VK_TMP/left-before" | sed 's/ $//')）"
  else
    verdict PASS "$t" "新規作成なし"
  fi
}

compare_main(){
  local t0=$SECONDS s
  snapshot_left > "$VK_TMP/left-before"
  echo "[verify-kit] 対象: $VK_ROOT"
  run_probes
  local sys=""
  for s in "${SYS_ALL[@]}"; do
    case "${SYS_STATE[$s]}" in
      ok) sys+="${sys:+ / }${SYS_NAME[$s]} ${SYS_VER[$s]}";;
      *) sys+="${sys:+ / }${SYS_LABEL[$s]}（${SYS_WHY[$s]}）";;
    esac
  done
  echo "[verify-kit] 系統: $sys"
  item_syntax bash "構文 bash -n（.sh / .sh.template）"
  item_syntax pwsh "構文 pwsh 7 Parser（.ps1 / .ps1.template）"
  item_syntax ps51 "構文 Windows PowerShell 5.1 Parser（.ps1 / .ps1.template）"
  item_format
  item_version
  item_launcher
  item_launcher_stalerc
  item_optset
  item_setupenv
  item_internal_keys
  item_ca_root
  item_ca_fixture
  item_ca_links
  item_cleanenv
  item_cleanenv_badmode
  item_cleanenv_badshare
  item_pubname
  item_pubcase
  item_pubmanifest
  item_pubargs
  item_left
  if [ "$VERBOSE" -eq 1 ]; then
    for s in "${SYS_ALL[@]}"; do
      [ -f "$VK_TMP/log-$s.txt" ] || continue
      echo "  --- probe ログ（${SYS_LABEL[$s]}）---"; detail_file "$VK_TMP/log-$s.txt"
    done
  fi
  echo "[verify-kit] 集計: PASS ${NPASS} / FAIL ${NFAIL} / SKIP ${NSKIP}（所要 $((SECONDS - t0)) 秒）"
  [ "$NFAIL" -eq 0 ]
}

compare_main
