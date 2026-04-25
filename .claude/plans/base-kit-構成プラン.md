# claude-code-base-kit 作業計画書（v3）

## 背景と目的

このプロジェクトを「Claude Code を最大限活用するための、必要最低限かつ言語中立・クロスプラットフォームな構成」のベースキットに作り替える。個人用・新規プロジェクトのスタート地点として利用する。

## 改訂履歴

- **v1（2026-04-23）**: 不承認。調査不足
- **v2（2026-04-24）**: 追加調査 A〜E 実施後、全面改訂。⚠️ クロスレビューで条件付き承認
- **v3（2026-04-24）**: 追加調査 F/G でレビュー指摘を解消し、本版で最終化

## 確定した要件

| 項目 | 内容 |
|---|---|
| 用途 | 個人用・新規プロジェクトのスタート地点 |
| 対象言語 | 言語中立 |
| OS | クロスプラットフォーム（Windows/Mac/Linux） |
| ドキュメント言語 | 日本語 |
| 成果物粒度 | 動作する実用サンプル |
| スコープ | 最小限＋他機能は CLAUDE.md で拡張方法を記述 |

---

## 設計判断と根拠（v3 更新版）

### 判断 1: CLAUDE.md は プロジェクトルート `./CLAUDE.md` に配置
- **根拠**: 公式等価（調査E項目4）、発見性優先（調査B）

### 判断 2: Custom commands でなく Skills を採用
- **根拠**: commands は skills に統合済み（調査E項目9）

### 判断 3: **Hooks を採用**（v2 から変更）
- **根拠**: 調査F で OS 中立コマンドによるクロスプラットフォーム実装が可能と確認。`claude-code-action` で実装実績あり（`bun run format`）。Hooks の学習価値が高い
- **実装方針**: 最小限の SessionStart hook を 1 つだけ。`git status --short` のような OS 中立コマンドに限定

### 判断 4: Plugin 化しない
- **根拠**: 個人用途は standalone `.claude/` 推奨（調査E項目12）

### 判断 5: コーディング規約は rules/ に配置（path-scoped）
- **根拠**: context 効率（調査A/B）。`paths:` で**言語拡張子を明示**（クロスレビュー改善提案1を反映）

### 判断 6: クロスプラットフォームは OS 中立コマンドで実装
- **根拠**: `git` など全 OS で動作するコマンドを使う。bash/PowerShell の分岐は避ける（調査F）

### 判断 7: Sandbox はデフォルト無効、CLAUDE.md で有効化方法を記載
- **根拠**: 最小構成を維持（ベースキット性質）

### 判断 8: **Orchestrator は Sub-agent でなく Skill として実装**（v2 から変更）
- **根拠**: 公式ドキュメント明記「Subagents cannot spawn other subagents」（調査G）。Sub-agent として実装すると機能しないため、Skill で実装する

### 判断 9: Agent Teams はベースキットに含めない
- **根拠**: 実験段階のため（調査G）。CLAUDE.md で参考情報として簡単に言及のみ

---

## 最終ディレクトリ構造

```
claude-code-base-kit/
├── CLAUDE.md                          ← 全面書き直し
├── .gitignore                         ← 全面書き直し
├── .env.example                       ← 新規（秘匿情報管理サンプル）
├── CLAUDE.local.md.example            ← 新規（個人指示ファイルのサンプル）
└── .claude/
    ├── settings.json                  ← 全面書き直し（最小hook含む）
    ├── settings.local.json.example    ← 新規
    ├── rules/
    │   └── coding-standards.md        ← 新規（path-scoped）
    ├── skills/
    │   ├── commit-and-pr/
    │   │   └── SKILL.md               ← 新規
    │   └── orchestrate/
    │       └── SKILL.md               ← 新規（Management 機能を Skill 化）
    └── agents/
        └── code-reviewer.md           ← 新規（orchestrator.md は作らない）
```

---

## タスク一覧

### タスク 1: `.gitignore` の全面書き直し

