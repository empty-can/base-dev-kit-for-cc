# 調査C: Slash Commands・Sub-agents・Skills の設計パターン

## 調査概要

**調査目的**: Claude Code ベースキットに配置する「動作する実用サンプル」の設計指針を、公式仕様と Anthropic 公式リポジトリの実例から抽出する

**実施日**: 2026-04-24

**取得した実例ファイル**:
- `anthropic-cookbook/.claude/commands/notebook-review.md`
- `anthropic-cookbook/.claude/commands/model-check.md`
- `anthropic-cookbook/.claude/agents/code-reviewer.md`
- `anthropic-cookbook/.claude/skills/cookbook-audit/style_guide.md`
- `anthropic/claude-code/.claude/commands/commit-push-pr.md`

## 1. Slash Commands / Skills の frontmatter 仕様

| プロパティ | 型 | 意味 | 必須 |
|---|---|---|---|
| `name` | string | コマンド名（lowercase + hyphens、最大 64 文字） | 任意（デフォルト: ディレクトリ名） |
| `description` | string | 説明・トリガー条件（Claude の自動実行判定に使用、最大 1,536 文字） | 推奨 |
| `when_to_use` | string | description 追加条件（同上合計 1,536 文字） | 任意 |
| `argument-hint` | string | 補完時ヒント（例: `[issue-number]`） | 任意 |
| `arguments` | string\|list | 名前付き位置引数（`$name` で参照） | 任意 |
| `disable-model-invocation` | bool | `true` で Claude 自動実行を禁止 | 任意（副作用ある操作で推奨） |
| `user-invocable` | bool | `false` でメニュー非表示（Claude のみ実行） | 任意 |
| `allowed-tools` | string\|list | 許可ツール一覧 | 任意 |
| `model` | string | モデル上書き（`sonnet`/`opus`/`haiku`/full ID/`inherit`） | 任意 |
| `effort` | string | 努力レベル（`low`〜`max`） | 任意 |
| `context` | string | `fork` でサブエージェント分離実行 | 任意 |
| `agent` | string | `context: fork` 時のエージェント型 | 任意 |
| `hooks` | object | スキルライフサイクルフック | 任意 |
| `paths` | string\|list | glob パターン（自動ロード条件） | 任意 |
| `shell` | string | `bash`/`powershell` | 任意 |

## 2. 本文の書き方パターン

### タイプA: リファレンス型（インライン知識）
- 目的: API 規則、スタイルガイド、ドメイン知識
- 構造: 見出し → リスト/表 → コード例
- 特性: ロード中は常時参照可能

### タイプB: タスク型（手順指示）
- 目的: デプロイ、コミット、コードレビュー
- 構造: 前置 → ステップ 1, 2, 3 → 結果検証
- 推奨: `disable-model-invocation: true`

### タイプC: コンテキスト注入型（動的データ）
- `` !`command` `` や ` ```! ` でシェル出力を埋め込み
- 前処理のため Claude は結果のみ参照

## 3. Slash Commands の実例分析

### commit-push-pr.md（anthropic/claude-code）- タイプB+C

```markdown
---
allowed-tools: Bash(git checkout --branch:*), Bash(git add:*), Bash(git status:*), Bash(git push:*), Bash(git commit:*), Bash(gh pr create:*)
description: Commit, push, and open a PR
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`

## Your task

Based on the above changes:
1. Create a new branch if on main
2. Create a single commit with an appropriate message
3. Push the branch to origin
4. Create a pull request using `gh pr create`
5. You have the capability to call multiple tools in a single response. You MUST do all of the above in a single message.
```

**分析**:
- `allowed-tools` で git コマンドを細粒度許可
- `` !`git status` `` でコンテキスト注入（現在状態を自動取得）
- 「You MUST do all... in a single message」で responsiveness 保証
- タスク型 + コンテキスト注入のハイブリッド

### notebook-review.md（anthropic-cookbook）- タイプB

```markdown
---
allowed-tools: Bash(gh pr comment:*),Bash(gh pr diff:*),Bash(gh pr view:*),Bash(echo:*),Read,Glob,Grep,WebFetch
description: Comprehensive review of Jupyter notebooks and Python scripts
---

**IMPORTANT**: Only review the files explicitly listed in the prompt above. Do not search for or review additional files.

Review the specified Jupyter notebooks and Python scripts using the Notebook review skill.

Provide a clear summary with:
- ✅ What looks good
- ⚠️ Suggestions for improvement
- ❌ Critical issues that must be fixed
```

**分析**:
- 細粒度の GitHub CLI 許可
- インプット制限（「ここに list のファイルだけ」）を明確化
- 出力フォーマット（3 段階の summary）を明記

## 4. Sub-agents の frontmatter 仕様

| プロパティ | 型 | 意味 | 必須 |
|---|---|---|---|
| `name` | string | エージェント ID | 必須 |
| `description` | string | 委譲判定用（Claude が判断） | 必須 |
| `tools` | string\|list | 使用可能ツール（allowlist） | 任意 |
| `disallowedTools` | string\|list | 除外ツール（denylist） | 任意 |
| `model` | string | モデル指定 | 任意 |
| `permissionMode` | string | 権限モード | 任意 |
| `maxTurns` | int | 最大 turn 数 | 任意 |
| `skills` | list | 起動時にロードするスキル | 任意 |
| `mcpServers` | list | 専用 MCP サーバー | 任意 |
| `hooks` | object | ライフサイクルフック | 任意 |
| `memory` | string | `user`/`project`/`local` メモリスコープ | 任意 |
| `background` | bool | バックグラウンド実行 | 任意 |
| `isolation` | string | `worktree` で git worktree 隔離 | 任意 |
| `color` | string | UI 表示色 | 任意 |

