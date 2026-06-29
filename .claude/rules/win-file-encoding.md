---
paths:
  - "**/*.ps1"
  - "**/*.bat"
  - "**/*.cmd"
  - "**/*.reg"
  - "**/*.ini"
---

# Windows 向けファイル（CP932/CRLF）編集規約

`.ps1` / `.bat` / `.cmd` / `.reg` / `.ini` は **CP932・改行 CRLF が要求される Windows 向け成果物**である
ことが多い。このファイルが日本語を含む（または含めうる）場合、Claude のネイティブ Read / Edit / Write / Grep は
UTF-8 前提のため、**CP932 ファイルを直接読み書きすると日本語が文字化け・破損する**。

> このルールは「**いつ** 気をつけるか」を担う（path-scoped 自動ロード）。**手順とスクリプトの実体は
> `win-file-encoding` skill 側**にある。Skill には `paths:` による自動発火が無く description だけでは確実に
> トリガーしないため、本ルールが発火の起点となる。

## 該当する場合は `win-file-encoding` skill の手順に必ず従う

- **新規作成**: ネイティブで UTF-8/LF 作成 → `convert_encoding.py --to-win` で CP932/CRLF 化。
- **既存編集**: 先に `--to-unix` で UTF-8/LF 化 → ネイティブ編集 → 最後に `--to-win` で CP932/CRLF へ戻す。
- **CP932 ファイルを直接 Read / Edit / Grep しない**（必ず先に UTF-8 化してから触る）。

skill 本体: `.claude/skills/win-file-encoding/SKILL.md`（plugin 配布時は
`${CLAUDE_PLUGIN_ROOT}/skills/win-file-encoding/`）。変換スクリプト・化け文字正規化表・根拠は同 skill の
`scripts/` `references/` を参照。

## 適用しないケース

- 英語のみ・UTF-8 が要件のファイル（UTF-8 前提の `.ini`、英語専用スクリプト等）。
- Python/CSV/Excel の文字化け対処、Linux/bash 向けスクリプト、`.gitattributes` 単独設定、Markdown 文書
  （いずれも本 skill のスコープ外）。
