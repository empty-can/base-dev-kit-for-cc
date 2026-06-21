# base-dev-kit-for-cc

Claude Code を最大限活用するための、言語中立・クロスプラットフォームな最小構成の
**共有 `.claude/` キット（`<Share>` リポジトリ）**。

> このリポジトリ自体の説明・使い方・MCP ポリシーはこの `README.md` に集約している。
> `README.md` は `--add-dir` での参照時に**ロードされない**ため、利用先リポジトリの文脈を
> 汚さずにリポ固有情報を置ける（README 隔離方式）。チーム共通の指示は `.claude/CLAUDE.md` に
> あり、こちらは利用先にロードされることを想定している。

---

## 2 つの利用方法

### 方法 A: コピー展開（テンプレートとして）

新規プロジェクトの土台として丸ごとコピーする。

1. このリポジトリをクローンまたはダウンロード
2. `.claude/`・`.mcp.json`・`.env.example`・`.gitignore`・`CLAUDE.md.example` を新規プロジェクトにコピー
3. `CLAUDE.md.example` を `CLAUDE.md` にリネームし、プロジェクト概要・開発コマンド・MCP ポリシーを記入
4. 不要なファイルを削除、必要な設定を追加

チーム共通の規約（コーディング / Git / マルチエージェント）は `.claude/CLAUDE.md` に入っており、
コピー後もそのまま機能する。

### 方法 B: `--add-dir` でライブ参照（`<Share>` として）

日々の作業リポジトリから、このキットを**クローンせず参照だけ**して共有資産を読み込む。
本リポジトリを `<Share>` としてローカルに 1 つ置き、各作業リポジトリから次のように結合する。

| 共有したい資産 | 結合方法 |
|---|---|
| skills / subagents | `--add-dir <Share>` |
| `.claude/CLAUDE.md` / `rules/` | `--add-dir <Share>` ＋ 環境変数 `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` |
| `settings.json`（permissions / hooks 等） | `--settings <Share>/.claude/settings.json` |

```bash
# 例: 作業リポジトリのルートで
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 \
  claude --add-dir /path/to/base-dev-kit-for-cc \
         --settings /path/to/base-dev-kit-for-cc/.claude/settings.json
```

> **注意**: `commands/` 形式・`output-styles/`・hooks 単体は `--add-dir` では結合されない
> （これらを共有したい場合は方法 A のコピー展開を使う）。`settings.local.json` は個人用・
> 共有不可。ローカル全リポジトリに効かせたい個人設定は `~/.claude/settings.json` に置く。

---

## 構成

```
.claude/
├── CLAUDE.md                  # チーム共通指示（利用側にロードされる共有資産）
├── settings.json              # チーム共有のパーミッション・hooks 設定
├── rules/
│   └── coding-standards.md    # path-scoped コーディング規約（コードファイル編集時のみロード）
├── skills/
│   ├── commit-and-pr/         # /commit-and-pr — コミット・プッシュ・PR 作成
│   ├── orchestrate/           # /orchestrate — マルチエージェント協調
│   ├── request-new-skill/     # /request-new-skill — 新規 skill 依頼フロー
│   └── review-skill-request/  # /review-skill-request — skill 依頼レビュー
├── agents/
│   └── code-reviewer.md       # code-reviewer サブエージェント
├── output-styles/
│   └── code-review.md         # コードレビュー出力フォーマット定義
└── templates/
    └── skill-request/         # skill 依頼書テンプレート

CLAUDE.md.example              # 方法 A 用：プロジェクト固有 CLAUDE.md の雛形
CLAUDE.local.md.example        # 個人用補足指示の雛形（コピーして CLAUDE.local.md に）
.claude/settings.local.json.example  # 個人用ローカル設定の雛形
.mcp.json                      # プロジェクト固有の MCP サーバー設定
.env.example                   # 環境変数テンプレート
```

> `.claude/reports/`・`.claude/work/`・`.claude/workspace/`・`settings.local.json`・
> `CLAUDE.local.md` は `.gitignore` 対象で、共有ペイロードには含めない。

---

## 含まれるもの

### Skills（スラッシュコマンド）

| コマンド | 説明 |
|---|---|
| `/commit-and-pr` | 変更をコミットして PR を作成 |
| `/orchestrate` | 複数エージェントを協調させる（並列調査・段階的処理・役割分担） |
| `/request-new-skill` | 新しい skill の依頼書テンプレを生成する |
| `/review-skill-request` | skill 依頼書をレビューし実装方針をまとめる |

### Sub-agents

| エージェント | 説明 |
|---|---|
| `code-reviewer` | コード変更の品質・セキュリティ・保守性レビュー |

### MCP サーバー

| サーバー | 用途 |
|---|---|
| `anthropic-docs` | Anthropic / Claude ドキュメント検索 |
| `context7` | ライブラリドキュメント取得 |
| `fetch` | 汎用 URL 取得 |
| `github` | GitHub リポジトリ・Issue・PR の参照 |

MCP サーバーの起動には Node.js（v18 以上）が必要。GitHub MCP の認証には `GITHUB_TOKEN`
環境変数（OS レベルで設定）が必要。

#### このキット開発時の MCP ポリシー

本リポジトリ（base-dev-kit-for-cc）を**開発・改善する作業**では、MCP の利用に制限を設けない。
各種 MCP サーバーの調査・評価・活用を積極的に行う。コピー展開先のプロジェクトでは、
`CLAUDE.md` の「MCP ポリシー」セクションに利用可否を改めて記述すること。

---

## 動作環境

- [Claude Code](https://claude.ai/code) CLI
- Node.js v18 以上（MCP サーバー用）
- Git

---

## 拡張オプション

以下はデフォルト無効。必要に応じて有効化する。

### Sandbox モード（コード実行の隔離）
`.claude/settings.json` の `sandbox: true` で有効化。詳細: https://code.claude.com/docs/en/security

### MCP サーバー接続

| スコープ | 設定場所 | 用途 |
|---|---|---|
| グローバル（ユーザー全体） | `~/.claude.json` の `mcpServers` | 全プロジェクト共通のサーバー |
| プロジェクト固有 | `.mcp.json` の `mcpServers` | このプロジェクト専用のサーバー |

グローバル MCP のプロジェクト別 有効/無効は `~/.claude.json` の該当プロジェクトエントリ内
`enabledMcpjsonServers` / `disabledMcpjsonServers` で制御する。詳細: https://code.claude.com/docs/en/mcp

### output-styles（出力フォーマット統一）
`.claude/output-styles/code-review.md` に設定済み。追加は `.claude/output-styles/<name>.md` に定義する。

### Agent Teams（実験的）
環境変数 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` で有効化。現在実験段階のため本番利用は非推奨。
詳細: https://code.claude.com/docs/en/agent-teams

### Plugin 化
複数プロジェクトで設定を共有する別手段として、`.claude/` の一部を Plugin として切り出す方法もある。
詳細: https://code.claude.com/docs/en/plugins

---

## ライセンス

[MIT](LICENSE)
