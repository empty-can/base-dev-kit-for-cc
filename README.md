# base-dev-kit-for-cc

Claude Code を最大限活用するための、言語中立・クロスプラットフォームな最小構成テンプレート。

## 使い方

1. このリポジトリをクローンまたはダウンロード
2. `.claude/`・`CLAUDE.md`・`.mcp.json`・`.env.example`・`.gitignore` を新規プロジェクトにコピー
3. `CLAUDE.md` の開発コマンド・コーディング規約をプロジェクトに合わせて書き換え
4. 不要なファイルを削除、必要な設定を追加

## 構成

```
.claude/
├── settings.json              # チーム共有のパーミッション・hooks 設定
├── rules/
│   └── coding-standards.md   # path-scoped コーディング規約（14言語拡張子）
├── skills/
│   ├── commit-and-pr/         # /commit-and-pr — コミット・プッシュ・PR 作成
│   └── orchestrate/           # /orchestrate — マルチエージェント協調
├── agents/
│   └── code-reviewer.md       # code-reviewer エージェント
└── output-styles/
    └── code-review.md         # コードレビュー出力フォーマット定義
CLAUDE.md                      # Claude へのプロジェクト説明（毎セッション自動ロード）
.mcp.json                      # MCP サーバー設定
.env.example                   # 環境変数テンプレート
```

## 含まれるもの

### Skills（スラッシュコマンド）

| コマンド | 説明 |
|---|---|
| `/commit-and-pr` | 変更をコミットして PR を作成 |
| `/orchestrate` | 複数エージェントを協調させる（並列調査・段階的処理・役割分担） |

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

MCP サーバーの起動には Node.js（v18 以上）が必要です。  
GitHub MCP の認証には `GITHUB_TOKEN` 環境変数（OS レベルで設定）が必要です。

## 動作環境

- [Claude Code](https://claude.ai/code) CLI
- Node.js v18 以上（MCP サーバー用）
- Git

## ライセンス

[MIT](LICENSE)