**内容**:
```gitignore
# Claude Code: ローカル個人設定（チームで共有しない）
.claude/settings.local.json
CLAUDE.local.md

# Claude Code: ローカル専用エージェントメモリ（memory: local スコープの sub-agent 用）
.claude/agent-memory-local/

# 環境変数・機密情報
.env
.env.*
!.env.example
secrets/

# 言語別・環境別（新規プロジェクト適用時は必要に応じて調整）
# 本ベースキットは言語中立を原則とするが、一般的なエントリを同梱
node_modules/
__pycache__/
*.pyc
.venv/
venv/
target/
vendor/
dist/
build/
out/

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
```

**改善点（クロスレビュー対応）**:
- `agent-memory-local/` に用途コメントを追加
- 言語別エントリに「言語中立を原則とするが一般的なエントリを同梱」と明記

### タスク 2: `.env.example` の新規作成

**内容**:
```dotenv
# 環境変数のサンプル。実際の値は `.env` ファイル（gitignore 対象）に記述する。
# API キーや秘匿情報はここに書かないこと。

# API_BASE_URL=https://api.example.com
# DATABASE_URL=postgresql://localhost/mydb
# LOG_LEVEL=info
```

### タスク 3: `CLAUDE.local.md.example` の新規作成

**内容**:
```markdown
# CLAUDE.local.md

このファイルは個人用の補足指示を記述するためのテンプレートです。
使用する場合はコピーして `CLAUDE.local.md` にリネームしてください。
`.gitignore` で除外されるため、チームメイトには共有されません。

## 個人用の追加指示

例：
- エディタ固有の癖（vim モード等）を考慮してほしい
- 特定のログ出力形式を好む
- 個人環境でのみ利用できる外部サービス（あれば）
```

### タスク 4: `.claude/settings.json` の全面書き直し

**内容**:
```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "Read(~/.aws/credentials)",
      "Read(~/.ssh/**)"
    ],
    "allow": [
      "Bash(git status)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git branch:*)",
      "WebFetch(domain:code.claude.com)",
      "WebFetch(domain:docs.claude.com)",
      "WebFetch(domain:github.com/anthropics)"
    ]
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "git status --short"
          }
        ]
      }
    ]
  }
}
```

**改善点（クロスレビュー対応）**:
- `WebFetch(domain:github.com)` → `github.com/anthropics` に絞った
- Hooks を **採用**し、最小 SessionStart hook を追加（`git status --short` は全 OS で動作）

### タスク 5: `.claude/settings.local.json.example` の新規作成

**内容**:
```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": []
  }
}
```

### タスク 6: `.claude/rules/coding-standards.md` の新規作成

**内容**（骨子）:
```markdown
---
paths:
  - "**/*.js"
  - "**/*.ts"
  - "**/*.jsx"
  - "**/*.tsx"
  - "**/*.py"
  - "**/*.go"
  - "**/*.rs"
  - "**/*.java"
  - "**/*.rb"
  - "**/*.kt"
  - "**/*.swift"
  - "**/*.c"
  - "**/*.cpp"
  - "**/*.cs"
---

# コーディング規約

このルールは一般的な**コードファイル**を編集する際にのみロードされる（path-scoped）。
プロジェクト固有の規約があれば、このファイルを編集するか、各言語ごとのルールファイルを `rules/` に追加してください。

## 命名規則
...

## コメント方針
...

## エラー処理
...

## テスト
...
```

**改善点（クロスレビュー対応）**:
- `paths: "**/*"` （無意味）を具体的な**コード拡張子**に変更

### タスク 7: `.claude/skills/commit-and-pr/SKILL.md` の新規作成

**内容**（骨子）:
```markdown
---
name: commit-and-pr
description: 現在のステージ済み・未ステージ変更を適切なメッセージでコミットし、プッシュして Pull Request を作成する。変更が完成して共有可能な状態になったら使用する。
disable-model-invocation: true
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git branch:*), Bash(git push:*), Bash(gh pr create:*)
---

## 前提条件

- `gh` CLI がインストールされていること（未インストールの場合は手動で PR 作成してください）
- GitHub にリモートリポジトリが存在すること

## コンテキスト

- 現在の変更: !`git status --short`
- ブランチ: !`git branch --show-current`
- 差分サマリ: !`git diff --stat HEAD`

## 実行手順

以下を **1 メッセージで連続して** 実行してください：

1. main ブランチの場合は新ブランチを作成
2. 変更を単一コミットにまとめる（メッセージは変更内容を端的に表現）
3. リモートへプッシュ
4. `gh pr create` で PR 作成
```

