---
name: win-file-encoding
description: >
  CP932 と UTF-8 の一括変換・検査を行う手動ツール。日本語を含む `.bat` を CP932/CRLF へ変換する、
  既存の CP932 ファイル群を UTF-8 へ移行する、CP932 でエンコードできない文字が混じっていないか事前検査する、
  といった一括作業に使う。日常の `.bat` 編集では不要（hook が自動処理する）。
---

# win-file-encoding（CP932 ⇄ UTF-8 の一括変換・検査ツール）

> **日常の `.bat` 編集にこの skill は不要**。`.claude/hooks/bat_cp932_guard.py` が原本を隠して UTF-8 の
> 作業コピーを見せ、保存時に CP932 + CRLF へ書き戻す。手順は `.claude/rules/win-file-encoding.md` を見ること。
> 本 skill は**一括変換・移行・事前検査**という、hook では扱えないまとまった作業のための手動ツール。

保存形式の方針（**原則 UTF-8。CP932 は `.bat` だけの例外**。`.ps1` は UTF-8 + BOM + CRLF で、変換不要）は
`.claude/rules/win-file-encoding.md` が正本。本 skill はその方針を**実行する道具**であって、方針を決めない。

## 実行パス（最初に確認）

```bash
# ① Plugin / Marketplace 配布時（${CLAUDE_PLUGIN_ROOT}=プラグインのインストールディレクトリ）
SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/win-file-encoding/scripts/convert_encoding.py"

# ② 層1（Git body・非 plugin）配布時 ── ★リポジトリルートを CWD にして実行すること
SCRIPT=".claude/skills/win-file-encoding/scripts/convert_encoding.py"
```

- 実行コマンドは **`python`**（本キットの想定環境では `python3` に PATH が通らないため）。
- マッピング表 `references/cp932-mapping.json` はスクリプトが `__file__` 基準で自動解決する。

## 使いどころ

| 場面 | コマンド |
|---|---|
| **事前検査**: CP932 でエンコードできない文字が無いか調べる（変換しない） | `python "$SCRIPT" --to-win --check "<target>"` |
| **CP932 化**: UTF-8/LF で書いた `.bat` を Windows 形（CP932/CRLF）へ | `python "$SCRIPT" --to-win "<target>"` |
| **UTF-8 化**: 既存の CP932 ファイルを UTF-8/LF へ移行する | `python "$SCRIPT" --to-unix "<target>"` |

- `--to-win` は UTF-8→CP932 の正規化（`〜→～` / `—→―` 等・`references/cp932-mapping.json` の `to_win`）と
  LF→CRLF を適用して上書きする。**ASCII 記号（`\` `~` 等）は不変**なのでスクリプト構文を壊さない。
- `--to-win` が CP932 エンコード不可文字を報告したら**放置しない**。`⚠` `✓` のように CP932 に符号位置が無い
  記号は ASCII（`[!]` / `[OK]`）へ置き換える。和字で対応字があるものは `cp932-mapping.json` に追記する。
- `--to-unix` に `--restore` を付けると `to_unix` の逆写像も適用する（既定 OFF。全角ハイフン等は正規の和字
  でもあり、無条件の逆変換は誤変換を招くため）。

## ⛔ 適用してはいけないもの

- **`.ps1` / `.psm1` / `.psd1`**: 正解は **UTF-8 + BOM + CRLF**。`--to-win` は **BOM を除去する**ため、
  適用すると Windows PowerShell 5.1 が CP932 と誤読して日本語が化ける（目的と正反対の結果になる）。
- **`.gitattributes` で改行が管理されているファイル**: リポジトリが方針を宣言している以上そちらが優先する。
  判断手順は `git check-attr text eol -- <path>`。属性が設定されていれば本 skill の改行変換は不要。
- **`.reg`**: `permissions.deny` で Claude の R/W を禁止しているスコープ外資産（UTF-16LE + BOM が要求される形式）。
- **`.ini`**: 拡張子だけでは文字コードを決められない（`tox.ini` / `pytest.ini` のように **UTF-8 が正しい `.ini`**
  が広く存在する）。**deny もしていない**。Win32 プロファイル用途の CP932 な `.ini` を変換するときだけ、
  対象を 1 ファイルずつ指定して使うこと。

## 依存・仕様

- `python`（CPython 3.x。`cp932` コーデックは標準同梱）。
- 改行は CR/CRLF 混在を一旦 LF に正規化してから目的の改行へ統一する（決定論的）。
- 背景と化け文字の根拠は `references/mojibake-notes.md`。
