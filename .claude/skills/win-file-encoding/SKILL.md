---
name: win-file-encoding
description: >
  日本語を含む Windows 向けスクリプト（`.ps1` / `.bat` / `.cmd` / `.reg` / `.ini`、例: backup.cmd /
  deploy.ps1 / run.bat / setup.ps1）を新規作成・編集するときは必ずこの skill を使う。echo・Write-Host・
  コメント・ログ・メッセージ等に日本語が一文字でも入る場合、文字コード指定（Shift-JIS / CP932）の明示有無に
  関わらず対象。「メモ帳で開いても化けない」「波ダッシュ・全角チルダ・円マークが化ける」「CRLF を保ちたい」
  「既存の cp932 ファイルを壊さず1行直す」も該当。理由: Claude のネイティブ Read / Edit / Write / Grep は
  UTF-8 前提で、CP932/CRLF の Windows ファイルを直接触ると日本語が文字化け・破損する。本 skill が UTF-8/LF ⇄
  CP932/CRLF を安全に往復変換し、化け文字を正規化する手順とスクリプトを提供する。発火しない例: 英語のみの
  Windows スクリプト、Python/CSV/Excel の文字化け対処、Linux/bash 向けスクリプト、`.gitattributes` 単独設定、
  Markdown 文書。
---

# win-file-encoding（Windows 向けファイルの安全な作成・編集）

Claude のネイティブツールは UTF-8 前提。最終成果物が **CP932・CRLF** で要求される Windows 向け
ファイル（`.ps1` / `.bat` / `.cmd` / `.reg` / `.ini` 等）を、文字化けさせずに作成・編集するための
往復変換手順。変換スクリプトは本 skill の `scripts/convert_encoding.py`、化け文字の正規化表は
`references/cp932-mapping.json`（根拠は `references/mojibake-notes.md`）。

## 実行パス（最初に確認）

変換スクリプトのパスは配布形態で異なる。下記いずれかで `SCRIPT` を設定してから、パターン A/B の
コマンド（`python "$SCRIPT" ...`）を実行する。

```bash
# ① Plugin / Marketplace 配布時（既定。${CLAUDE_PLUGIN_ROOT}=プラグインのインストールディレクトリ）
SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/win-file-encoding/scripts/convert_encoding.py"

# ② 層1（Git body・非 plugin）配布時 ── ★リポジトリルートを CWD にして実行すること（相対パスは CWD 依存）
SCRIPT=".claude/skills/win-file-encoding/scripts/convert_encoding.py"

# ③ CWD 非依存にしたい場合は絶対パス（① ② どちらの配布形態でも可・最も確実）
SCRIPT="/abs/path/to/skills/win-file-encoding/scripts/convert_encoding.py"
```

- 実行コマンドは **`python`**（本キットの想定環境では `python3` に PATH が通らないため。`python` が無い環境でのみ `python3`）。
- マッピング表 `references/cp932-mapping.json` はスクリプトが `__file__` 基準で自動解決するため、別途パス指定は不要。

## ⛔ CRITICAL（最優先・絶対遵守）

- **CP932 のファイルを Claude のネイティブ Read / Edit / Write / Grep で直接触らない。** UTF-8 前提で
  デコードされ文字化け・破損する。**必ず先に `--to-unix` で UTF-8/LF 化してから**ネイティブツールで扱う。
- ネイティブで編集したら**作業の最後に必ず `--to-win` で CP932/CRLF へ戻す**（戻し忘れると Windows 側で壊れる）。
- `--to-win` が CP932 エンコード不可文字を報告したら**放置しない**。`cp932-mapping.json` に追記して再実行する
  （黙ってデータを失わせない）。

## パターン A: 新規作成

1. **Claude ネイティブで作成**（この時点では UTF-8 / LF）。`Write` で通常どおり作る。
2. **Win 形へ変換**:
   ```bash
   python "$SCRIPT" --to-win "<target>"
   ```
   → UTF-8→CP932 の正規化（波ダッシュ→全角チルダ 等）＋ LF→CRLF を適用して上書き。
3. これで完了。以降そのファイルを再び**ネイティブで読む/編集する必要が出たら、パターン B**（先に `--to-unix`）に従う。

> 補足: 事前にエンコード可否だけ確認したいときは `--to-win --check`（変換せず CP932 エンコード可否のみ報告。NG なら行番号付きで列挙し exit≠0、OK なら `[OK]` を表示）。

## パターン B: 既存 Win ファイルの編集

1. **UTF-8 形へ変換**（ネイティブで触れる状態にする）:
   ```bash
   python "$SCRIPT" --to-unix "<target>"
   ```
   → CP932→UTF-8 デコード（ロスレス）＋ CRLF→LF。
   - 直前に自分で `--to-win` した内容を**完全に round-trip で戻したい**場合のみ `--restore` を付ける
     （既定 OFF。全角ハイフン等の正規の和字を誤変換しないため）。
2. **Claude ネイティブで編集**（`Read` / `Edit` / `Grep`。ここは UTF-8/LF なので安全）。
3. **Win 形へ戻す**（パターン A の手順 2 と同一）:
   ```bash
   python "$SCRIPT" --to-win "<target>"
   ```

## マッピング（化け文字の正規化）

`references/cp932-mapping.json` の `to_win` が UTF-8→CP932 で正規化する和字ペア
（`〜→～` / `−→－` / `—→―` / `‖→∥` / `¢£¬→￠￡￢`）。**ASCII 記号（`\` `~` 等）は対象外＝不変**で、
`.ps1`/`.bat` の構文を壊さない。背景と拡張手順は `references/mojibake-notes.md` を参照。

## 運用上の注意

- **git 管理**: CP932/CRLF ファイルを commit すると diff が読みにくく壊れやすい。リポジトリ方針として
  「CP932 を唯一の成果物として往復運用」か「UTF-8 を正本に置き CP932 を生成物（`.gitattributes`/生成）」かを
  決めておく。本 skill はどちらの運用でも変換器として機能する。
- **依存**: `python`（CPython 3.x。`cp932` コーデックは標準同梱）。
- **改行**: 変換器は CR/CRLF 混在を一旦 LF に正規化してから目的の改行へ統一する（決定論的）。
