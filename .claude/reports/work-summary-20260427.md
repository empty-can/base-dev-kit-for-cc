# 作業レポート 2026-04-27（統合版）

**作成**: Sonnet 4.6 + Opus 4.7 の議論を Sonnet 4.6 が統合・再構成  
**議論全記録**: `work-report-20260427.md`

---

## 本日の作業概要

| # | 作業 | 成果物 |
|---|------|--------|
| 1 | `claude-doc-repositories` 目次走査・Memory MCP 登録 | `doc-repos-index-20260427.md`、Memory MCP に 32 エンティティ（MCPServer×7、Announcement×3、ClaudePlugin×22） |
| 2 | 推奨 MCP・プラグイン調査 | `recommended-mcp-and-plugins-20260427.md` |
| 3 | `settings.local.json` パーミッション整備 | allow 配列に 40+ 件追加（Read / Bash / WebSearch / WebFetch / Write / Edit / MCP ツール群） |

---

## 主要発見事項

- **MCP アーカイブ化の波**: GitHub / Sentry / Slack / PostgreSQL 等が公式リポジトリからアーカイブ済み。各ベンダー公式リポジトリへ移管。最新版は直接ベンダーリポジトリを参照すること
- **公式 Registry の存在**: `https://registry.modelcontextprotocol.io/` が MCP サーバーの公式ディレクトリとして機能。サードパーティ MCP 探索の主要な起点
- **`security-guidance` プラグインの不在**: Anthropic 推奨リストに記載があるが `claude-plugins-official` に実体なし（未リリースと推定）
- **`claude-code-setup` の高い活用価値**: `hooks-patterns` / `mcp-servers` / `plugins-reference` / `skills-reference` / `subagent-templates` の参照ドキュメントを内包。本キット改善の直接的情報源

---

## 次のアクション（最終優先順位）

### 優先度：高

**C. 公式 Registry 走査**（最優先）

Registry を起点とすることで調査の網羅性と再現性が担保される。後続の B（個別サーバー調査）も Registry 内で多くが吸収可能なため、先に実施する方が効率的。

- `registry.modelcontextprotocol.io` を走査し、セキュリティ・テスト自動化・AI/ML 等のカテゴリを補完

**B. アーカイブ済みサーバーの後継確認**（C の直後・C で見つからなかった分のみ）

Registry は申請ベースであり、ベンダー独自配布のみで未登録のサーバーが存在する（Sentry MCP 等）。C で吸収できない残件として保持が必要。

- Registry 未登録サーバーを推薦する場合の品質基準: GitHub Stars 1000+ / 週次ダウンロード 1000+ / 直近 3ヶ月のメンテナンス活動 / 公式ベンダー管理下の証跡

**A. `claude-code-setup` 評価・導入検討**

- `hooks-patterns.md` を先読みしてから実施することで手戻りを防ぐ
- `claude-automation-recommender` スキルを実行し、推薦内容と本キット現状のギャップを確認
- 推薦結果を丸呑みせず「本キットが意図的に外したもの」の判断基準を明文化しながら進める

### 優先度：中

**D. インデックス設計（エンティティ設計書 + 検索ユースケース整理）**

Memory MCP の検索は部分一致のみ。引き出し精度は「要約品質」よりも「キーワード設計」に依存するため、先にユースケースを整理してからでないと要約スクリプトの実装が機能しない。

- Memory MCP エンティティ型・命名規則・観察書式・関係命名の設計書を作成（詳細は後述「改善課題 5」）
- 検索ユースケースを整理して引き出し精度を検証
- 元提案 E（Haiku + MCP SDK 要約スクリプト）はこの中に包含: D 完了後に「キーワード設計に基づく自動要約パイプライン」として実施

**G. `commit-and-pr` スキル見直し**

- `commit-commands` プラグインの内部実装を読んで PR テンプレ・ブランチ命名 hook 等の差分を比較した上で判断する

### セキュリティ補強（`security-guidance` 代替 + 元提案 F を統合）

プラグインの到着を待たず以下の組み合わせで代替する:

| 着手順 | 手段 | 備考 |
|--------|------|------|
| 1 | `hooks-patterns.md` 先読み（A の前に実施） | フック実装パターンの正解を把握してから実装に入る |
| 2 | `Bash` 監視 PreToolUse hook（危険コマンド検出） | `rm -rf /`・`curl \| sh`・`chmod 777` 等を `decision: "deny"` で遮断。Anthropic 公式の `bash-command-validator-example` を参考に実装 |
| 3 | `Edit`/`Write` 監視 PreToolUse hook（機密パターン検出） | API キー文字列・`.env` 直接編集・`secrets/` 配下への書き込みを遮断 |
| 4 | `pr-review-toolkit` / `code-review` にセキュリティ観点を追加 | PR レビュー時のセキュリティカバレッジ |
| 5 | `.claude/rules/security-checklist.md` 新設 | OWASP Top 10 対応の禁止事項リスト（path-scoped ロードでコード編集時のみ参照） |

