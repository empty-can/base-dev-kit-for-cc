# 調査D: Anthropic 公式リポジトリ横断調査

## 調査概要

**調査目的**: Claude Code ベースキット作成のための先行事例調査

**調査対象**: Anthropic 組織の公開リポジトリ 8 件

**実施日**: 2026-04-24

## 調査対象リポジトリ一覧

| リポジトリ | `.claude/` 有無 | 主要言語 | 目的 |
|---|---|---|---|
| anthropics/claude-code | ✓ | Shell/Python/TypeScript | Claude Code 本体・ツール |
| anthropics/anthropic-cookbook | ✓ | Jupyter/Python | API 使用例・レシピ集 |
| anthropics/claude-code-action | ✓ | TypeScript | GitHub Actions 統合 |
| anthropics/prompt-eng-interactive-tutorial | ✗ | Jupyter | 学習用コース |
| anthropics/courses | ✗ | Jupyter | 教育用コース |
| anthropics/anthropic-sdk-python | ✗ | Python | API SDK |
| anthropics/anthropic-sdk-typescript | ✗ | TypeScript | API SDK |
| anthropics/skills | ✗ | Markdown | Agent Skills リポジトリ |

## 各リポジトリの構成詳細

### anthropics/claude-code

```
.claude/
└── commands/
    ├── commit-push-pr.md      (795 bytes)
    ├── dedupe.md              (1,701 bytes)
    └── triage-issue.md        (5,550 bytes)
```

**注目点**: Slash Commands のみの実装。agents / skills は未使用。

### anthropics/anthropic-cookbook

```
.claude/
├── agents/
│   └── code-reviewer.md
├── commands/
│   ├── add-registry.md        (2,450 bytes)
│   ├── link-review.md         (1,477 bytes)
│   ├── model-check.md         (906 bytes)
│   ├── notebook-review.md     (673 bytes)
│   ├── review-issue.md        (6,831 bytes)
│   ├── review-pr.md           (2,936 bytes)
│   └── review-pr-ci.md        (2,850 bytes)
└── skills/
    └── cookbook-audit/
        └── style_guide.md
```

**注目点**: agents + commands + skills をフル活用。もっとも包括的な実装例。

**code-reviewer.md の責務**:
- Python・Jupyter ベストプラクティスのレビュー
- プロジェクト固有の規約チェック（100 文字行長、double quote、uv add 等）
- Critical / Important / Suggestion の重大度付きフィードバック

**review-pr.md のプロセス**:
1. `gh pr checkout` でブランチ切り替え
2. `gh pr view` ・`gh pr diff` でコンテキスト取得
3. code-reviewer エージェント呼び出し
4. 構造化フィードバック生成
5. ユーザー確認後に GitHub 投稿

**CLAUDE.md の内容（確認済み）**:
- Development Workflow（`uv sync`, `make format/lint/test`, 100 文字行長）
- Critical Guidelines（モデル名の非日付版使用、`.env` 非 commit、`uv add` で依存管理）

### anthropics/claude-code-action

```
.claude/
├── agents/       (空または最小限)
├── commands/     (空または最小限)
└── settings.json (231 bytes)
```

**settings.json の内容**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bun run format"
          }
        ],
        "matcher": "Edit|Write|MultiEdit"
      }
    ]
  }
}
```

**注目点**: PostToolUse フックで自動フォーマッティング。Bun ベース。

## 共通パターンの抽出

### パターン1: `.claude/commands/` の標準採用 — 3/3 リポジトリ（100%）
- 全リポジトリで Slash Commands を実装
- Markdown 形式
- 命名は kebab-case

### パターン2: `.claude/agents/` の準備 — 2/3 リポジトリ（67%）
- anthropic-cookbook: 実装済み（code-reviewer.md）
- claude-code-action: ディレクトリのみ（空）
- Sub-agents は準備されるが、実装は選択的

### パターン3: Hooks の段階的採用 — 1/3 リポジトリ（確認済み）
- claude-code-action で PostToolUse（自動フォーマット）
- 他リポジトリは settings.json が取得困難で未確認

### パターン4: settings.json の最小構成
- claude-code-action の例は 231 bytes のみ（hooks のみ）
- 必要最小限の設定に留める傾向

### パターン5: Skills の実装例 — 1/3 リポジトリ（33%）
- anthropic-cookbook の cookbook-audit/style_guide.md
- 実装例はまだ少ない

## `.claude/` を持たないリポジトリの特徴

| リポジトリ | 理由（推測） |
|---|---|
| courses, tutorial | 学習教材（Claude Code 実行前提なし） |
| SDK 系 | API SDK（開発プロセスは従来のツール） |
| skills | Skills Marketplace（対象が別） |

## ベースキット採用候補パターンの推奨

| パターン | 推奨度 | 根拠 |
|---|---|---|
| `.claude/commands/` ディレクトリ構造 | **必須** | 全 3 リポジトリ採用（100%） |
| `.claude/settings.json` 基本構成 | **必須** | 全リポジトリで確認・言語中立 |
| `.claude/agents/` ディレクトリの準備 | **推奨** | 2 リポジトリ（67%）、実装例あり |
| Slash Commands テンプレート | **推奨** | 複数リポジトリで活用・実用的 |
| PostToolUse フック | **推奨** | 1 リポジトリで実装、言語依存 |
| Sub-agents テンプレート（code-reviewer） | **推奨** | 実装例あり、汎用性高 |
| Skills テンプレート | **推奨** | 実装例あり、用途次第 |
| CLAUDE.md の標準テンプレート | **必須** | すべてのリポジトリで存在 |

## 設計推奨事項

### 最小限ベースキット構成（必須要素）
```
.claude/
├── settings.json
└── commands/
    └── sample-command.md
CLAUDE.md
```

### 推奨構成（実用サンプル含む）
```
.claude/
├── settings.json
├── agents/
│   └── code-reviewer.md
├── commands/
│   └── review-pr.md
└── skills/
    └── sample-skill/
        └── SKILL.md
CLAUDE.md
CLAUDE.local.md  (gitignore)
```

## 補足

本調査で GitHub Web UI 経由では取得困難だった情報：
- 各リポジトリの settings.json の完全内容（一部のみ確認済み）
- CLAUDE.md の完全内容（anthropic-cookbook 以外）

これらは実装段階で追加確認可能。
