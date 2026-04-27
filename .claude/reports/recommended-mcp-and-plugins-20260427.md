# 導入推奨 MCP サーバー・プラグイン調査レポート

**作成日**: 2026-04-27  
**情報源**:
- `claude-plugins-official/plugins/claude-code-setup/skills/claude-automation-recommender/references/mcp-servers.md`（Anthropic 公式推奨リスト）
- `claude-plugins-official/plugins/claude-code-setup/skills/claude-automation-recommender/references/plugins-reference.md`（Anthropic 公式プラグイン推奨リスト）
- `modelcontextprotocol/servers/README.md`（リファレンスサーバー一覧・Registry 案内）

---

## MCP サーバー推奨一覧

> **公式 Registry**: https://registry.modelcontextprotocol.io/  
> 最新の MCP サーバー一覧はこちらで検索可能。

### ドキュメント・ナレッジ

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **context7** | ★★★ 汎用推奨 | ライブラリ・SDK 使用時は常に | ライブデキュメント取得。ハルシネーション低減 |

### ブラウザ・フロントエンド

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **Playwright MCP** | ★★★ | React/Vue/Angular・E2E テスト | ブラウザ操作・スクリーンショット・フォームテスト |
| **Puppeteer MCP** | ★★ | PDF 生成・スクレイピング・ヘッドレスCI | ヘッドレスブラウザ自動化（注: 公式リポジトリはアーカイブ済み） |

### データベース

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **Supabase MCP** | ★★★ | Supabase プロジェクト使用時 | テーブル操作・認証・ストレージ |
| **PostgreSQL MCP** | ★★ | 生 PostgreSQL 使用時 | スキーマ管理・データ分析・デバッグ（注: 公式リポジトリはアーカイブ済み） |
| **Neon MCP** | ★★ | Neon サーバーレス Postgres 使用時 | エッジ向け Postgres 操作 |
| **Turso MCP** | ★ | Turso/libSQL 使用時 | エッジ SQLite 操作 |

### バージョン管理・DevOps

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **GitHub MCP** | ★★★ 汎用推奨 | GitHub リポジトリ使用時は常に | Issue・PR・Actions・リリース管理 |
| **GitLab MCP** | ★★ | GitLab リポジトリ使用時 | プロジェクト管理（注: 公式リポジトリはアーカイブ済み） |
| **Linear MCP** | ★★ | Linear でイシュー管理時 | スプリント・バックログ・イシュー連携 |

### クラウドインフラ

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **AWS MCP** | ★★★ | `@aws-sdk/*` 使用・IaC 開発時 | Lambda・S3・DynamoDB・CDK/Terraform 操作 |
| **Cloudflare MCP** | ★★ | Cloudflare Workers/Pages/R2/D1 使用時 | エッジ関数・ストレージ・SQLite 操作 |
| **Vercel MCP** | ★★ | Vercel デプロイ使用時 | デプロイ・設定管理 |

### モニタリング・オブザーバビリティ

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **Sentry MCP** | ★★★ | Sentry 導入プロジェクト | エラー調査・根本原因分析（注: 公式リポジトリはアーカイブ済み） |
| **Datadog MCP** | ★★ | Datadog 使用時 | APM・ログ・メトリクス |

### コミュニケーション

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **Slack MCP** | ★★ | チームで Slack 使用時 | 通知・デプロイ通知・インシデント対応（注: 公式リポジトリはアーカイブ済み、Zencoder 版に移行）|
| **Notion MCP** | ★★ | Notion でドキュメント管理時 | ページ読み書き・ナレッジベース検索 |

### ファイル・データ

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **Filesystem MCP** | ★★★ 汎用推奨 | 複雑なファイル操作が必要な場合 | バッチ処理・ファイル監視・高度な検索 |
| **Memory MCP** | ★★★ 汎用推奨 | 長期プロジェクト・文脈保持が必要な場合 | セッション横断の記憶・ナレッジグラフ |

### コンテナ・DevOps

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **Docker MCP** | ★★ | Docker Compose/Dockerfile 使用時 | コンテナ管理・ログ・デバッグ |
| **Kubernetes MCP** | ★★ | K8s マニフェスト・Helm 使用時 | Pod デプロイ・スケーリング・クラスタデバッグ |

### AI・リサーチ

| サーバー | 推奨度 | 推奨条件 | 用途 |
|---------|--------|---------|------|
| **Exa MCP** | ★★ | リサーチ・競合調査・最新情報収集時 | AI 向け最適化 Web 検索 |

---

## リファレンス実装サーバー（modelcontextprotocol/servers）

公式リポジトリが提供する**教育・参考用**の実装。本番利用より学習用途向け。

| サーバー | 用途 |
|---------|------|
| everything | 全 MCP 機能を実装したテスト用参照サーバー |
| fetch | URL フェッチ → Markdown 変換 |
| filesystem | ディレクトリアクセス制御付きファイル操作 |
| git | Git リポジトリ操作 |
| memory | ナレッジグラフ永続化 |
| sequentialthinking | 段階的思考・分岐・修正 |
| time | 現在時刻・タイムゾーン変換 |

> ⚠️ 以下は公式リポジトリからアーカイブ済み（別リポジトリに移管または後継あり）:  
> GitHub, GitLab, PostgreSQL, Puppeteer, Redis, Sentry, Slack, SQLite, Brave Search, Google Drive, Google Maps

