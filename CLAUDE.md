# claude-code-base-kit

Claude Code を最大限活用するための、言語中立・クロスプラットフォームな最小構成テンプレート。
新規プロジェクトにコピーして各セクションをプロジェクトに合わせて書き換えて使う。

---

## ディレクトリ構造

```
.claude/
├── settings.json              # チーム共有のパーミッション・hooks 設定
├── settings.local.json        # 個人用ローカル設定（.gitignore 対象）
├── rules/
│   └── coding-standards.md   # path-scoped コーディング規約（コードファイルのみロード）
├── skills/
│   ├── commit-and-pr/         # /commit-and-pr — コミット・プッシュ・PR 作成
│   └── orchestrate/           # /orchestrate — マルチエージェント協調
└── agents/
    └── code-reviewer.md       # code-reviewer エージェント
CLAUDE.md                      # このファイル（毎セッション自動ロード）
CLAUDE.local.md                # 個人用補足指示（.gitignore 対象）
.mcp.json                      # MCP サーバー設定（anthropic-docs / context7 / fetch）
.env                           # 機密情報（.gitignore 対象）
.env.example                   # 環境変数テンプレート（リポジトリ管理）
```

---

## 開発コマンド

<!-- プロジェクトに合わせて書き換えてください -->
- Build: `<build command>`
- Test: `<test command>`
- Dev: `<dev server command>`
- Lint: `<lint command>`

---

## コーディング規約

詳細は `.claude/rules/coding-standards.md` を参照（コードファイル編集時に自動ロードされる）。

主要方針:
- 命名規則は言語慣習に従う
- コメントは「なぜそうするか」を説明する場合のみ記述
- エラーは握り潰さない
- 外部入力の境界でのみバリデーション

---

## Git ワークフロー

- ブランチ命名: `<username>/<feature-description>`（例: `alice/add-auth`）
- コミットプレフィックス: `feat:` / `fix:` / `docs:` / `refactor:` / `test:`
- コミット前にテスト実行
- `/commit-and-pr` スキルでコミット・プッシュ・PR 作成を一括実行できる

---

## マルチエージェント戦略

### Skills（メインセッションで実行）

| コマンド | 用途 |
|---|---|
| `/commit-and-pr` | 変更をコミットして PR を作成 |
| `/orchestrate` | 複数エージェントを協調させる（並列調査・段階的処理・役割分担） |

### Sub-agents（隔離コンテキストで実行）

| エージェント | 用途 |
|---|---|
| `code-reviewer` | コード変更の品質・セキュリティ・保守性レビュー |

**注意**: Sub-agent から別の Sub-agent を呼び出すことは公式仕様上不可能。
マルチエージェント協調は必ず `/orchestrate` スキル（メインセッション実行）を使う。

---

## 重要な制約

- `.env` ファイルを直接編集しない。環境変数は実行環境から参照する
- API キー・パスワード等の機密情報をコードにハードコードしない
- `secrets/` ディレクトリは `.gitignore` で除外済み
- DB マイグレーション等の破壊的操作は必ず確認を取ってから実行する

---

## 拡張オプション

以下はデフォルト無効。必要に応じて有効化してください。

### Sandbox モード（コード実行の隔離）
`.claude/settings.json` の `sandbox: true` で有効化。
詳細: https://code.claude.com/docs/en/security

### MCP サーバー接続
`.mcp.json` に設定済み（anthropic-docs / context7 / fetch）。
追加サーバーは `.mcp.json` の `mcpServers` セクションに追記し、`settings.json` の `enabledMcpjsonServers` に名前を追加する。
詳細: https://code.claude.com/docs/en/mcp

### output-styles（出力フォーマット統一）
`.claude/output-styles/code-review.md` に設定済み。
追加スタイルは `.claude/output-styles/<name>.md` に定義する。

### Agent Teams（実験的）
環境変数 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` で有効化。
複数エージェントをチームとして動作させる機能。現在実験段階のため本番利用は非推奨。
詳細: https://code.claude.com/docs/en/agent-teams

### Plugin 化
複数プロジェクトで設定を共有する場合は `.claude/` を Plugin として切り出す。
個人用途は standalone（このテンプレートの構成）で十分。
詳細: https://code.claude.com/docs/en/plugins
