#!/usr/bin/env bash
# check-assets.sh — 配布する共有ペイロード <Share> を公開前に機械チェックする
#
# 個人ファイル・無視されうる設定キー・壊れた JSON が「配布されてしまう」状態かを自動判定する。
# 対話 TUI が必要な項目（trust 承認・/memory・/status の確認など）は対象外（手で確認）。
#
# 判定基準（README 隔離方式 / 案1 対応）― 検査対象の「層」で基準が変わる:
#   追跡基準（対象が git リポジトリのルート = 開発者の作業ツリー）:
#     - tracked            → FAIL（clone に含まれ参照側へ漏れる / payload に乗る）
#     - untracked で実在   → WARN（gitignore 済みで配布はされないが掃除推奨）
#     - 不在               → PASS
#   実体基準（対象が非 git = publish 時に取り出した payload の実体）:
#     - 実在               → FAIL（実際に配布される中身なので追跡状態は無関係）
#
# 名前の照合（2-c 成果物クラス・2-c' */evals/results/・3. の E 区分の env キー）は二段階で、照合と判定を分けている:
#   照合: まず完全一致（大文字小文字を区別）、一致しなければ ASCII（A〜Z）だけを小文字へ畳んだ同士で比べ、
#         「完全一致 / 大文字小文字だけ違う / 不一致」に分類する（下の name_class）。
#   判定: 完全一致は上の基準のまま。大文字小文字だけ違うものは、成果物（2-c / 2-c'）では実体基準（payload）で FAIL、
#         追跡基準（git）で WARN、env キー（3.）では層によらず WARN。区別する OS では正当な別物でありうるが、区別しない
#         Windows では .gitignore をすり抜けた成果物でありうる。publish-share は FAIL でしか止まらない（WARN は確認
#         プロンプトを経て公開まで進む）ため、配布する実体では止め、開発中の作業ツリーでは人の確認に回す。対応は各節の判定表。
#   ただし settings.json の同じオブジェクト内に完全一致または大文字小文字だけが違うキーが並ぶもの（systemroot と SystemRoot 等）は、
#   照合の前に重複キーとして層によらず FAIL（どちらの値が効くかが読み手で変わる。3. を参照）。
#
# 使い方:  ./check-assets.sh [--payload] <Share-path>
#   --payload  実体基準を強制する（publish-share から payload を検査する時に使う）
# 終了コード: FAIL が1件以上で 1、なければ 0（CI 利用可）。
set -uo pipefail

PAYLOAD=0
SHARE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --payload) PAYLOAD=1; shift;;
    -*) echo "‼ 不明な引数: $1（使い方: $0 [--payload] <Share-path>）" >&2; exit 2;;
    *) SHARE="$1"; shift;;
  esac
done
if [[ -z "$SHARE" || ! -d "$SHARE" ]]; then echo "使い方: $0 [--payload] <Share-path>" >&2; exit 2; fi
SHARE="$(cd "$SHARE" && pwd)"

fail=0
pass(){ echo "  [PASS] $1"; }
bad(){  echo "  [FAIL] $1"; fail=1; }
warn(){ echo "  [WARN] $1"; }

# 層の判定。
#
# ⚠ rev-parse --is-inside-work-tree を使ってはいけない。祖先方向に .git を探すため、
#    対象自身がリポジトリでなくても「どこかの repo 配下」なら真を返す。publish-share は
#    payload を mktemp -d へ展開して検査するので、TMPDIR が worktree 配下のマシン
#    （home を dotfiles リポジトリ化している等）では payload が追跡基準で検査され、
#    成果物の混入も統制ファイルの不在も FAIL から WARN へ退化する = ゲートの fail-open。
#    → 対象が「リポジトリのルートそのもの」の時だけ追跡基準を使う（--show-prefix が空）。
#    → publish-share からは --payload で実体基準を明示強制する（呼び出し側は層を知っている）。
IS_GIT=0
if [[ $PAYLOAD -eq 0 ]]; then
  if _prefix="$(git -C "$SHARE" rev-parse --show-prefix 2>/dev/null)" && [[ -z "$_prefix" ]]; then
    IS_GIT=1
  fi
fi

is_tracked(){ git -C "$SHARE" ls-files --error-unmatch "$1" >/dev/null 2>&1; }

# 個人ファイル（tracked=FAIL / untracked実在=WARN / 不在=PASS、非gitは実在=FAIL）を判定
check_personal(){
  local rel="$1" label="$2"
  if [[ $IS_GIT -eq 1 ]]; then
    if is_tracked "$rel"; then
      bad "$label が Git 追跡されている（clone に含まれ参照側へ漏れる）。git rm --cached して .gitignore へ"
    elif [[ -e "$SHARE/$rel" ]]; then
      warn "$label が実在するが未追跡（配布はされない。掃除推奨）"
    else
      pass "$label なし"
    fi
  else
    if [[ -e "$SHARE/$rel" ]]; then
      bad "$label がある（非 git のためコピー展開でそのまま配布される）。削除する"
    else
      pass "$label なし"
    fi
  fi
}

echo "[check-assets] 対象: $SHARE（$([[ $IS_GIT -eq 1 ]] && echo 'リポジトリのルート: 追跡基準' || echo 'payload / 非リポジトリ: 実体基準')）"

# 1. 個人ファイル CLAUDE.local.md（--add-dir+env で参照側へ漏れる）
check_personal "CLAUDE.local.md"        "CLAUDE.local.md"
check_personal ".claude/CLAUDE.local.md" ".claude/CLAUDE.local.md"

# 2. settings.local.json（個人・非共有。共有設定は settings.json へ）
check_personal ".claude/settings.local.json" ".claude/settings.local.json"

# 2-b. ランチャーの個人実体（テンプレから利用者が作る。配布してはならない）
check_personal ".claude/custom.env"          ".claude/custom.env"
check_personal ".claude/option-settings.sh"  ".claude/option-settings.sh"
check_personal ".claude/option-settings.ps1" ".claude/option-settings.ps1"