---

## プラグイン（Anthropic 公式）推奨一覧

### 開発・コード品質

| プラグイン | 推奨度 | 用途 |
|-----------|--------|------|
| **plugin-dev** | ★★★ プラグイン作成者向け | スキル・フック・コマンド・エージェントの作成 |
| **pr-review-toolkit** | ★★★ | 特化型 PR レビュー（6エージェント） |
| **code-review** | ★★★ | 自動 PR レビュー（4並列・信頼度スコアリング） |
| **feature-dev** | ★★ | 7フェーズ機能開発ワークフロー |
| **code-simplifier** | ★★ | コードリファクタリング支援 |
| **mcp-server-dev** | ★★★ MCPサーバー開発者向け | MCP サーバー・アプリ開発支援 |

### Git・ワークフロー

| プラグイン | 推奨度 | 用途 |
|-----------|--------|------|
| **commit-commands** | ★★★ 汎用推奨 | `/commit`, `/commit-push-pr`, `/clean_gone` |
| **hookify** | ★★ | 自然言語でフック設定・管理 |
| **ralph-loop** | ★★ | Stop フック利用の自律反復ループ |

### フロントエンド

| プラグイン | 推奨度 | 用途 |
|-----------|--------|------|
| **frontend-design** | ★★ | フロントエンド/UI デザイン支援 |

### セットアップ・設定管理

| プラグイン | 推奨度 | 用途 |
|-----------|--------|------|
| **claude-code-setup** | ★★★ 新規セットアップ時 | hooks/MCPs/plugins/skills の最適設定推薦 |
| **claude-md-management** | ★★ | CLAUDE.md の品質改善 |

### 学習・ガイダンス

| プラグイン | 推奨度 | 用途 |
|-----------|--------|------|
| **explanatory-output-style** | ★★ | 詳細解説型出力（学習・オンボーディング） |
| **learning-output-style** | ★★ | インタラクティブ学習モード |
| **security-guidance** | ★★★ セキュリティ要件がある場合 | セキュリティ問題の警告（編集時） |

> ⚠️ `security-guidance` は `plugins-reference.md` に記載があるが、現在の `claude-plugins-official` リポジトリには見当たらない（未リリースまたは別名の可能性）

### LSP プラグイン（言語別）

| プラグイン | 言語 | 推奨条件 |
|-----------|------|---------|
| typescript-lsp | TypeScript/JavaScript | TS プロジェクト |
| pyright-lsp | Python | Python プロジェクト |
| gopls-lsp | Go | Go プロジェクト |
| rust-analyzer-lsp | Rust | Rust プロジェクト |
| clangd-lsp | C/C++ | C/C++ プロジェクト |
| jdtls-lsp | Java | Java プロジェクト |
| kotlin-lsp | Kotlin | Kotlin プロジェクト |
| swift-lsp | Swift | Swift プロジェクト |
| csharp-lsp | C# | C# プロジェクト |
| php-lsp | PHP | PHP プロジェクト |
| lua-lsp | Lua | Lua プロジェクト |

---

## クイックリファレンス：プロジェクト特性 → 推奨 MCP

| プロジェクト特性 | 推奨 MCP |
|----------------|---------|
| 人気ライブラリ使用 | context7 |
| GitHub リポジトリ | GitHub MCP |
| フロントエンド開発 | Playwright MCP |
| Supabase 使用 | Supabase MCP |
| AWS 使用 | AWS MCP |
| Sentry 導入 | Sentry MCP |
| Docker/Compose 使用 | Docker MCP |
| Slack 使用チーム | Slack MCP |
| 長期プロジェクト | Memory MCP |
| 常時推奨 | Filesystem MCP, Memory MCP |

---

## MCP サーバーを探すための公式ディレクトリ・Registry

| サービス | URL | 特徴 |
|---------|-----|------|
| **MCP Registry（公式）** | https://registry.modelcontextprotocol.io/ | MCP 公式 Registry |
| **PulseMCP** | https://www.pulsemcp.com | コミュニティハブ・週次ニュースレター |
| **Smithery** | https://smithery.ai/ | LLM エージェント向けレジストリ |
| **Glama / Awesome MCP** | https://glama.ai/mcp/servers | punkpeye による厳選リスト |
| **mcpservers.org** | https://mcpservers.org | wong2 による厳選リスト |
| **mcp.so** | https://mcp.so | ディレクトリ |

---

## 注目事項

1. **アーカイブ化の波**: GitHub/GitLab/PostgreSQL/Puppeteer/Sentry/Slack/Brave Search など多くの人気サーバーが `modelcontextprotocol/servers` からアーカイブ済み。各サービスの公式リポジトリまたは後継プロジェクトに移管されている。

2. **`security-guidance` プラグイン**: `plugins-reference.md` に記載されているが、現在の `claude-plugins-official` リポジトリに存在を確認できなかった。未リリースの可能性。

3. **汎用的に推奨されるMCP（常時導入候補）**: context7 / GitHub MCP / Filesystem MCP / Memory MCP の4つがどのプロジェクトでも有効。

4. **`claude-code-setup` プラグイン**: プロジェクトのコードベースを自動解析して最適な MCP・プラグイン構成を推薦する機能を持つ。新規プロジェクトへのキット適用時に活用価値が高い。