**改善点（クロスレビュー対応）**:
- `gh` 未インストール時のフォールバック注記を追加

### タスク 8: `.claude/skills/orchestrate/SKILL.md` の新規作成（旧タスク 8 を差し替え）

**内容**（骨子）:
```markdown
---
name: orchestrate
description: 複雑なタスクで複数の専門エージェントを協調させる。並列調査・段階的レビュー・複数領域の実装など、単独では非効率な作業に適用する。
disable-model-invocation: true
allowed-tools: Agent, Read, Grep, Bash
---

# オーケストレーション・フレームワーク

このスキルは、複数の Sub-agent を協調させて複雑なタスクを効率的に処理する手順を提供します。
Claude Code の公式仕様では「Subagents cannot spawn other subagents」のため、
本スキルは**メインセッション**で実行され、Agent ツール経由で子エージェントを並列/順次起動します。

## パターンA: 並列調査（Parallel Research）

複数の独立したトピックを同時に調査する場合：
1. トピックごとに Explore エージェントを並列起動
2. 全結果を待って統合

## パターンB: 段階的処理（Sequential Chain）

前段の結果が次段に必要な場合：
1. Phase 1: コードレビュー（code-reviewer エージェント）
2. Phase 2: 最適化提案（Plan エージェント）
3. 結果を統合

## パターンC: 役割分担（Divide and Conquer）

大規模タスクを専門領域に分割する場合：
1. 領域ごとに専門エージェントを割り当て
2. メインセッションが結果を取りまとめ
```

**改善点（クロスレビュー対応）**:
- 旧 `.claude/agents/orchestrator.md` を廃止し、**Skill として実装**（`Subagents cannot spawn other subagents` の仕様制約のため）

### タスク 9: `.claude/agents/code-reviewer.md` の新規作成

**内容**（骨子）:
```markdown
---
name: code-reviewer
description: コード変更を品質・セキュリティ・保守性・テストの観点でレビューする。大きな変更を完了した後に主体的に使用する。
tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*)
model: sonnet
---

あなたは経験豊富なコードレビュアーです。

## レビュー観点

1. **セキュリティ**: 認証情報の漏洩、インジェクション、入力検証
2. **パフォーマンス**: 非効率な処理、メモリリーク、不要なループ
3. **保守性**: 可読性、命名、DRY 原則、複雑度
4. **テスト**: カバレッジ、エッジケース、エラー処理

## プロセス

1. `git diff` で変更を確認
2. 変更範囲をファイル単位で精査
3. 重大度順にフィードバックを出力

## 出力フォーマット

- **[CRITICAL]**: セキュリティ問題・破壊的変更
- **[IMPORTANT]**: 品質・保守性の問題
- **[SUGGESTION]**: 改善提案・スタイル
- **[POSITIVE]**: 良かった点
```

### タスク 10: `CLAUDE.md` の全面書き直し（**最後に実施**）

**含めるセクション**（200 行以内）:

1. **このキットについて** — 用途・カスタマイズ方針
2. **ディレクトリ構造** — 主要ファイルと役割
3. **開発コマンド**（プレースホルダー） — Build/Test/Dev/Lint
4. **コーディング規約** — 詳細は `.claude/rules/coding-standards.md` に移譲
5. **Git ワークフロー** — ブランチ命名・コミットプレフィックス・`commit-and-pr` skill の利用
6. **マルチエージェント戦略** — `orchestrate` skill と `code-reviewer` agent の使い方
7. **重要な制約** — `.env` 直接編集禁止・秘匿情報ハードコード禁止
8. **拡張オプション** — Sandbox 有効化、MCP 接続、Agent Teams（実験的）、output-styles、plugin 化

**セクション別行数配分（目安）**: 約 150 行。各セクション 15〜25 行以内。

---

## 各タスクの依存関係と実施順序