# 2-c. セッション成果物・作業一時物の混入（内部レポートの公開リポ流出を止める最後の砦）
#      判定は個人ファイル（check_personal）と同じ二層基準:
#        - 非 git（= publish 時に取り出した payload 実体）→ 実在＝FAIL。
#          実際に配布される中身なので、追跡状態は無関係。「追跡解除したから大丈夫」は
#          publish する ref を取り違えた瞬間に崩れるため、実体で検査する。
#        - git リポジトリ（= 開発者が作業ツリーに対して手動で回す場合）→ 追跡されていれば FAIL。
#          gitignore 済みで実在するだけなら WARN（payload には乗らないため）。
#          ここを実体基準にすると、work/ を持つ通常の開発マシンで常時 FAIL し、
#          「いつもの誤検知」として無視される habit を生む（ゲートの信号価値が死ぬ）。
#      名前は二段階で照合し（下の「名前の照合」）、大文字小文字だけが違うものは payload で FAIL、git で WARN にする（判定表）。
#
# ---- 名前の照合（チェックロジック）。分類を返すだけで、判定（PASS / WARN / FAIL と文言）は各節の判定表に置く ----
#   1) 完全一致（大文字小文字を区別）  2) 一致しなければ ASCII（A〜Z）だけを小文字へ畳んだ同士で比べる
#   → exact（完全一致）/ case（大文字小文字だけが違う）/ none（不一致）
# ⚠ 存在検査（[[ -e .claude/reports ]]）で照合しない。Windows ではそれ自体が大文字小文字を無視して真になり、
#    区別する OS とで判定が割れる。エントリ名・追跡パスを列挙して文字列で比べる（publish-plugin の
#    大文字小文字違い検査と同じ方式）。
# ⚠ 畳むのは A〜Z だけ（LC_ALL=C の tr）。${x,,} や PS の ToLowerInvariant() は非 ASCII も畳む（K と KELVIN SIGN 等）
#    ため両版の結果が割れる。PS 版の Fold-Ascii と同じ。1 件ずつ $(...) で畳むと Windows では fork が遅いので、
#    候補は NUL 区切りの一覧のまま 1 回で畳み、分類は NC で返す（サブシェルを立てない）。
fold_z(){ LC_ALL=C tr 'A-Z' 'a-z'; }
name_class(){ # $1=実際の名前 $2=その畳み $3=期待する名前 $4=その畳み → NC=exact / case / none
  if [[ "$1" == "$3" ]]; then NC=exact
  elif [[ "$2" == "$4" ]]; then NC=case
  else NC=none; fi
}
# コマンド "$@" が出す NUL 区切りの一覧を CAND へ、その畳みを CANDF へ読む（添字で対応する）
load_cands(){
  local x
  CAND=(); CANDF=()
  while IFS= read -r -d '' x; do CAND+=("$x"); done < <("$@")
  [[ ${#CAND[@]} -gt 0 ]] || return 0
  while IFS= read -r -d '' x; do CANDF+=("$x"); done < <(printf '%s\0' "${CAND[@]}" | fold_z)
}
# CAND の各要素を期待する名前 $1（畳み $2）と照合し、exact の要素を M_EXACT へ、case の要素を M_CASE へ入れる
match_cands(){
  local i
  M_EXACT=(); M_CASE=()
  for (( i = 0; i < ${#CAND[@]}; i++ )); do
    name_class "${CAND[i]}" "${CANDF[i]}" "$1" "$2"
    case "$NC" in exact) M_EXACT+=("${CAND[i]}");; case) M_CASE+=("${CAND[i]}");; esac
  done
}
tracked_claude(){ git -C "$SHARE" ls-files -z -- .claude 2>/dev/null; }
# 2-c の候補（.claude/<直下の名前>）。追跡: 追跡パスの最初の要素（重複なし・git の順）／実在: 直下のエントリ（バイト順）
tracked_tops(){
  local p t seen=$'\n'
  while IFS= read -r -d '' p; do
    t="${p#.claude/}"; t=".claude/${t%%/*}"
    case "$seen" in *$'\n'"$t"$'\n'*) continue;; esac
    seen+="$t"$'\n'; printf '%s\0' "$t"
  done < <(tracked_claude)
}
disk_tops(){
  local e
  [[ -d "$SHARE/.claude" ]] || return 0
  while IFS= read -r -d '' e; do printf '.claude/%s\0' "${e##*/}"; done \
    < <(find "$SHARE/.claude" -mindepth 1 -maxdepth 1 -print0 2>/dev/null) | LC_ALL=C sort -z
}
_LAYER=payload; [[ $IS_GIT -eq 1 ]] && _LAYER=git

# 大文字小文字だけが違うパスの判定（2-c / 2-c' の判定表が共有する文言）。$1=層:出どころ $2=実際のパス $3=クラス
#   payload は FAIL（publish-share は FAIL でしか止まらないので、WARN では公開まで進む）、git は WARN（開発中の確認用）。
verdict_case(){
  local same="（$3 と同一視される OS がある。"
  case "$1" in
    git:tracked) warn "大文字小文字だけが違う成果物クラスらしきパスが Git 追跡されている（payload に乗る）: $2${same}意図したものか確認すること）";;
    git:disk)    warn "大文字小文字だけが違う成果物クラスらしきパスが実在する（未追跡。配布はされない）: $2${same}意図したものか確認すること）";;
    *)           bad  "大文字小文字だけが違う成果物クラスらしきパスが配布ペイロードに含まれている: $2${same}公開前に名前を直すか除外すること）";;
  esac
}
# 2-c の判定表（照合の分類 → 判定）。1 クラスにつき判定は 1 つで、上の行ほど優先する（呼び出し側が選ぶ）:
#   層:出どころ:分類          判定
#   git:tracked:exact         FAIL  Git 追跡されている（payload に乗る）
#   git:tracked:case          WARN  大文字小文字だけが違うパスが Git 追跡されている（パスごとに 1 行）
#   git:disk:exact            WARN  実在するが未追跡（配布はされない）
#   git:disk:case             WARN  大文字小文字だけが違うパスが実在する（未追跡）
#   payload:disk:exact        FAIL  配布ペイロードに含まれている
#   payload:disk:case         FAIL  大文字小文字だけが違うパスが配布ペイロードに含まれている（パスごとに 1 行）
#   none                      PASS  なし
verdict_artifact(){ # $1=層:出どころ:分類 $2=クラス 残り=case で一致した実際のパス
  local key="$1" cls="$2" p; shift 2
  case "$key" in
    git:tracked:exact)  bad "$cls が Git 追跡されている（payload に乗り配布される）。git rm --cached して .gitignore へ";;
    git:disk:exact)     warn "$cls が実在するが未追跡（配布はされない。掃除推奨）";;
    payload:disk:exact) bad "$cls が配布ペイロードに含まれている（内部成果物は配布しない）。grooming 済みの ref を publish すること";;
    *:case)             for p in "$@"; do verdict_case "${key%:case}" "$p" "$cls"; done;;
    *)                  pass "$cls なし";;
  esac
}

# 成果物クラスの正本リストは本配列。root/.claude 双方の .gitignore はこれに追随させること。
# 位置が固定でないクラス（evals/results/）は直後の 2-c' が正本。
#   .claude/worktrees            … --worktree / EnterWorktree が作る git worktree（公式も .gitignore を推奨）
#   .claude/scheduled_tasks.json … 永続化したスケジュールタスク（作成したフォルダでしか動かない個人状態）
_ARTIFACTS=(".claude/reports" ".claude/work" ".claude/workspace" ".claude/plans"
            ".claude/agent-memory-local" ".claude/work_instructions.txt"
            ".claude/.bat-shadow" ".claude/worktrees" ".claude/scheduled_tasks.json")
