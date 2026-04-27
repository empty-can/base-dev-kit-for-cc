# claude-doc-repositories 目次走査レポート

**作成日**: 2026-04-27  
**対象**: `C:\workspace\claude-doc-repositories` 配下の3リポジトリ  
**走査手法**: `find` + `grep "^#"` による `.md` ファイル見出し抽出

---

## 1. anthropics/claude-ai-mcp

**概要**: Claude.ai の MCP 統合に関する公式情報・アナウンス管理リポジトリ

### ファイル構成

```
README.md          — Claude.ai MCP Integration の概要
SECURITY.md        — セキュリティポリシー
drafts/            — MCP 仕様変更のアナウンスドラフト (3件)
```

### README.md の構成

| 見出し | 内容 |
|--------|------|
| How to Stay Updated | 更新情報の追い方 |
| Report a Bug or Request a Feature | バグ報告・機能要望 |
| What This Covers | カバー範囲 |
| What This Does NOT Cover | カバー外 |
| Resources | 参考リンク |

### drafts/ — アナウンスドラフト一覧

| ファイル | タイトル | 概要 |
|----------|---------|------|
| `announcement-sse-deprecation.md` | Streamable HTTP recommended | SSE トランスポートが非推奨に。新規サーバーは Streamable HTTP を使用すること |
| `announcement-session-changes.md` | Reduced MCP session initialization overhead | セッション初期化オーバーヘッドの削減 |
| `announcement-auth-server-metadata-fallback-deprecation.md` | Removal of path-aware auth_server_metadata fallback | PRM なしでのパス対応 auth_server_metadata フォールバック廃止。PRM を使用するよう変更が必要 |

**注目点**: SSE トランスポートの廃止 + Streamable HTTP 移行は、MCP サーバー開発者が対応を要する変更。

---

## 2. modelcontextprotocol/servers

**概要**: MCP リファレンス実装サーバー群のモノレポ

### ディレクトリ構成

```
src/
├── everything/      — 全 MCP プロトコル機能を実装したリファレンス/テストサーバー
├── fetch/           — URL フェッチ・Markdown 変換
├── filesystem/      — ファイルシステムアクセス（アクセス制御付き）
├── git/             — Git リポジトリ操作
├── memory/          — ナレッジグラフ永続化
├── sequentialthinking/ — 段階的思考・分岐
└── time/            — 現在時刻・タイムゾーン変換
```

### サーバー詳細

| サーバー | 言語 | 主要ツール | 用途 |
|---------|------|-----------|------|
| **fetch** | Python | `fetch` | URL→Markdown変換。robots.txt/user-agent/proxy対応 |
| **filesystem** | TypeScript | `read_file`, `write_file`, `edit_file`, `list_directory`, `create_directory`, `move_file`, `search_files` | ディレクトリアクセス制御付きファイル操作 |
| **git** | Python | `git_status`, `git_diff`, `git_log`, `git_commit`, `git_add`, `git_branch`, `git_checkout` ほか | Git 操作一式 |
| **memory** | TypeScript | `create_entities`, `create_relations`, `add_observations`, `delete_*`, `read_graph`, `search_nodes` | ナレッジグラフ永続化。検索は部分一致のみ（ベクトル検索なし） |
| **sequentialthinking** | TypeScript | `sequential_thinking` | 思考ステップの構造化。分岐・修正対応 |
| **time** | Python | `get_current_time`, `convert_time` | タイムゾーン対応の現在時刻・変換 |
| **everything** | TypeScript | 多数 | 全 MCP プロトコル機能の参照実装。開発・テスト用 |

#### everything サーバーの詳細 (開発者向け)

`src/everything/docs/` 配下に詳細ドキュメントあり:

| ドキュメント | 内容 |
|------------|------|
| `architecture.md` | 高レベル設計・マルチクライアント対応 |
| `features.md` | Tools/Prompts/Resources/Subscriptions/Logging/Tasks/Elicitation |
| `extension.md` | ツール・プロンプト・リソースの追加方法 |
| `how-it-works.md` | 条件付きツール登録・Resource Subscriptions の実装 |
| `startup.md` | 起動プロセス（Launcher → TransportManager → ServerFactory） |
| `structure.md` | ディレクトリ構造 |
| `instructions.md` | Server Instructions の例 |

**注目点**: `everything` サーバーは MCP プロトコル実装者にとって参照実装として有用。Tasks (SEP-1686)、Elicitation など最新機能も実装済み。

---

## 3. anthropics/claude-plugins-official

**概要**: Claude Code 公式プラグインのリポジトリ。内部プラグイン32件 + 外部プラグイン5件

### 内部プラグイン (plugins/)

#### 開発ツール系

| プラグイン | コマンド/スキル | 概要 |
|-----------|---------------|------|
| **plugin-dev** | `/plugin-dev:create-plugin` | プラグイン開発ツールキット。7スキル構成（hook-development, mcp-integration, plugin-structure, plugin-settings, command-development, agent-development, skill-development）+ 3エージェント |
| **mcp-server-dev** | スキル群 | MCP サーバー・アプリ開発支援。Cloudflare Workers デプロイ、認証、Elicitation 参照ドキュメント付き |
| **agent-sdk-dev** | `/new-sdk-app` | Agent SDK プロジェクトのスキャフォールディング（TypeScript/Python）と自動検証 |
| **hookify** | `/hookify` + `/configure` + `/list` | 自然言語でフック設定・管理。条件式、演算子参照、有効/無効切り替え対応 |
| **skill-creator** | スキル | 新スキル作成ツール（analyzer/comparator/grader の3エージェント） |
| **example-plugin** | — | プラグインスキャフォールド・テンプレート |

