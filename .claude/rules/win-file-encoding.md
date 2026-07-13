---
paths:
  - "**/*.ps1"
  - "**/*.psm1"
  - "**/*.psd1"
  - "**/*.bat"
  - "**/*.cmd"
  - ".claude/.bat-shadow/**"
---

# Windows 向けファイルの文字コード・改行規約

**原則は一律 UTF-8。CP932 は `.bat` だけの例外**。「Windows 向けは一律 CP932」は成立しない ―― PowerShell 7 は
既定が UTF-8 で、CP932 の `.ps1` は日本語リテラルが壊れる（実測: `'こんにちは'.Length` が 5 → 8）。
保存形式を決める権利は書き手ではなく**読み手（処理系）**にあり、読み手ごとに正解が違う。

| 拡張子 | 読み手 | 保存形式 | 理由 |
|---|---|---|---|
| `.ps1` / `.psm1` / `.psd1` | PowerShell | **UTF-8 + BOM + CRLF** | 5.1 は BOM 無しを CP932 と誤読、7 は CP932 を読めない。**両対応はこの形式だけ**。Claude のツールでそのまま読み書きしてよい |
| `.bat` | cmd.exe | **CP932 + CRLF・BOM なし** | cmd.exe は BOM を読み飛ばさず **1 行目を壊す**。`chcp 65001` を先頭に置く回避策はコンソール表示品質を損なうため採らない |
| `.cmd` | cmd.exe | **使用禁止**（`.bat` に一本化） | `.bat` との差は一部組み込みの ERRORLEVEL 挙動のみ。例外を 1 つに絞るため |
| `.reg` / `.ini` | regedit / Win32 API | **スコープ外** | `.env` と同格。`settings.json` の `permissions.deny` で Claude の R/W を禁止している |
| `.csv` | Excel | UTF-8 + BOM | Excel は BOM を見て UTF-8 と判定する |

改行は `.gitattributes`（ルート ＋ `.claude/`）が拡張子ベースで固定する。**Claude が改行を意識する必要はない**。

## `.ps1` は普通に編集してよい（ただし新規作成は必ず壊れる）

UTF-8 + BOM なので Claude のツールがそのまま扱える。**変換は不要**。ただし **`Write` ツールは BOM も CRLF も
保持しない**（実測: `Write` で作った `.ps1` は BOM 無し・LF になる。`Edit` は保持する）。加えて Claude Code は
過去に **CRLF を二重化する不具合（v2.1.89 修正）／CRLF ファイルの改行を黙って変換する不具合（v2.1.77 修正）**
を出しており、**改行と BOM の保全は仕様として保証されていない**（公式 docs にファイル操作ツールの改行・
文字コードの規定は無い）。

そのため **`.claude/hooks/ps1_bom_crlf_check.py` が編集後に自動検査し、BOM 欠落・LF 化を検出すると差し戻す**
（PostToolUse。直し方のコマンドも一緒に返す）。手で確認するなら:

```bash
# CR バイト数（0 でなければ CRLF）と先頭 3 バイト（efbbbf なら BOM 付き）
tr -cd '\r' < <file> | wc -c
head -c 3 <file> | od -An -tx1
```

⚠ **Git Bash では `grep -c $'\r'` を CR の計測に使ってはならない**。パターンが空文字列に落ちて**全行に
マッチ**するため、返るのは CR 行数ではなく総行数になる。`awk '/\r$/'` も MSYS 版は CR を捨てて 0 を返す。
正しいのは上記の `tr` か `git ls-files --eol`。

## `.bat` は原本に触らない（hook が自動処理する）

`.bat` は CP932 なので、Claude のツールで直接読むと文字化けし、書くと UTF-8 で上書きして壊れる。
そのため **`.claude/hooks/bat_cp932_guard.py` が原本を隠し、UTF-8 の作業コピー（影）を見せる**。
**Claude は以下に従うだけでよく、文字コードを意識する必要はない**。

| やること | 方法 |
|---|---|
| **読む** | 普通に `Read <path>.bat` する。hook が UTF-8 の作業コピーへ差し替えるので**正しい日本語が読める**（原本は不変） |
| **編集する** | 原本ではなく**作業コピー `.claude/.bat-shadow/<相対パス>.bat.utf8.txt` を `Edit` する**。保存すると hook が **CP932 + CRLF で原本へ書き戻す**。作業コピーのパスは Read した直後に hook が教える |
| **新規作成する** | `python .claude/hooks/bat_cp932_guard.py new <path>.bat` で空の `.bat` と作業コピーを作り、作業コピーを編集する（`Write` は拒否される） |
| **中身を検索する** | `python .claude/hooks/bat_cp932_guard.py sync` で全作業コピーを更新してから、`Grep` の対象を `.claude/.bat-shadow/` にする（CP932 のままでは Grep は日本語にヒットしない） |

- **原本への `Edit` / `Write` は `permissions.deny` で拒否される**。hook は Python が無い環境では失敗して素通り
  するため、**ハードなガードは permission 側が担い、hook は利便性を担う**という二層構造にしてある。
- **CP932 に存在しない文字は書き戻し時に拒否される**（原本は書き換わらない）。`⚠` `‼` `✓` `✗` は CP932 に
  符号位置が無いので、`.bat` のメッセージ記号は **ASCII（`[!]` / `[OK]` 等）**を使う。
  `〜` `—` `−` のような和字は `.claude/skills/win-file-encoding/references/cp932-mapping.json` の表で
  CP932 の対応字へ自動正規化されるため、拒否されない。
- **`.bat` を `sed -i` やリダイレクトで書き換えない**（Bash 経由の書き込みは hook が守れない）。

> 一括変換・検査を手動で行いたい場合は `win-file-encoding` skill の `convert_encoding.py` を使う
> （`--to-win --check` で CP932 エンコード可否だけを検査できる）。日常の `.bat` 編集で skill を呼ぶ必要はない。
