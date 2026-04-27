# base-dev-kit-for-cc

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
.mcp.json                      # プロジェクト固有の MCP サーバー設定（グローバル MCP は ~/.claude.json で管理）
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

## MCP ポリシー

<!-- テンプレートコピー後、プロジェクトの要件に合わせて書き換えてください -->

このプロジェクト（base-dev-kit-for-cc）では MCP の利用に制限を設けない。  
Claude Code キットとしての開発・改善フェーズにおいて、各種 MCP サーバーの調査・評価・活用を積極的に行う。

#### Memory MCP（ナレッジグラフ）の参照条件

以下の場合**のみ**参照すること。それ以外（通常のコーディング・ファイル操作・Git 操作など）では参照不要：

- `C:\workspace\claude-doc-repositories` 内のリポジトリを調査する際の起点確認
- MCP・プラグインの選定・推薦・比較を行う際の調査起点確認

なお Memory MCP の検索は**部分一致文字列検索**のため、自然言語クエリは機能しない。エンティティ名・タイプ名などの具体的なキーワードで検索すること。

#### 参照対象外リポジトリ

`C:\workspace\claude-doc-repositories` に以下のリポジトリが存在するが、**MCP 選定・ツール推薦・改善提案の際は参照しないこと**：

- `anthropics/life-sciences` — 生命科学分野に特化しており、汎用キット開発には無関係

> テンプレートをコピーして別プロジェクトで使う場合は、利用を許可/禁止する MCP をここに明記すること。

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

MCP は 2 つのスコープで管理する。

| スコープ | 設定場所 | 用途 |
|---|---|---|
| グローバル（ユーザー全体） | `~/.claude.json` の `mcpServers` | 全プロジェクトで共通利用するサーバー |
| プロジェクト固有 | `.mcp.json` の `mcpServers` | このプロジェクト専用のサーバー |

グローバル MCP をプロジェクトごとに有効/無効にする場合は `~/.claude.json` の該当プロジェクトエントリ内の `enabledMcpjsonServers` / `disabledMcpjsonServers` で制御する。  
技術的な制御が不要な場合は、後述の **MCP ポリシー** セクションに利用可否ルールを記載する方法でも代替できる。  
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