#### Git ワークフロー系

| プラグイン | コマンド | 概要 |
|-----------|---------|------|
| **commit-commands** | `/commit`, `/commit-push-pr`, `/clean_gone` | コミット・PR 作成・stale ブランチ削除の自動化 |

#### コード品質系

| プラグイン | コマンド | 概要 |
|-----------|---------|------|
| **code-review** | `/code-review` | PR コードレビュー（4並列エージェント、信頼度スコアリング、GitHub コメント自動投稿） |
| **pr-review-toolkit** | `/review-pr` | PR レビューツールキット（6エージェント: comment-analyzer, pr-test-analyzer, silent-failure-hunter, type-design-analyzer, code-reviewer, code-simplifier） |

#### 開発ワークフロー系

| プラグイン | コマンド | 概要 |
|-----------|---------|------|
| **feature-dev** | `/feature-dev` | 7フェーズ機能開発ワークフロー（Discovery → Exploration → Clarifying → Architecture → Implementation → Quality Review → Summary）。3エージェント連携 |
| **ralph-loop** | `/ralph-loop`, `/cancel-ralph` | Stop フック利用の自律反復ループ。完了条件を満たすまで自動継続。Windows 対応 |

#### 設定・自動化系

| プラグイン | コマンド/スキル | 概要 |
|-----------|--------------|------|
| **claude-code-setup** | スキル: `claude-automation-recommender` | Claude Code の最適設定（hooks/MCPs/plugins/skills）を推薦。参照ドキュメント: hooks-patterns, mcp-servers, plugins-reference, skills-reference, subagent-templates |
| **claude-md-management** | `/revise-claude-md`, スキル: `claude-md-improver` | CLAUDE.md の品質改善・維持 |

#### 出力スタイル系

| プラグイン | 概要 |
|-----------|------|
| **explanatory-output-style** | 詳細解説型の出力スタイル。Hooks と系統的な説明を組み合わせ |
| **learning-output-style** | インタラクティブ学習モード。Claude がユーザーからの補足情報を能動的に求める |

#### その他

| プラグイン | 概要 |
|-----------|------|
| **frontend-design** | フロントエンド/UI デザイン支援スキル |
| **math-olympiad** | 数学オリンピック問題の解法（検証・提示のリファレンス多数） |
| **playground** | 6種テンプレート（code-map, concept-map, data-explorer, design-playground, diff-review, document-critique）を使った実験的分析 |
| **session-report** | セッションサマリーレポート生成スキル |

#### LSP プラグイン (12言語)

`clangd-lsp`（C/C++）、`csharp-lsp`（C#）、`gopls-lsp`（Go）、`jdtls-lsp`（Java）、`kotlin-lsp`（Kotlin）、`lua-lsp`（Lua）、`php-lsp`（PHP）、`pyright-lsp`（Python）、`ruby-lsp`（Ruby）、`rust-analyzer-lsp`（Rust）、`swift-lsp`（Swift）、`typescript-lsp`（TypeScript）

各プラグインは対応言語サーバーのセットアップと拡張子の登録を行う薄いラッパー。

---

### 外部プラグイン (external_plugins/)

| プラグイン | 概要 | 備考 |
|-----------|------|------|
| **discord** | Discord DM・チャンネルへの送受信 | アクセス制御・添付ファイル対応 |
| **telegram** | Telegram メッセージ送受信 | 写真対応、履歴・検索なし |
| **imessage** | iMessage 送受信 | macOS 専用 |
| **greptile** | Greptile API 経由の AI コードレビュー | API キー要 |
| **fakechat** | チャットシミュレーション（実チャンネルではない） | テスト・デモ用途 |

---

## Memory MCP への登録サマリー

本走査の結果、以下をナレッジグラフに登録済み:

| エンティティタイプ | 登録数 | 主なエンティティ名 |
|-----------------|--------|-----------------|
| `MCPServer` | 7 | mcp-server-fetch, mcp-server-filesystem, mcp-server-git, mcp-server-memory, mcp-server-sequentialthinking, mcp-server-time, mcp-server-everything |
| `Announcement` | 3 | announcement-sse-deprecation, announcement-session-changes, announcement-auth-metadata-deprecation |
| `ClaudePlugin` | 22 | plugin-dev, mcp-server-dev, agent-sdk-dev, hookify, ralph-loop, commit-commands, code-review, pr-review-toolkit, feature-dev, claude-code-setup, claude-md-management, lsp-plugins-bundle, explanatory-output-style, learning-output-style, frontend-design, math-olympiad, playground, skill-creator, session-report, external-plugin-discord, external-plugin-telegram, external-plugin-imessage, external-plugin-greptile, external-plugin-fakechat |

---

## 注目すべき情報

1. **SSE トランスポート廃止**: `claude-ai-mcp/drafts/` に MCP サーバーの SSE→Streamable HTTP 移行を促すアナウンスドラフトが存在。現在 SSE 使用中の MCP サーバー作成者は対応が必要。

2. **`claude-code-setup` プラグイン**: hooks-patterns / mcp-servers / plugins-reference / skills-reference / subagent-templates の参照ドキュメントを内包しており、**このキット (`base-dev-kit-for-cc`) の改善情報源として最有力**。

3. **`plugin-dev` の hook-development スキル**: `validate-hook-schema.sh` / `test-hook.sh` / `hook-linter.sh` の3スクリプト付き。フック設計の品質向上に活用可能。

4. **`ralph-loop`**: Stop フックを利用した自律反復ループ。Claude が完了条件を満たすまで自動継続する仕組みで、Windows でも動作確認済み。本キットのフック設計に参考になる可能性あり。