**hookify の利用制限**: hookify は自然言語生成のため false negative リスクがある。セキュリティガード hook のプロトタイピングには使えるが、本採用前に必ず手動レビュー・固定化を行うこと。

---

## 本キット固有の改善課題

### 1. ユースケース（使われ方シナリオ）の未定義

「丸ごとコピー」「部分取り込み」「Plugin 化配布」のどのパターンを想定するかが文書化されていない。これによって何を含めるべきかが変わる（言語別 LSP の扱い、Plugin 化に必要なスキャフォールド等）。**機能追加・削除の判断を行う前に先行して文書化すること**。

### 2. キット / 開発ナレッジ / 個人作業ログの 3 層分離

今回生成した調査レポートが `.claude/reports/` に混在しているが、これらは本キットの一部ではなくキット開発のための成果物。現状このまま利用者がキットをコピーすると不要なリサーチ成果物も混入する。

| 層 | 推奨配置先 | 内容 |
|---|------|------|
| キット本体（利用者向け） | `.claude/` 配下テンプレート | 汎用設定・スキル・hooks |
| キット開発ナレッジ | `claude-doc-repositories` 等の別リポジトリ | 調査レポート・Memory MCP データ |
| 個人作業ログ | `.claude/reports/`（`.gitignore` 対象） | 本日のような作業記録 |

**.gitignore の見直しが必要**（`.claude/reports/` の扱いが現状不明確）。

### 3. `settings.json` / `settings.local.json` の役割整理

現在の `settings.local.json` はキット開発専用（音声 hooks・広範な allow）に最適化されており、利用者向けのデフォルト `settings.json` が空のまま。また PowerShell 依存・音声通知 hooks は CI/CD（Linux ランナー）で動かない。

- `.claude/settings.json`（チーム共有・CI 互換）: Windows 非依存の設定のみ。利用者向けミニマル設定テンプレートとして整備
- `.claude/settings.local.json`（個人用）: Windows ローカル向けフル構成

### 4. テスト戦略の不在

本キットはスキル・hooks・エージェントを含む「設定の実装」だが、動作確認方法が未整備。

| 対象 | 現実的なテスト方法 | 備考 |
|------|-----------|------|
| Hooks | 設計レビュー + ローカル目視確認 | CI 環境では音声デバイス・PowerShell が使用不可のため自動テスト不可。`plugin-dev` の `validate-hook-schema.sh` はスキーマ検証として参考になる |
| スキル（`commit-and-pr` / `orchestrate`） | サンプル入力 → 期待出力の回帰テスト | モック入力を定義可能なため自動化の余地あり |

### 5. Memory MCP エンティティ設計書の未整備

今回は場当たり的にエンティティ型を定義したため、後続セッションで一貫性を失うリスクがある。D の成果物として以下の設計書を作成する:

| 項目 | 推奨決定事項 |
|-----|---------|
| 型名命名規則 | PascalCase 統一（`MCPServer`・`ClaudePlugin` 等） |
| 粒度 | 1 主要概念 = 1 エンティティ |
| 観察書式 | カテゴリプレフィックス付き自然文（`[purpose]`・`[install]`・`[note]`） |
| 関係命名 | 動詞現在形・能動態（`provides`・`replaces`・`recommends`） |

### 6. 本キットの差別化軸

「Windows + 日本語の一級サポート」を明示的な差別化軸として文書化することを推奨。現状既に持っている対応要素:

| 要素 | 現状 |
|-----|------|
| 音声通知 hooks | 実装済み（`Media.SoundPlayer` + `SAPI.SpVoice`） |
| パス区切り両対応 | `settings.local.json` で `/` と `\\` 両方記載 |
| PowerShell 明示 | hooks 内で `powershell.exe` 使用 |
| `ralph-loop` | Windows 動作確認済みプラグインとして推薦可能 |

CI/CD との両立は課題 3 の 2 層分離で対応（ローカル用フル構成と CI 用最小構成の分離）。

---

## 参照元

| ファイル | 内容 |
|---------|------|
| `.claude/reports/doc-repos-index-20260427.md` | 3 リポジトリの目次走査詳細 |
| `.claude/reports/recommended-mcp-and-plugins-20260427.md` | 推奨 MCP・プラグイン詳細リスト |
| `.claude/reports/work-report-20260427.md` | Sonnet↔Opus 全議論経緯（本ファイルの原文） |