1. **並列実施可能**: タスク 1〜9
2. **最後に実施**: タスク 10（CLAUDE.md は他タスクの成果物を参照）

---

## 検証方法

### 1. JSON 構文チェック（環境非依存）
```bash
# Claude Code 自身に JSON ファイルを読ませる、または：
python -c "import json; json.load(open('.claude/settings.json'))"
# Python が無い場合は：
# （Node.js がある場合）node -e "require('./.claude/settings.json')"
```

### 2. 行数確認
```bash
# OS 中立（POSIX sh / PowerShell 両対応）
wc -l CLAUDE.md  # CLAUDE.md が 200 行以内であること
```

### 3. 構造確認
```bash
ls -la .claude/
ls -la .claude/skills/
ls -la .claude/agents/
ls -la .claude/rules/
```

以下が存在すること：
- `.claude/settings.json`
- `.claude/settings.local.json.example`
- `.claude/rules/coding-standards.md`
- `.claude/skills/commit-and-pr/SKILL.md`
- `.claude/skills/orchestrate/SKILL.md`
- `.claude/agents/code-reviewer.md`
- `.env.example`
- `CLAUDE.local.md.example`

### 4. `.gitignore` の動作確認
- `.claude/settings.local.json` および `CLAUDE.local.md` を作成し、`git status` で追跡されないことを確認

### 5. Claude Code での実機動作確認
- Claude Code を再起動し、以下を確認：
  - CLAUDE.md が読み込まれる
  - SessionStart hook で `git status --short` が実行される
  - `/commit-and-pr` スラッシュコマンドが認識される
  - `/orchestrate` スラッシュコマンドが認識される
  - エージェント一覧に `code-reviewer` が表示される
  - `code-reviewer` エージェントに git diff を食わせてレビュー結果が返る
  - `orchestrate` skill から `Agent` ツールで子エージェントが起動できる（手動確認）

---

## 変更ファイル一覧

| # | ファイル | 変更種別 |
|---|---|---|
| 1 | `.gitignore` | 全面書き直し |
| 2 | `.env.example` | 新規 |
| 3 | `CLAUDE.local.md.example` | 新規 |
| 4 | `.claude/settings.json` | 全面書き直し（hook 追加） |
| 5 | `.claude/settings.local.json.example` | 新規 |
| 6 | `.claude/rules/coding-standards.md` | 新規（path-scoped） |
| 7 | `.claude/skills/commit-and-pr/SKILL.md` | 新規 |
| 8 | `.claude/skills/orchestrate/SKILL.md` | 新規（Orchestrator 機能） |
| 9 | `.claude/agents/code-reviewer.md` | 新規 |
| 10 | `CLAUDE.md` | 全面書き直し |

**合計**: 10 ファイル（新規 8 / 書き直し 2）

---

## v2 からの主な変更点

### クロスレビュー重大問題への対応
1. ✅ **Orchestrator は Skill として実装**（調査G で公式仕様を裏取り）
2. ✅ **`.env.example` / `CLAUDE.local.md.example` を追加**（秘匿情報管理の実用サンプル）
3. ✅ **Hooks を採用**（調査F でクロスプラットフォーム実装可能性を裏取り）

### クロスレビュー改善提案への対応
1. ✅ `rules/coding-standards.md` の `paths:` を言語拡張子に変更
2. ✅ `commit-and-pr/SKILL.md` に `gh` フォールバック注記
3. ✅ `WebFetch` を `github.com/anthropics` に絞る
4. ✅ Agent Teams は CLAUDE.md で参考情報として言及（本体には含めない）
5. ✅ JSON 検証方法を環境非依存に変更
6. ✅ `.gitignore` の `agent-memory-local/` に用途コメントを追加
7. ✅ `.gitignore` の言語別エントリにトレードオフを明記
8. ✅ 検証方法に実動作確認項目を追加

---

## 後回し論点（実装完了後に確認）

1. Git 履歴のクリーンアップ要否（初期コミットに AL 内容が残る件）
2. README.md / LICENSE の要否
3. プロジェクト名 `claude-code-base-kit` のままでよいか
4. MCP 設定のサンプル追加要否
5. output-styles サンプル追加要否
