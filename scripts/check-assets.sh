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
#
# 成果物クラスの正本リストは本配列。root/.claude 双方の .gitignore はこれに追随させること。
for _artifact in ".claude/reports" ".claude/work" ".claude/workspace" ".claude/plans" \
                 ".claude/agent-memory-local" ".claude/work_instructions.txt" \
                 ".claude/.bat-shadow"; do
  if [[ $IS_GIT -eq 1 ]]; then
    if [[ -n "$(git -C "$SHARE" ls-files -- "$_artifact" 2>/dev/null)" ]]; then
      bad "$_artifact が Git 追跡されている（payload に乗り配布される）。git rm --cached して .gitignore へ"
    elif [[ -e "$SHARE/$_artifact" ]]; then
      warn "$_artifact が実在するが未追跡（配布はされない。掃除推奨）"
    else
      pass "$_artifact なし"
    fi
  else
    if [[ -e "$SHARE/$_artifact" ]]; then
      bad "$_artifact が配布ペイロードに含まれている（内部成果物は配布しない）。grooming 済みの ref を publish すること"
    else
      pass "$_artifact なし"
    fi
  fi
done

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
payload_files() {
  if [[ $IS_GIT -eq 1 ]]; then
    git -C "$SHARE" ls-files -z -- .claude
  else
    ( cd "$SHARE" && find .claude -type f -print0 2>/dev/null )
  fi
}

# 2-e. 配布物の本文に「環境固有の絶対パス」が埋まっていないか。
#      payload は公開リポへ配る。開発者マシンのディレクトリ構成が載ると、(1) ローカルの FS
#      レイアウトを公開してしまい、(2) 利用者のマシンには存在しないパスを指示することになる。
#      （実例: skill が `C:\workspace\...\claude-plugins-official\plugins\` を参照していた）
#      説明用の例示を弾ききれないので WARN 止まり（人間が判断する）。
_abs_re='(^|[^A-Za-z])[A-Za-z]:\\[A-Za-z]|(^|[^A-Za-z])/home/[a-z][a-z0-9_-]*/|/Users/[a-z][a-z0-9_-]*/'
_abs_hits=""
while IFS= read -r -d '' _f; do
  case "$_f" in */skills/win-file-encoding/*) continue ;; esac   # 変換 skill は CP932 パスが題材
  if grep -qIE "$_abs_re" "$SHARE/$_f" 2>/dev/null; then _abs_hits+="${_f}"$'\n'; fi
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

# 3. settings.json の JSON 構文 ＋ project/local で無視される security キーの検出
SETTINGS="$SHARE/.claude/settings.json"
if [[ -f "$SETTINGS" ]]; then
  # python3 が無い環境では python を試す。どちらも無ければ「検査していない」ことを明示する
  # （黙ってスキップすると、検査した結果 PASS したのか未検査なのか区別できない）。
  PY=""
  command -v python3 >/dev/null 2>&1 && PY="python3"
  [[ -z "$PY" ]] && command -v python >/dev/null 2>&1 && PY="python"
  if [[ -n "$PY" ]]; then
    if "$PY" -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS" >/dev/null 2>&1; then
      pass "settings.json は valid JSON"
    else
      bad "settings.json が不正な JSON（/doctor でも検出される）"
    fi
  else
    warn "python が見つからず settings.json の JSON 構文を検査できなかった（未検査）"
  fi
  hits=""
  grep -Eq '"defaultMode"[[:space:]]*:[[:space:]]*"auto"'  "$SETTINGS" && hits="$hits defaultMode:auto"
  grep -Eq '"skipDangerousModePermissionPrompt"'           "$SETTINGS" && hits="$hits skipDangerousModePermissionPrompt"
  grep -Eq '"autoMode"'                                    "$SETTINGS" && hits="$hits autoMode"
  grep -Eq '"useAutoModeDuringPlan"'                       "$SETTINGS" && hits="$hits useAutoModeDuringPlan"
  if [[ -n "$hits" ]]; then
    warn "project/local では無視される可能性のあるキー:$hits（効かせるなら ~/.claude/settings.json へ）"
  else
    pass "project/local 無視キーなし（settings.json）"
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