## 5. Sub-agents 実例分析

### code-reviewer.md（anthropic-cookbook）

```markdown
---
name: code-reviewer
description: Performs thorough code reviews for the Notebooks in the Cookbook repo, focusing on Python/Jupyter best practices, and project-specific standards. Use this agent proactively after writing any significant code changes, especially when modifying notebooks, Github Actions, and scripts
tools: Read, Grep, Glob, Bash, Bash(git status:*)
---

You are a senior software engineer specializing in code reviews for Anthropic's Cookbooks repo.

Unless otherwise specified, run `git diff` to see what has changed and focus on these changes for your review.

## Core Review Areas

1. **Code Quality & Readability**: ...
2. **Python Patterns**: ...
3. **Security**: ...
4. **Notebook Pedagogy**: ...

## SPECIFIC CHECKLIST

### Notebook Structure & Content
...
```

**分析**:
- `description` が長い（1 文ではなく、使用タイミングも含む → Claude の委譲判断精度向上）
- `tools` は最小権限（読み取り系 + git status のみ）
- 本文は詳細チェックリスト形式
- 責務範囲が明確（Cookbook 特化）

## 6. Skills（ディレクトリ型）の実例

### cookbook-audit/style_guide.md（タイプA リファレンス型）

```markdown
# 1. Introduction

Purpose: Frame the notebook around the problem being solved and the value delivered.

### Structure
Hook with the problem (1-2 sentences)
Why it matters (1-2 sentences)
...

### Template
```
## Introduction
[2-3 sentences: What's the problem? Why is it hard/important?]
...
```
```

**分析**:
- 目的明記から開始
- Good/Bad 対比を含む
- プレースホルダー付きテンプレート形式
- セクション単位で独立

## 7. description の書き方（重要）

**Claude の自動委譲判定に直接影響するため最重要**

❌ **悪い例**:
```
description: Help with code
description: Execute a command
```

✅ **良い例**:
```
description: Thoroughly review code for quality, security, and best practices. Use when you've made significant changes or when the user explicitly asks for a review.

description: Validate Claude model references in code. Check that all model names match current public models list and flag deprecated versions.
```

**ルール**:
- 動詞で始めない（動作ではなく機能・目的を記述）
- 使用タイミング（`Use when...`）を含める
- `when_to_use` で追加条件を記述可能

## 8. 設計判断フロー

1. **一度限りの操作か、繰り返し参照か？**
   - 一度限り → Task Skill（`disable-model-invocation: true`）
   - 参照多用 → Reference Skill

2. **多くの context 結果が出るか？**
   - Yes → Sub-agent（context flooding 回避）
   - No → Inline Skill

3. **project 固有か？**
   - Yes → `.claude/skills/` または `.claude/agents/`
   - No → `~/.claude/skills/` （personal）

4. **自動実行させるか？**
   - Yes → description を詳細に、`disable-model-invocation` default (false)
   - No → `disable-model-invocation: true`

## 9. ベースキット採用推奨サンプル

| サンプル名 | 種類 | 用途 | 言語中立 |
|---|---|---|---|
| `commit-and-pr` | Skill（Task 型） | git フロー自動化 | Yes |
| `code-reviewer` | Sub-agent | コード品質レビュー | Yes（言語非依存化）|
| `orchestrator` | Sub-agent | 他エージェントの指揮（Management agent） | Yes |
| `coding-standards` | Skill（Reference 型）または rules/ | コーディング規約 | Yes |

## 10. ベースキット向けテンプレート

### Template A: Task Skill（タスク型）
```markdown
---
name: my-task
description: <機能・目的の名詞句説明>. Use when [trigger condition].
disable-model-invocation: true
allowed-tools: Bash(git *), Read, Write
---

## Context
- Current branch: !`git branch --show-current`
- Recent changes: !`git diff --stat`

## Your task
Based on the above context:
1. [Step 1]
2. [Step 2]
3. [Step 3]
```

### Template B: Reference Skill / Rules（リファレンス型）
```markdown
---
name: coding-standards
description: Coding standards for this project.
---

## Naming Conventions
- Variables: `snake_case`
- Constants: `UPPER_SNAKE_CASE`

## Code Style
- Line length: 100 characters
```

### Template C: Sub-agent（コードレビュー）
```markdown
---
name: quality-reviewer
description: Reviews code changes for quality, security, and best practices. Invoke after significant code changes.
tools: Read, Grep, Glob, Bash(git *)
model: sonnet
---

You are an expert code reviewer.

## Review Areas
1. **Security**: ...
2. **Performance**: ...
3. **Maintainability**: ...
4. **Testing**: ...

## Review Process
1. Run `git diff` to see changes
2. Identify critical issues first
3. Provide specific feedback with file:line references

## Feedback Structure
- **[CRITICAL]**: Security or breaking changes
- **[IMPORTANT]**: Quality issues
- **[SUGGESTION]**: Enhancements
- **[POSITIVE]**: What's working well
```

## 11. 重要な注意点

- `allowed-tools` は最小権限原則で設計
- SKILL.md は 500 行以下推奨
- Agent system prompt は 2000 行以下推奨
- description + when_to_use 合計 1,536 文字上限
- コンテキスト注入（`` !`cmd` ``）で現在状態を明示化

## 参考資料

- https://code.claude.com/docs/en/skills
- https://code.claude.com/docs/en/sub-agents
- https://code.claude.com/docs/en/commands
- https://github.com/anthropics/anthropic-cookbook/tree/main/.claude
- https://github.com/anthropics/claude-code/tree/main/.claude