load_cands printf '%s\0' "${_ARTIFACTS[@]}"; _ART=("${CAND[@]}"); _ARTF=("${CANDF[@]}")
_TOP=(); _TOPF=()
if [[ $IS_GIT -eq 1 ]]; then load_cands tracked_tops; _TOP=(${CAND[@]+"${CAND[@]}"}); _TOPF=(${CANDF[@]+"${CANDF[@]}"}); fi
load_cands disk_tops; _DISK=(${CAND[@]+"${CAND[@]}"}); _DISKF=(${CANDF[@]+"${CANDF[@]}"})
for (( _i = 0; _i < ${#_ART[@]}; _i++ )); do
  _key=none; _hits=()
  if [[ $IS_GIT -eq 1 ]]; then
    CAND=(${_TOP[@]+"${_TOP[@]}"}); CANDF=(${_TOPF[@]+"${_TOPF[@]}"})
    match_cands "${_ART[_i]}" "${_ARTF[_i]}"
    if [[ ${#M_EXACT[@]} -gt 0 ]]; then _key=git:tracked:exact
    elif [[ ${#M_CASE[@]} -gt 0 ]]; then _key=git:tracked:case; _hits=("${M_CASE[@]}"); fi
  fi
  if [[ $_key == none ]]; then
    CAND=(${_DISK[@]+"${_DISK[@]}"}); CANDF=(${_DISKF[@]+"${_DISKF[@]}"})
    match_cands "${_ART[_i]}" "${_ARTF[_i]}"
    if [[ ${#M_EXACT[@]} -gt 0 ]]; then _key=$_LAYER:disk:exact
    elif [[ ${#M_CASE[@]} -gt 0 ]]; then _key=$_LAYER:disk:case; _hits=("${M_CASE[@]}"); fi
  fi
  verdict_artifact "$_key" "${_ART[_i]}" ${_hits[@]+"${_hits[@]}"}
done

# 2-c'. 置き場所が固定でない成果物クラス: claude plugin eval の結果（評価した plugin / skill の evals/results/。v2.1.269〜）
#       追跡パス（git 層）と .claude 配下のディレクトリ（両層）を列挙し、evals/results の 2 要素を二段階で照合する。
#       追跡パスはファイル名を除いたディレクトリ部分のどこか（旧 pathspec ':(glob).claude/**/evals/results/**' と同じ範囲）、
#       ディレクトリは末尾の 2 要素（旧 find -path '*/evals/results' と同じ）を見る。
#       ⚠ .claude/worktrees（丸ごとの git チェックアウト。2-c で別途判定する）には降りない。名前は A〜Z だけ畳んだ一致で
#          除外する（Worktrees / WORKTREES も降りない。2-c がそれを大文字小文字だけが違う成果物クラスとして報告する）。
#          降りると遅いうえ、worktree 内の evals/results を payload の成果物と誤って数える。-ipath は使わない（UTF-8 の
#          ロケールでは非 ASCII も畳みうる。KELVIN SIGN 等）。A〜Z の各文字を [Ww] の形で書いて畳む（PS 版の Fold-Ascii と同じ）。
#       ⚠ シンボリックリンクは辿らず、…/results のディレクトリとしても数えない。find -P（既定。-P を明示している）は
#          リンクを辿らず、-type d はリンク自体も含めない。Git Bash の find はジャンクションも symlink として扱う（実測）。
#          PS 版の Get-ClaudeTree と同じ（LinkType が Junction / SymbolicLink のものだけをリンクとし、OneDrive の
#          プレースホルダ等ほかの再解析ポイントは通常のディレクトリとして降りる。find も降りる。実測）。
_EVR="evals/results"; _EVR_CLS='*/evals/results/'
# $1=パス $2=その畳み $3=file（ディレクトリ部分のどこか）/ dir（末尾の 2 要素）→ NC=分類、NC_DIR=一致した …/results まで
evr_class(){
  local IFS=/ n i lo best=none dir=""
  local -a p f
  read -r -a p <<< "$1"; read -r -a f <<< "$2"
  n=${#p[@]}
  if [[ "$3" == dir ]]; then lo=$((n - 2)); else lo=1; n=$((n - 1)); fi
  [[ $lo -lt 1 ]] && lo=1                        # p[0] は .claude
  for (( i = lo; i + 1 < n; i++ )); do
    name_class "${p[i]}/${p[i+1]}" "${f[i]}/${f[i+1]}" "$_EVR" "$_EVR"
    if [[ $NC == exact ]]; then best=exact; dir="${p[*]:0:i+2}"; break; fi
    if [[ $NC == case && $best == none ]]; then best=case; dir="${p[*]:0:i+2}"; fi
  done
  NC=$best; NC_DIR=$dir
}
# -iname は候補を絞るだけ（作業ツリーの .claude/work 等は数千ディレクトリになり、全件を照合すると遅い）。
# ASCII の大文字小文字を畳む一致は必ず含むので取りこぼさず、分類はこのあと evr_class が行う（PS 版の -like と同じ役割）。
evr_dirs(){
  [[ -d "$SHARE/.claude" ]] || return 0
  ( cd "$SHARE" && find -P .claude -path '.claude/[Ww][Oo][Rr][Kk][Tt][Rr][Ee][Ee][Ss]' -prune -o -type d -iname results -print0 2>/dev/null ) \
    | LC_ALL=C sort -z
}
# 2-c' の判定表（照合の分類 → 判定）。2-c と同じ優先順位で判定は 1 つ。列挙は序数（バイト）順の先頭 5 件まで（git 層は
# ls-files の順 = パスのバイト順、実在は / 区切りのまま LC_ALL=C sort。PS 版の git の順 / Sort-Ordinal と同じ順になる）:
#   git:tracked:exact    FAIL  Git 追跡されている（追跡ファイルを列挙）
#   git:tracked:case     WARN  大文字小文字だけが違うパスが Git 追跡されている（…/results のディレクトリごとに 1 行）
#   git:disk:exact       WARN  実在するが未追跡
#   git:disk:case        WARN  大文字小文字だけが違うパスが実在する（未追跡）
#   payload:disk:exact   FAIL  配布ペイロードに含まれている（ディレクトリを列挙）
#   payload:disk:case    FAIL  大文字小文字だけが違うパスが配布ペイロードに含まれている（…/results のディレクトリごとに 1 行）
#   none                 PASS  なし
verdict_evr(){ # $1=層:出どころ:分類 残り=列挙するパス
  local key="$1" p; shift
  case "$key" in
    git:tracked:exact)
      bad "plugin eval の結果（*/evals/results/）が Git 追跡されている（payload に乗り配布される）。git rm -r --cached して .gitignore へ:"
      for p in "$@"; do echo "         $p"; done;;
    git:disk:exact) warn "plugin eval の結果（*/evals/results/）が実在するが未追跡（配布はされない。掃除推奨）";;
    payload:disk:exact)
      bad "plugin eval の結果（*/evals/results/）が配布ペイロードに含まれている:"
      for p in "$@"; do echo "         $p"; done;;
    *:case) for p in "$@"; do verdict_case "${key%:case}" "$p" "$_EVR_CLS"; done;;
    *) pass "plugin eval の結果（*/evals/results/）なし";;
  esac
}
_key=none; _hits=()
if [[ $IS_GIT -eq 1 ]]; then
  load_cands tracked_claude
  _ex=(); _cs=()
  for (( _i = 0; _i < ${#CAND[@]}; _i++ )); do
    evr_class "${CAND[_i]}" "${CANDF[_i]}" file
    case "$NC" in
      exact) _ex+=("${CAND[_i]}");;
      case) [[ ${#_cs[@]} -gt 0 && "${_cs[${#_cs[@]}-1]}" == "$NC_DIR" ]] || _cs+=("$NC_DIR");;   # git の順なので同じディレクトリは隣接する
    esac
  done
  if [[ ${#_ex[@]} -gt 0 ]]; then _key=git:tracked:exact; _hits=("${_ex[@]:0:5}")
  elif [[ ${#_cs[@]} -gt 0 ]]; then _key=git:tracked:case; _hits=("${_cs[@]:0:5}"); fi
fi
if [[ $_key == none ]]; then
  load_cands evr_dirs
  _ex=(); _cs=()
  for (( _i = 0; _i < ${#CAND[@]}; _i++ )); do
    evr_class "${CAND[_i]}" "${CANDF[_i]}" dir
    case "$NC" in exact) _ex+=("${CAND[_i]}");; case) _cs+=("${CAND[_i]}");; esac
  done
  if [[ ${#_ex[@]} -gt 0 ]]; then _key=$_LAYER:disk:exact; _hits=("${_ex[@]:0:5}")
  elif [[ ${#_cs[@]} -gt 0 ]]; then _key=$_LAYER:disk:case; _hits=("${_cs[@]:0:5}"); fi
fi
verdict_evr "$_key" ${_hits[@]+"${_hits[@]}"}

# 2-d. 配布先の統制ファイル（payload に無いと配布先から「消える」クラス）
#      publish-share のミラーは payload に無いものを削除するため、これらを欠いた ref を
#      publish すると配布先の除外設定・改行保護が黙って失われる（CR-1 の逆行）。
#      判定は 2-c と同じ二層基準（非 git = 実際に publish する payload → 不在は FAIL。
#      git = 開発中の作業ツリー → 不在は WARN。開発途中で未マージなだけのことがあるため）。
for _guard in ".claude/.gitignore" ".claude/.gitattributes"; do
  if [[ -f "$SHARE/$_guard" ]]; then
    pass "$_guard あり（配布先の統制ファイル）"
  elif [[ $IS_GIT -eq 1 ]]; then
    warn "$_guard が無い（publish 前に必要。この状態のまま publish すると配布先の除外設定・改行保護が失われる）"
  else
    bad "$_guard が payload に無い。このまま publish すると配布先の除外設定・改行保護が失われる"
  fi
done

# 「実際に配布されるファイル」の列挙。2-e / 2-f はこれを走査する。
#
# ⚠ 二層基準をここにも適用すること。作業ツリーに対して単純に find を回すと、gitignored で
#    payload には乗らない .claude/work/ 等まで検査対象になり、通常の開発マシンで常時 FAIL する
#    （IM-2 でゲートのオオカミ少年化として指摘された故障をそのまま再発させる）。
#      - git 層（リポジトリのルート）→ 追跡されているファイルだけが payload に乗る
#      - 非 git 層（取り出した payload の実体）→ そこにあるものが全て配布される
#    非 git 層の find -P -type f はシンボリックリンク（Git Bash ではジャンクションも）を辿らず数えない（PS 版の Get-ClaudeTree と同じ）。
#    隠し属性のファイルも数える（find は属性を見ない。PS 版も隠し属性・システム属性を含めて列挙する）。
# ⚠ 並びは序数（バイト順）にそろえる（2-e / 2-f の一覧の順。PS 版と同じ）。find の順は readdir の順・深さ優先で、PS の
#    列挙（ディレクトリごとにファイルが先）と割れる（実測）。git 層の ls-files は index の順 = パスのバイト順なので並べ直さない
#    （PS 版も同じ出力をそのまま使う）。区切りは / のまま並べる（\ は数字・英大文字より後ろに来るので順が変わる）。
payload_files() {
  if [[ $IS_GIT -eq 1 ]]; then
    git -C "$SHARE" ls-files -z -- .claude
  else
    ( cd "$SHARE" && find -P .claude -type f -print0 2>/dev/null ) | LC_ALL=C sort -z
  fi
}

# 2-e. 配布物の本文に「環境固有の絶対パス」が埋まっていないか。
#      payload は公開リポへ配る。開発者マシンのディレクトリ構成が載ると、(1) ローカルの FS
#      レイアウトを公開してしまい、(2) 利用者のマシンには存在しないパスを指示することになる。
#      （実例: skill が `C:\workspace\...\claude-plugins-official\plugins\` を参照していた）
#      説明用の例示を弾ききれないので WARN 止まり（人間が判断する）。
_abs_re='(^|[^A-Za-z])[A-Za-z]:\\[A-Za-z]|(^|[^A-Za-z])/home/[a-z][a-z0-9_-]*/|/Users/[a-z][a-z0-9_-]*/'
# 製品が規定する公式パス（managed-settings.json の配置先、Git for Windows の既定）は環境固有ではないので除く。
# 行から公式パスの部分文字列だけを取り除き、残りを絶対パスのパターンで判定する（行ごと除外すると、同じ行にある
# 開発者固有パスを見逃す。ファイル単位ならなおさら）。PS 版と同じ表・同じ判定（大文字小文字を区別する）にすること。
# ⚠ grep -q で受けない。pipefail の下では後段の -q が先に終わると前段の grep が SIGPIPE（141）で落ち、
#    パイプライン全体が偽になってヒットが失われる（実測: 該当行が 20000 行のファイルで毎回見逃した）。件数で受ける。
# バイナリは対象外にする。判定は PS 版の Test-BinaryHead と同じ明示的な規則: 先頭 8000 バイトに NUL があればバイナリ
# （8000 は git が text=auto / diff でバイナリと見なす窓と同じ。UTF-16 のテキストも NUL を含むのでバイナリ扱い）。
#   ⚠ grep -I に頼らない。何をバイナリと見なすか（NUL を探す範囲・符号化の誤りの扱い）が grep の版とロケールに依存し、
#      PS 版と割れる。テキストと判定したものは grep -a で必ずテキストとして読む。
#   ⚠ NUL を grep で数えない（引数に NUL を渡せない）。tr で NUL だけを残して wc -c でバイト数を数える。
#   ⚠ grep / sed は LC_ALL=C で走らせる。パターンは ASCII だけなので UTF-8 の本文には同じ結果になり、UTF-8 として不正な
#      バイト（CP932 等）も 1 バイト = 1 文字として扱える（PS 版は U+FFFD に置き換えて読む。どちらも [^A-Za-z] に一致する）。
#      [a-z] 等の範囲もロケールの照合順でなくバイト値になる（PS 版の .NET 正規表現と同じ）。
_BIN_HEAD=8000
is_binary(){ local n; n="$(head -c "$_BIN_HEAD" -- "$1" 2>/dev/null | LC_ALL=C tr -cd '\000' | wc -c)"; [[ $((n)) -gt 0 ]]; }
_abs_allow='[A-Za-z]:\\Program Files( \(x86\))?\\(ClaudeCode|Git)\\'
_abs_hits=""
while IFS= read -r -d '' _f; do
  case "$_f" in */skills/win-file-encoding/*) continue ;; esac   # 変換 skill は CP932 パスが題材
  is_binary "$SHARE/$_f" && continue
  _n="$(LC_ALL=C grep -aE "$_abs_re" "$SHARE/$_f" 2>/dev/null | LC_ALL=C sed -E "s#${_abs_allow}##g" | LC_ALL=C grep -acE "$_abs_re")"
  if [[ "${_n:-0}" -gt 0 ]]; then _abs_hits+="${_f}"$'\n'; fi
done < <(payload_files)
if [[ -n "$_abs_hits" ]]; then
  warn "配布物に環境固有の絶対パスらしき記述がある（公開前に確認すること）:"
  while IFS= read -r _f; do [[ -n "$_f" ]] && echo "         $_f"; done <<< "$_abs_hits"
else
  pass "配布物に環境固有の絶対パスなし"
fi

# 2-f. 配布される .ps1 が UTF-8 BOM を保持しているか。
#      BOM が無いと Windows PowerShell 5.1 が CP932 と誤読し、日本語コメント・メッセージが化ける
#      （後続バイトが引用符を食えば構文エラーにもなる）。.gitattributes は改行しか守れず、
#      BOM は「中身」なので一度落ちると復元されない。実際に BOM を除去する経路が存在する
#      （win-file-encoding skill の convert_encoding.py --to-win）ため、機構でも検出する。
_ps1_nobom=0
while IFS= read -r -d '' _f; do
  case "$_f" in *.ps1|*.ps1.template) ;; *) continue ;; esac
  if [[ "$(head -c 3 "$SHARE/$_f" | od -An -tx1 | tr -d ' ')" != "efbbbf" ]]; then
    bad "$_f に UTF-8 BOM が無い（Windows PowerShell 5.1 で日本語が化ける）"
    _ps1_nobom=1
  fi
done < <(payload_files)
[[ $_ps1_nobom -eq 0 ]] && pass "配布される .ps1 は全て BOM 付き"

# 2-g. 配布される rules と共通 CLAUDE.md の大きさ。対象は .claude/rules/ 配下の *.md（サブディレクトリを含む）と .claude/CLAUDE.md に固定する。
#      判定は 2 段で、1 ファイルにつき 1 行（両方に当たるものは FAIL だけを出し、WARN と二重に出さない）。ちょうどは PASS:
#        - 32,000 文字超 → FAIL（publish-share は FAIL で公開を中止する）。on demand で読まれるファイル（paths: 付きの rules 等）は
#          1 ファイルの上限を超えた分が読まれない（v2.1.309〜。200K コンテキストで 40,000 文字、1M で 150,000〜200,000 文字。
#          memory「Claude ignores the end of my subdirectory CLAUDE.md」）。32,000 は最も厳しい 40,000 の 8 割。本リポの文体（日本語で
#          1 行 40〜60 文字）では 600〜700 行に当たり、下の 200 行の目安もほぼ確実に大きく超えているので、WARN でなく FAIL にする
#          （2026-10-27 の作業指示者の判断）。
#        - 200 行超 → WARN。docs の CLAUDE.md の目安（memory「target under 200 lines per CLAUDE.md file. Longer files consume more
#          context and reduce adherence」）。rules 固有の目安は docs に無いので、rules にも同じ目安を当てる（起動時の長さの警告でも
#          rules は 1 ファイルとして数えられる）。
#      ⚠ 対象を広げない: skills の SKILL.md・agents・その他の .md は見ない（docs/・README はそもそも payload の外）。rules は
#         サブディレクトリの .md も Claude Code が rules として読む（memory「All .md files are discovered recursively」）ので深さによらず
#         数える（case の * は / にも一致するので、.claude/rules/*.md がそのまま再帰の範囲になる）。ただし . で始まるディレクトリ
#         （.claude/rules/.x/… や .claude/rules/a/.x/…。作業用の退避・VCS のメタデータ等）の中には入らない（PS 版と同じ名前の規則。
#         隠し属性は見ない）。. で始まるファイル名そのものは数える。
#      列挙は payload_files（2-e / 2-f と同じ二層基準・序数順。git 層は追跡ファイルだけ、payload 層はリンクを辿らない実体だけ。
#      .claude/CLAUDE.md は .claude/rules/… より前に来る）。
#      ⚠ 数え方は PS 版と同じバイト単位の規則にする（どちらもデコードしない）:
#        文字数 = UTF-8 の継続バイト（0x80〜0xBF）以外のバイト数。正しい UTF-8 ではコードポイント数（Linux の UTF-8 ロケールでの
#                 wc -m）に一致する。先頭の UTF-8 BOM（EF BB BF）は 1 文字分を引いて数えない。改行（LF・CR）も 1 文字。
#        行数   = LF のバイト数。最後の行が LF で終わらなければ 1 行足す（空のファイルは 0 行）。
#        wc -m に頼らない（ロケールが UTF-8 でないとバイト数を返す。Git Bash では UTF-8 のロケールでも UTF-16 の code unit を数えて
#        絵文字を 2 と数え、BOM も 1 文字と数える。実測）。python も使わない（無い環境でも検査する）。PS 版の文字列の .Length も
#        UTF-16 の code unit 数なので使わない。
# ⚠ しきい値を変えたら FAIL / WARN / PASS の文言（200 行・32,000 文字）と PS 版の $ruleMaxLines / $ruleMaxChars も同時に直す。
_RULE_MAX_LINES=200; _RULE_MAX_CHARS=32000
_rule_n=0; _rule_hit=0
while IFS= read -r -d '' _f; do
  case "$_f" in
    .claude/CLAUDE.md) ;;
    .claude/rules/.*/*|.claude/rules/*/.*/*) continue ;;   # . で始まるディレクトリの中（直下・それより深い所）
    .claude/rules/*.md) ;;
    *) continue ;;
  esac
  [[ -f "$SHARE/$_f" ]] || continue   # 実体が無いもの（列挙と作業ツリーのずれ）は従来どおり対象にしない（PS 版の Test-Path と同じ）
  # 読めないファイル（-r が偽・開けない・途中で読めない。ロック・権限・I/O エラー）は件数に足さず、ファイルごとに「未検査」の
  # WARN を 1 行出す（2026-10-27 の判断 J-4。黙って飛ばすと、検査して PASS したのか未検査なのか区別できない。settings の
  # 「キー検査に失敗した（未検査）」と同じ扱い）。FAIL にはしない（一時的なロックで publish を止めない）。他のファイルが基準内なら
  # 下の PASS 行は読めたファイルの件数で別に出す。PS 版の ReadAllBytes の try / catch → Warn と同じ文言（例外の文言は出さない。
  # bash 版では取れないので両版で割れる）。pipefail なので tr の失敗が終了コードに出る。2>/dev/null は < より前に置く
  if [[ ! -r "$SHARE/$_f" ]] \
     || ! _rchars="$(LC_ALL=C tr -d '\200-\277' 2>/dev/null < "$SHARE/$_f" | wc -c)" \
     || ! _rlines="$(LC_ALL=C tr -cd '\n' 2>/dev/null < "$SHARE/$_f" | wc -c)"; then
    warn "rules / CLAUDE.md の大きさ: $_f は読み取りに失敗したため未検査（ロックや読み取り権限を確かめて再実行する）"
    continue
  fi
  _rule_n=$((_rule_n + 1))
  _rchars=$((_rchars)); _rlines=$((_rlines))
  [[ "$(head -c 3 "$SHARE/$_f" | od -An -tx1 | tr -d ' \n')" == "efbbbf" ]] && _rchars=$((_rchars - 1))
  _rlast="$(tail -c 1 "$SHARE/$_f" | LC_ALL=C tr -d '\n' | wc -c)"
  [[ $((_rlast)) -gt 0 ]] && _rlines=$((_rlines + 1))
  if [[ $_rchars -gt $_RULE_MAX_CHARS ]]; then
    bad "rules / CLAUDE.md の大きさ: $_f は ${_rchars} 文字（32,000 文字超）。on demand で読まれるファイルは 200K コンテキストで 40,000 文字を超えた分が読まれず（v2.1.309〜）、docs の目安（1 ファイル 200 行未満）も大きく超える。分割する（FAIL なので publish-share は公開を中止する）"
    _rule_hit=1
  elif [[ $_rlines -gt $_RULE_MAX_LINES ]]; then
    warn "rules / CLAUDE.md の大きさ: $_f は ${_rlines} 行（200 行超）。docs の目安は 1 ファイル 200 行未満（超えるとコンテキストを消費し遵守率が下がる）。分割を検討する"
    _rule_hit=1
  fi
done < <(payload_files)
[[ $_rule_hit -eq 0 ]] && pass "rules / CLAUDE.md の大きさ（200 行・32,000 文字以内）: ${_rule_n} ファイル"

# 3. settings.json の JSON 構文 ＋ project（.claude/settings.json）では効かないキーの検出
#    根拠: settings-reference の Scope 欄。`Any file` 以外のキーは共有 project ファイルからは適用されない。
#    「直し方」が違うので区分を分けて報告する:
#      U = user / local / managed / --settings でのみ有効。方法 A（.claude/ を project として配置）では
#          無視されるが、方法 B と clean-test-env（--settings で結合）では有効になる＝配布方式で挙動が割れる。
#      M = managed 専用。project でも --settings でも無視される（組織の managed settings で配る）。
#      E = env ブロックのうち project / local からは設定できない変数（テレメトリの off 値だけは例外的に効く）。
#          キー名は 2-c と同じ二段階で照合する（_ENV_RE に完全一致 → A〜Z だけ畳んだ同士で一致）。判定は、
#          完全一致 → 従来の WARN、大文字小文字だけ違う（systemroot 等）→ 「Windows でのみ同一視される」旨の別の WARN。
#          環境変数名の大文字小文字を区別しないのは Windows だけなので、区別する OS では別の変数でありうる。
#          どの settings ファイルからも読まれず起動環境からしか読まれない変数（CLAUDE_CODE_RESTRICTED 等）も E に含める
#          （settings-reference「Variables Claude Code ignores in `env`」の各項目。v2.1.310 の docs で照合）。
#    加えて、どこに置いても照合されない権限ルール（permissions.allow / deny / ask のうち、パス付きの Write / NotebookEdit /
#    MultiEdit / Glob。ファイルの権限は Edit(path) / Read(path) ルールだけで照合される。permissions「`Write(path)`,
#    `NotebookEdit(path)`, and `Glob(path)` rules never match」）を別の WARN で報告する。ツール名だけのルール（Write 等）は
#    ツール単位で効くので対象外。hooks の if 条件（"Write(...)" 等）は権限ルールではないので見ない。Claude Code 自身も
#    起動時に警告するが、v2.1.305 以降の対話セッションではバナー下の行とデバッグログにしか出ない（allow ルールは行も出ない）。
#    ⚠ 判定はキーパス（a.b.c）で行い、PS 版と同じ表・同じ意味に揃えること（raw grep は
#       sandbox.filesystem.disabled の "disabled" のような汎用名を区別できない）。
#    ⚠ 表を更新したら PS 版の $uKeys / $mKeys / $envRe / $wRuleRe も同時に更新する。
#    同じオブジェクト内のキーの重複（完全一致、または A〜Z だけ畳んで一致 = 大文字小文字だけの違い。env 以外の階層も同じ）は
#    専用メッセージで FAIL にし、キーの検査には進まない。どの値が効くかは読み手で変わり（python / PowerShell 7 / 5.1 は
#    完全一致の重複を黙って後勝ちで受理し、PowerShell は大文字小文字だけの違いを拒否する。実測）、Windows の環境変数名は
#    大文字小文字を区別しない。判定の順は BOM → JSON 構文 → 重複キー → キーの検査（PS 版と同じ）。構文が先なので、
#    壊れた JSON は重複があっても「不正な JSON」になる（PS 版は ConvertFrom-Json が構文を通したかで同じ順にしている）。
# axScreenReader は v2.1.305 から User or managed（--settings も可。それまでは Any file）。sandbox.allowNestedUserNamespaces は
# v2.1.305 で新設（User or managed。--settings も可。true にするとサンドボックスの境界を外す）
_U_KEYS=(skipDangerousModePermissionPrompt useAutoModeDuringPlan autoMode skipAutoPermissionPrompt
         processWrapper pluginConfigs syncClaudeAiSkills syncClaudeAiPlugins axScreenReader
         sandbox.allowAppleEvents sandbox.allowNestedUserNamespaces sandbox.ripgrep sandbox.filesystem.disabled
         sandbox.network.strictAllowlist sandbox.network.tlsTerminate
         sandbox.credentials.allowPlaintextInject sandbox.credentials.awsPairs sandbox.credentials.sigv4)
# prependPlugins / appendPlugins は Scope 表記こそ User or managed だが --settings でも無視されるので M に置く
_M_KEYS=(prependPlugins appendPlugins
         allowManagedPermissionRulesOnly allowManagedHooksOnly allowManagedMcpServersOnly managedMcpServers
         strictKnownMarketplaces allowedMarketplaces blockedMarketplaces strictPluginOnlyCustomization
         disableSideloadFlags disableCommandPluginSources claudeMd policyHelper allowedProviders
         deniedModels availableModelsMatch requiredMinimumVersion requiredMaximumVersion sshHostAllowlist
         channelsEnabled allowedChannelPlugins
         sandbox.bwrapPath sandbox.socatPath sandbox.filesystem.allowManagedReadPathsOnly
         sandbox.network.allowManagedDomainsOnly)
# ⚠ 二段階目は _ENV_RE 自体も A〜Z を畳んで照合する。畳めるのは \D \S \W \B 等の「大文字で意味が変わるエスケープ」を
#    含まないから。追加するときもリテラルと . * ( ) | ? だけで書くこと（PS 版の $envRe も同じ）。
# ⚠ CLAUDE_AFK_(TIMEOUT|COUNTDOWN)_MS は v2.1.310 の docs から消えた（どのページにも無い。changelog に廃止の記載は無い）が、
#    project の env に書いても効かない事実は変わらないので残す（外すと、効かない変数が黙って PASS になる）。
# CLAUDE_AX_.* は v2.1.305 から project / local では無視（screen reader 等）。CLAUDE_CODE_DISABLE_*_RM_* / CLAUDE_CODE_WARN_*_FREE_GIB は
# どの settings ファイルからも読まれない（起動環境だけ。MOUNTED_DRIVE_RM_PROMPT と WARN_* は v2.1.304 以降の docs で追加）。
# ホスティング環境・Claude Code 自身が設定する変数（CLAUDE_CODE_REMOTE / CLAUDE_CODE_ACCOUNT_UUID / CLAUDE_CODE_MESSAGING_* 等）は、
# 利用者が settings に書く動機が無いので含めない。
_ENV_RE='^(CLAUDE_CONFIG_DIR|CLAUDE_CODE_TMPDIR|HOME|TMPDIR|TMP|TEMP|XDG_.*|SystemRoot|ComSpec|ProgramData|LOCALAPPDATA|PATHEXT|PSModulePath|ProgramFiles.*|CommonProgramFiles.*|ALLUSERSPROFILE|SystemDrive|CLAUDE_CODE_ENABLE_TELEMETRY|CLAUDE_CODE_ENHANCED_TELEMETRY_BETA|ENABLE_ENHANCED_TELEMETRY_BETA|OTEL_(LOGS|METRICS|TRACES)_EXPORTER|OTEL_LOG_.*|OTEL_EXPORTER_OTLP_(.*_)?(ENDPOINT|HEADERS|PROTOCOL|CERTIFICATE|CLIENT_KEY|INSECURE)|OTEL_EXPORTER_PROMETHEUS_(HOST|PORT)|ENABLE_BETA_TRACING_DETAILED|BETA_TRACING_ENDPOINT|CLAUDE_CODE_PROCESS_WRAPPER|CLAUDE_CODE_SYNC_(SKILLS|PLUGINS)|CLAUDE_CODE_PLUGIN_(CACHE|SEED)_DIR|CLAUDE_AX_.*|CLAUDE_CODE_USER_DIALOG_TIMEOUT_MS|CLAUDE_AFK_(TIMEOUT|COUNTDOWN)_MS|CLAUDE_CODE_DISABLE_(ATTACHMENTS|FILE_MENTIONS)|CLAUDE_CODE_PROJECT_DIR_NAME|CLAUDE_CODE_RESTRICTED|CLAUDE_CODE_DISABLE_POWERSHELL_CMD_RM_DENY|CLAUDE_CODE_DISABLE_(DANGEROUS_RM_TIMEOUT|SUBSTITUTION_RM_PROMPT|INLINE_SHELL_RM_PROMPT|MOUNTED_DRIVE_RM_PROMPT)|CLAUDE_CODE_WARN_(DISK|MEMORY)_FREE_GIB)$'
# 照合されない権限ルール（パス付きの Write / NotebookEdit / MultiEdit / Glob）。( ) の中が 1 文字以上あるものだけ（ツール名だけ・
# 空の ( ) は対象外）。. の代わりに [\s\S] を使う（python の . は既定で改行に一致せず、PS 版の .NET も同じだが、両版で同じ意味に
# するため明示する）。大文字小文字を区別する（ツール名は区別される）。PS 版の $wRuleRe と同じ式
_W_RULE_RE='(Write|NotebookEdit|MultiEdit|Glob)\([\s\S]+\)'
SETTINGS="$SHARE/.claude/settings.json"
# ⚠ 先頭の UTF-8 BOM は専用メッセージで FAIL にする（JSON 構文・キーの検査には進まない）。Claude Code が BOM 付きの
#    settings.json を読める保証が無い（RFC 8259 §8.1 は BOM を付けないよう求め、無視するかはパーサ次第）。かつては
#    bash 版（python の utf-8）が「不正な JSON」で FAIL、PS 版（Get-Content -Encoding UTF8 が BOM を剥がす）が PASS と
#    判定が割れていた。両版とも fail-closed にそろえる。
_settings_bom=""
[[ -f "$SETTINGS" ]] && _settings_bom="$(head -c 3 "$SETTINGS" | od -An -tx1 | tr -d ' \n')"
if [[ "$_settings_bom" == "efbbbf" ]]; then
  bad "settings.json の先頭に UTF-8 BOM がある（Claude Code が BOM 付きを読める保証が無い）。BOM なしの UTF-8 で保存し直すこと（JSON 構文とキーの検査は BOM を外してから行う）"
elif [[ -f "$SETTINGS" ]]; then
  # python3 が無い環境では python を試す。どちらも無ければ「検査していない」ことを明示する
  # （黙ってスキップすると、検査した結果 PASS したのか未検査なのか区別できない）。
  PY=""
  command -v python3 >/dev/null 2>&1 && PY="python3"
  [[ -z "$PY" ]] && command -v python >/dev/null 2>&1 && PY="python"
  if [[ -n "$PY" ]]; then
    # ⚠ encoding を明示する。省略すると日本語 Windows では cp932 で読まれ、日本語を含む正しい
    #    UTF-8 の JSON を「不正な JSON」と誤判定する（実測）。
    # 構文と重複キーを 1 回で調べる。終了コード 0 = 正しい JSON で重複なし / 3 = 正しい JSON だが重複キーあり（1 組 1 行）/
    # それ以外 = 不正な JSON。重複は object_pairs_hook で拾うが、読み終えられなければ 1 なので構文の誤りが先に勝つ。
    _dup="$("$PY" - "$SETTINGS" 2>/dev/null <<'PYEOF'
import json, sys
# 1 組 = 同じオブジェクト内で完全一致または A〜Z だけ畳んで一致するキーを、文書順に ' / ' で結んだもの（PS 版の Get-JsonDupKeys
# と同じ）。str.lower() / casefold() は非 ASCII も畳むので使わない（2-c の name_class と同じ規則）
FOLD = {c: c + 32 for c in range(0x41, 0x5B)}
groups = set()
def hook(pairs):
    by = {}
    for k, _ in pairs:
        by.setdefault(k.translate(FOLD), []).append(k)
    groups.update(' / '.join(ks) for ks in by.values() if len(ks) > 1)
    return dict(pairs)
try:
    json.load(open(sys.argv[1], encoding='utf-8'), object_pairs_hook=hook)
except Exception:
    sys.exit(1)
if groups:
    # 序数（コードポイント）順。キーに非 ASCII があってもロケールの符号化に左右されないよう UTF-8 のバイト列で書く
    sys.stdout.buffer.write(('\n'.join(sorted(groups)) + '\n').encode('utf-8', 'replace'))
    sys.exit(3)
PYEOF
)"; _jrc=$?
    if [[ $_jrc -eq 3 ]]; then
      _dupj=""
      while IFS= read -r _l; do _l="${_l%$'\r'}"; [[ -n "$_l" ]] && _dupj+="${_dupj:+、}${_l}"; done <<< "$_dup"
      bad "settings.json の同じオブジェクト内でキーが重複している（大文字小文字だけが違うものを含む）: ${_dupj}（どの値が効くかは読み手によって変わる。Windows の環境変数名のように大文字小文字を区別しない読み手では同じキーになる。1 つにまとめること。キーの検査は重複を解消してから行う）"
    elif [[ $_jrc -eq 0 ]]; then
      pass "settings.json は valid JSON"
      # ⚠ python の失敗を PASS に化けさせない（出力が空でも成功扱いにすると fail-open になる。実測）
      if _res="$("$PY" - "$SETTINGS" "${_U_KEYS[*]}" "${_M_KEYS[*]}" "$_ENV_RE" "$_W_RULE_RE" 2>/dev/null <<'PYEOF'
import json, re, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
if not isinstance(d, dict):
    d = {}
def has(path):
    cur = d
    for k in path.split('.'):
        if not isinstance(cur, dict) or k not in cur:
            return False
        cur = cur[k]
    return True
u = [k for k in sys.argv[2].split() if has(k)]
perm = d.get('permissions') if isinstance(d.get('permissions'), dict) else {}
for src in (perm, d):
    if src.get('defaultMode') in ('auto', 'bypassPermissions'):
        u.insert(0, 'defaultMode:' + src['defaultMode'])
        break
m = [k for k in sys.argv[3].split() if has(k)]
env = d.get('env') if isinstance(d.get('env'), dict) else {}
# E 区分の照合（二段階。2-c の name_class と同じ規則）。re.I や str.lower() は非 ASCII も畳むので使わず、A〜Z だけを畳む
FOLD = {c: c + 32 for c in range(0x41, 0x5B)}
pat = sys.argv[4]
patf = pat.translate(FOLD)
def env_class(k):
    if re.match(pat, k):
        return 'exact'
    if re.match(patf, k.translate(FOLD)):
        return 'case'
    return 'none'
cls = {k: env_class(k) for k in env}
# 一覧に出すキーの中の CR / LF も <CR> / <LF> と書く（照合は生のキーで行う。PS 版と同じ）。re.match の $ は末尾の改行の直前にも
# 一致するので "XDG_A\n" のようなキーも E に入り、生のまま出すと下の read で後の行がずれて、照合されない権限ルールが PASS に化ける
# （PS 版は WARN が 2 行に割れる）。置き換えは下の w と同じ
vis = lambda s: s.replace('\r', '<CR>').replace('\n', '<LF>')
e = [vis(k) for k in env if cls[k] == 'exact']
ec = [vis(k) for k in env if cls[k] == 'case']
# 照合されない権限ルール。deny → ask → allow の順、各配列の中は文書順に「種別:ルール」で並べる（PS 版と同じ）。文字列以外は見ない。
# ルールの中の CR / LF は <CR> / <LF> と書く（式の [\s\S] は改行にも一致する。生のまま出すと下の read が 1 行目しか受け取らず、
# PS 版は WARN が 2 行に割れる。\r / \n と書くと Write(C:\new) のような Windows のパスと見分けられない）
w = []
for kind in ('deny', 'ask', 'allow'):
    rules = perm.get(kind) if isinstance(perm.get(kind), list) else []
    w += [kind + ':' + r.replace('\r', '<CR>').replace('\n', '<LF>') for r in rules if isinstance(r, str) and re.fullmatch(sys.argv[5], r)]
# ルールのパスに非 ASCII があってもロケールの符号化（cp932 等）に左右されないよう UTF-8 のバイト列で書く（重複キーの出力と同じ）
sys.stdout.buffer.write(('\n'.join(' '.join(x) for x in (u, m, e, ec, w)) + '\n').encode('utf-8', 'replace'))
PYEOF
)"; then
        { IFS= read -r _u; IFS= read -r _m; IFS= read -r _e; IFS= read -r _ec; IFS= read -r _w; } <<< "$_res"
        # ⚠ 行末の CR を落とす（以前は print で書いており、Windows の python はパイプへ CRLF で書いた。残すと WARN 文の途中に
        #    CR が混ざり、空判定（-n）も「CR だけの行」を非空と誤る。バイト列で書くようにした後も念のため落とす）。
        _u="${_u%$'\r'}"; _m="${_m%$'\r'}"; _e="${_e%$'\r'}"; _ec="${_ec%$'\r'}"; _w="${_w%$'\r'}"
        # 判定（E 区分は 完全一致 → 従来の WARN／大文字小文字だけ違う → 別文言の WARN）
        [[ -n "$_u" ]] && warn "方法 A（.claude/ を project として配置）では無視されるキー: $_u（方法 B / clean-test-env の --settings 結合では有効になり、配布方式で挙動が割れる。各自に効かせるなら ~/.claude/settings.json へ）"
        [[ -n "$_m" ]] && warn "project でも --settings でも無視されるキー: $_m（managed 専用。prependPlugins / appendPlugins だけは条件付きで user も可。組織の managed settings で配る）"
        [[ -n "$_e" ]] && warn "env で project / local からは設定できない変数: $_e（シェル（OS の環境変数）か、組織で固定するなら managed settings で設定する。テレメトリの off 値 none / 0 だけは例外。CLAUDE_CODE_PROJECT_DIR_NAME / CLAUDE_CODE_RESTRICTED / CLAUDE_CODE_DISABLE_*_RM_* / CLAUDE_CODE_WARN_*_FREE_GIB はどの settings ファイルからも読まれず、起動環境からしか読まれない）"
        [[ -n "$_ec" ]] && warn "env で project / local からは設定できない変数と大文字小文字だけが違う変数: $_ec（Windows でのみ同一視される。環境変数名の大文字小文字を区別しないのは Windows だけで、Windows では設定できない変数と同じ扱いになりうる。意図したものか確認すること）"
        [[ -z "$_u$_m$_e$_ec" ]] && pass "project で効かないキーなし（settings.json）"
        if [[ -n "$_w" ]]; then
          warn "照合されない権限ルール（パス付きの Write / NotebookEdit / MultiEdit / Glob）: $_w（ファイルの権限は Edit(path) / Read(path) ルールだけで照合され、これらはどこに置いても効かない。Write / NotebookEdit / MultiEdit は Edit(…)、Glob は Read(…) に書き換える。ツール名だけのルールは対象外）"
        else
          pass "照合されない権限ルールなし（settings.json）"
        fi
      else
        warn "settings.json のキー検査に失敗した（未検査）"
      fi
    else
      bad "settings.json が不正な JSON（claude doctor / /doctor でも検出される）"
    fi
  else
    warn "python が見つからず settings.json の JSON 構文とキーを検査できなかった（未検査）"
  fi
else
  warn "settings.json が無い（settings を共有しない構成なら問題なし）"
fi

# 4. 共有共通ルールの所在（案1 では .claude/CLAUDE.md。ルート CLAUDE.md は README 隔離の対象）
#    不在は FAIL。publish-share のミラーは payload に無いファイルを配布先から削除するため、
#    .claude/CLAUDE.md を持たない ref を publish すると「配布先の共通 CLAUDE.md が消える」。
#    配る構成を採用済みなので、WARN では止められない。
if [[ -f "$SHARE/.claude/CLAUDE.md" ]]; then
  pass "共有共通ルール .claude/CLAUDE.md あり（案1 構成）"
elif [[ -f "$SHARE/CLAUDE.md" ]]; then
  bad "共有ルールがルート CLAUDE.md にある（.claude/CLAUDE.md が無い）。このまま publish すると配布先の CLAUDE.md が削除される。.claude/CLAUDE.md へ移し、リポ固有情報は README.md へ"
else
  bad "共有共通ルール .claude/CLAUDE.md が無い。このまま publish すると配布先の CLAUDE.md が削除される。grooming 済みの ref を publish すること"
fi

# 5. （案1 情報）ルート CLAUDE.md が tracked なら --add-dir+env で参照側へ漏れる旨を通知
if [[ $IS_GIT -eq 1 ]] && is_tracked "CLAUDE.md"; then
  warn "ルート CLAUDE.md が Git 追跡されている。--add-dir + CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 で参照側にロードされる点に注意（リポ固有情報を含めない）"
fi

if [[ $fail -eq 0 ]]; then
  echo "[check-assets] 結果: 重大な問題なし（FAIL=0）"
else
  echo "[check-assets] 結果: FAIL あり。上記を修正してください"
fi
exit $fail
