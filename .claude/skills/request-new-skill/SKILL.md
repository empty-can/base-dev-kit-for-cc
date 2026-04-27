---
name: request-new-skill
description: 新しいSkillの作成依頼を開始する。作業用フォルダを作成し、依頼書テンプレートをコピーする。
allowed-tools: Bash(mkdir:*), Bash(cp:*), Bash(date:*)
---

## 引数

`/request-new-skill <概要>` の形式で呼び出す。`<概要>` はSkillの内容を短く表す日本語または英語の説明。

## 実行手順

1. **フォルダ名を生成する**
   - `<概要>` をケバブケース（英数字・ハイフンのみ）に変換する
   - 日本語の場合はローマ字または意味が伝わる英語に意訳する
   - 例: "コミット自動化" → `auto-commit`、"daily report" → `daily-report`
   - プレフィックスとして今日の日付（`YYYYMMDD`）を付与する
   - 最終形: `YYYYMMDD-<kebab-case>`

2. **作業用フォルダを作成する**
   ```
   .claude/workspace/skill-request/<生成したフォルダ名>/
   ```

3. **テンプレートをコピーする**
   - `.claude/templates/skill-request/skill-request-form.md` → 作業用フォルダへコピー
   - `.claude/templates/skill-request/skill-cc-response.md` → 作業用フォルダへコピー

4. **完了を報告する**
   - 作成したフォルダのパスを伝える
   - 「`skill-request-form.md` に要件を記入して渡してください」と案内する
