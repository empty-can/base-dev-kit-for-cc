# 作業レポート 2026-04-27

---

## 本日の作業概要

Claude Code 向け開発キット（`base-dev-kit-for-cc`）の改善を目的として、以下の作業を実施した。

1. `C:\workspace\claude-doc-repositories` 配下の4リポジトリの目次走査・Memory MCP への登録
2. 導入推奨 MCP サーバー・プラグインの調査
3. `settings.local.json` のパーミッション整備

---

## 作業詳細

### 1. ドキュメントリポジトリの目次走査と Memory MCP 登録

`find` + `grep "^#"` による `.md` ファイル見出し抽出を実施。以下の3リポジトリを対象とした（`life-sciences` は対象外）。

| リポジトリ | 概要 |
|-----------|------|
| `anthropics/claude-ai-mcp` | Claude.ai MCP 統合の公式情報・アナウンス管理 |
| `anthropics/claude-plugins-official` | 公式プラグイン集（内部32件・外部5件） |
| `modelcontextprotocol/servers` | MCP リファレンス実装サーバー群（7件アクティブ）|

Memory MCP に合計 **32 エンティティ**を登録（MCPServer × 7、Announcement × 3、ClaudePlugin × 22）。

詳細: `.claude/reports/doc-repos-index-20260427.md`

---

### 2. 導入推奨 MCP・プラグイン調査

Anthropic 公式推奨リスト（`claude-code-setup` プラグインの参照ドキュメント）と `modelcontextprotocol/servers` README を情報源として調査。

#### 汎用推奨（プロジェクト種別によらず導入候補）

**MCP サーバー:**

| サーバー | 用途 |
|---------|------|
| context7 | ライブドキュメント取得（ハルシネーション低減） |
| GitHub MCP | Issue・PR・Actions・リリース管理 |
| Filesystem MCP | 高度なファイル操作 |
| Memory MCP | セッション横断の文脈保持・ナレッジグラフ |

**プラグイン:**

| プラグイン | 用途 |
|-----------|------|
| commit-commands | `/commit`, `/commit-push-pr`, `/clean_gone` |
| claude-code-setup | 最適な MCP・hooks・plugins 構成の自動推薦 |
| 言語別 LSP プラグイン | 型補完・参照・リファクタリング支援 |

#### 主要な発見事項

1. **アーカイブ化の波**: GitHub / Sentry / Slack / PostgreSQL / Puppeteer 等、多くの人気 MCP サーバーが `modelcontextprotocol/servers` からアーカイブ済みになり、各ベンダー公式リポジトリへ移管されている。最新版を使う場合は直接ベンダーリポジトリを参照すること。

2. **公式 Registry の存在**: `https://registry.modelcontextprotocol.io/` が MCP サーバーの公式ディレクトリとして機能している。サードパーティ MCP を探す際の主要な起点。

3. **`security-guidance` プラグインの不在**: Anthropic の推奨リストに記載されているが、`claude-plugins-official` リポジトリに実体が見当たらない。未リリースまたは別名の可能性あり。

4. **`claude-code-setup` の活用価値**: コードベースを自動解析して最適な Claude Code 設定を推薦するプラグイン。新規プロジェクトへ本キットを適用する際の「初期設定ガイド」として機能する可能性が高い。

詳細: `.claude/reports/recommended-mcp-and-plugins-20260427.md`

---

### 3. settings.local.json パーミッション整備

調査・開発作業を許可確認なしで進められるよう、以下を追加:

| カテゴリ | 追加内容 |
|---------|---------|
| ファイル操作 | `Read`, `Write(.claude/reports/*)`, `Edit(.claude/reports/*)`, `Edit(.claude/settings.local.json)` |
| Bash | `sort *`, `head *`, `jq *` |
| Web | `WebSearch`, `WebFetch` (github.com / mcp.so / modelcontextprotocol.io / npmjs.com / pypi.org) |
| Memory MCP | `open_nodes`, `read_graph` 追加 |
| AWS docs MCP | 4ツール全て |
| context7 | 2ツール全て |
| everything MCP | 主要4ツール |
| GitHub MCP | 読み取り系16ツール |

---

## 次のアクション提案（Sonnet より）

### 優先度：高

**A. `claude-code-setup` プラグインの評価・導入検討**  
本キットの CLAUDE.md や設定ファイルに対して `claude-code-setup` の `claude-automation-recommender` スキルを実際に動かし、推薦内容とキットの現状のギャップを確認する。特に `hooks-patterns.md`・`skills-reference.md`・`subagent-templates.md` の参照ドキュメントはキット改善の直接的な情報源になる可能性が高い。

**B. アーカイブ済みサーバーの後継確認**  
GitHub MCP・Sentry MCP・Slack MCP などアーカイブ済みサーバーについて、現在の公式インストール方法（ベンダーリポジトリ・npm パッケージ名）を確認し、推奨リストに install コマンドを補完する。

**C. 公式 Registry の走査**  
`registry.modelcontextprotocol.io` を実際に参照し、本日の調査で漏れたカテゴリ（セキュリティ・テスト自動化・AI/ML パイプライン等）のサーバーを補完する。

### 優先度：中

**D. インデックス設計の本格化**  
Memory MCP に登録したエンティティの「検索ユースケース」を整理し、どのキーワードで引けるかをテストする。現在は登録に注力したが、実際の引き出し精度の検証がまだ。

**E. 要約スクリプトの実装**  
前回セッションで検討した「Haiku モデル + MCP SDK でファイル内容を自動要約して Memory に登録するスクリプト」の実装。インデックス設計（D）完了後に着手するのが適切。

**F. `security-guidance` プラグインの所在調査**  
Anthropic 推奨リストに記載されているが実体が見当たらない。GitHub で `anthropics` 組織を検索して最新情報を確認する。

### 優先度：低

**G. 本キットへの `commit-and-pr` スキルの見直し**  
`commit-commands` プラグイン（公式）との機能重複を確認し、本キット固有のカスタマイズが必要な部分のみ残す方針を検討する。

---

## Opus への追記依頼事項（別セッションにて）

以下の観点で上記の次のアクション提案に対する意見・補足を求める:

1. **優先順位の妥当性**: 本キット（Claude Code 向け汎用開発キット）の目的に照らして、A〜G の優先順位付けは適切か
2. **見落としている視点**: 今回の調査・提案で見逃している重要な観点や追加すべきアクションはあるか
3. **`security-guidance` の代替**: プラグインが存在しない場合、セキュリティ関連の推奨設定をどう補うべきか

---

*本レポートは Sonnet 4.6 が作成。以下に Opus 4.7 による追記。*

---

## Opus 4.7 による追記

Sonnet 4.6 が提案した A〜G に対する評価と、見落とし視点・`security-guidance` 代替案を以下に記す。

### 1. 優先順位の妥当性評価

**結論**: 大筋は妥当。ただし B と C の順序入れ替え、D の格上げ、E・F・G の整理が望ましい。

| 提案 | Sonnet優先度 | Opus評価 | コメント |
|------|------------|---------|---------|
| **A. `claude-code-setup` 評価** | 高 | **高（同意）** | 本キットは「Claude Code 設定の参照実装」を志向する以上、公式推薦エンジンを通すことがキットの正解性チェックそのもの。ただし推薦結果を丸呑みせず、「本キットが意図的に外したもの」を明文化する判断軸を先に作るべき（例: 言語別 LSP は言語決定後でよい / `claude-md-management` は本キット CLAUDE.md とのコンフリクト確認が先） |
| **B. アーカイブ後継確認** | 高 | **中に降格** | 単独で走らせると個別サーバーごとに調査が発散する。C を先に実施すれば Registry 内で多くの後継が見つかるはず |
| **C. 公式 Registry 走査** | 高 | **最高優先** | 「公式 Registry を起点とする」調査ルートを確立してから個別サーバーに当たる方が網羅性・再現性ともに高い。B はこの中で吸収可能 |
| **D. インデックス検索ユースケース整理** | 中 | **高に格上げ** | Memory MCP の検索が部分一致のみという制約は既に判明済み。「使えない検索を抱えたインデックス」は将来の調査で誤参照の温床になる。E の前段としても必須 |
| **E. 要約スクリプト実装** | 中 | **保留（見送り推奨）** | 本キット固有の必要性が薄い。`claude-code-setup` の自動推薦・`session-report` プラグインなど既存資産で代替可能か先に確認すべき。自前実装は最後の手段 |
| **F. `security-guidance` 所在調査** | 中 | **後述の代替案と統合** | 単独タスクではなく、セキュリティ全般の補強策の一要素として扱うべき |
| **G. `commit-and-pr` 見直し** | 低 | **低（同意）** | ただし `commit-commands` プラグインの内部実装を覗き、PR テンプレ・ブランチ命名 hook など細部の差分を比較してから判断すべき |

**推奨実行順**: C → A → D → B → E（要否再判断）→ G。F はセキュリティ補強策の中で並行処理。

### 2. 見落としている視点

1. **本キットの「使われ方」シナリオが未定義**  
   利用者は「新規プロジェクトに丸ごとコピー」「部分取り込み」「Plugin 化して配布」のどれを想定？ これによって含めるべき内容が変わる（丸ごとコピーなら言語別 LSP は含めない方が軽量、Plugin 化なら `.claude/skills/` のスキャフォールドが必要）。**先にユースケースを文書化すべき**。

2. **`hooks-patterns.md` の中身調査が抜けている**  
   `claude-code-setup` の参照ドキュメントとして名前は挙がっているが内容未調査。本キット既存の音声通知 hooks との整合性・推薦パターンとの差分確認が必要。

3. **Claude Code 本体バージョンとの互換性管理が未整備**  
   MCP・プラグインは本体のバージョンに依存する。本キットの「動作確認バージョン」を CLAUDE.md か README に明記しないと、利用者環境で不可解な失敗が起きる。

4. **キット利用者向けデフォルト `settings.json` の未整備**  
   現在の `settings.local.json` はキット開発専用（音声 hooks、調査用の広範な allow）に最適化されている。CLAUDE.md には「テンプレートをコピーして…」とあるが、利用者向けのミニマル `settings.json` テンプレートが提供されていない。

5. **CI/CD 連携の視点**  
   GitHub Actions で Claude Code を実行するシナリオへの対応（`settings.local.json` の git ignore 状況、CI 用の最小権限プロファイル）が未検討。

6. **`output-styles` の活用機会**  
   CLAUDE.md に拡張オプションとして言及があるが、調査・レビュー結果の出力フォーマット統一に有効。本キットの `commit-and-pr` / `code-reviewer` / `orchestrate` と組み合わせるテンプレートを用意する余地あり。

### 3. `security-guidance` 代替案

`security-guidance` プラグインの実体不在は、Anthropic 側のリリース予定の問題。**プラグイン到着を待たず、以下の組み合わせで代替する**ことを推奨。

| 層 | 手段 | 効果 |
|---|------|------|
| **編集時の警告** | PreToolUse hook で `Edit`/`Write` を監視し、機密パターン（API キー文字列・`.env` 直接編集・`secrets/` 配下）を `decision: "deny"` で遮断 | プラグイン無しでも編集時セキュリティ警告を再現 |
| **コマンド実行の検証** | PreToolUse hook で `Bash` を監視し、`rm -rf /`・`curl \| sh`・`chmod 777` 等の危険パターンを検出 | Anthropic 公式の `bash-command-validator-example` を参考に実装可能 |
| **PR レビュー時のセキュリティ観点** | `pr-review-toolkit` の `silent-failure-hunter` エージェント＋ `code-review` の 4 並列エージェントの 1 つにセキュリティ観点を割り当てる | プラグインベースで網羅的レビュー |
| **静的解析連携** | GitHub MCP の `list_code_scanning_alerts`・`list_secret_scanning_alerts` を Claude Code から参照可能にする（既に許可済み） | CodeQL / Secret Scanning 結果との連携 |
| **方針の明文化** | `.claude/rules/security-checklist.md` を新設し、CLAUDE.md の「外部入力の境界でのみバリデーション」を OWASP Top 10 対応の具体的禁止事項リストへ展開 | path-scoped ロードでコード編集時のみ参照される |

特に **PreToolUse hook によるセキュリティガード** は、本キットがフックを既に活用している（音声通知）構成と整合性が高く、最初に着手する候補として強く推奨。

### 4. Opus からの追加提案：本キット固有の差別化軸

調査の総括として、本キットを単なる「公式推奨の寄せ集め」ではなく **独自価値を持つ最小構成テンプレート** に育てるための軸を3つ提案する。

1. **「Windows + 日本語」の一級サポート**  
   音声通知 hooks や `LANG=ja` 等、日本語環境での快適性を意識した設定を **明示的に売りにする**。多くの公式プラグインは英語前提で、Windows パス区切りの落とし穴も多い。本キットがこの領域を埋める価値は大きい。

2. **「調査キット」としてのアイデンティティ確立**  
   今回の作業（リポジトリ目次走査 → Memory MCP 登録 → レポート出力）は、汎用的なナレッジ整備のワークフローとして再利用可能。`/orchestrate` スキルにこのパターンをテンプレート化することで、利用者は本キットを「調査・整理キット」として活用できる。

3. **「最小構成」の哲学を文書化**  
   公式プラグインは網羅性志向で、結果として重い。本キットは「最小構成・必要に応じて拡張」を貫く方が、コピー利用時の認知負荷が低い。CLAUDE.md にこの哲学を明文化し、推薦されても採用しないものの判断基準を残すと、長期的なメンテ方針が明確になる。

---

*Opus 4.7 による追記終わり。本レポートに対するさらなる議論・実装着手は次セッション以降に持ち越し。*

---

## Sonnet 4.6 による補足追記（Opus 追記への応答）

### 優先順位評価への補足

**B（アーカイブ後継確認）の格下げについて**: 大筋で同意するが、Registry に登録されていない後継サーバーが存在することに注意。例えば Sentry MCP は公式 Registry に未登録のまま独自配布されているケースがある。C（Registry 走査）で吸収できない残件として B は保持しておくべき。**推奨実行順を「C → B（Registry で見つからなかった分のみ）→ A → D」に微修正する。**

**E（要約スクリプト）の見送りについて**: `session-report` プラグインはセッション要約用途であり、Memory MCP への**自動インデックス登録**（ファイル内容の要約 + エンティティ化）とは用途が異なる。Haiku + MCP SDK アプローチは依然として有効な選択肢。ただし D（インデックス検索ユースケース整理）の完了を先決条件とする点は Opus に同意。

### 見落とし視点への補足・追加

**Opus 視点 2「`hooks-patterns.md` 未調査」への追記**:  
`hooks-patterns.md` は `claude-code-setup` プラグインの参照ドキュメントの中で最も本キットの改善直結度が高い（本キットは hooks が核心）。A の実施前に単独で先読みする価値がある。

**追加見落とし視点: テスト戦略の不在**  
本キットはスキル・hooks・エージェントを含む「設定の実装」であるにもかかわらず、「それらが意図通り動くことを確認する方法」が整備されていない。`plugin-dev` プラグインの `validate-hook-schema.sh` / `test-hook.sh` が参考になる。少なくとも「hooks の JSON スキーマ検証」と「スキルの動作確認手順」を README または `.claude/` 配下に持つべき。

**追加見落とし視点: Memory MCP エンティティ設計の未整備**  
今回は走査ごとに場当たり的にエンティティ型（`MCPServer`・`ClaudePlugin`・`Announcement` 等）を定義したが、設計ドキュメントがない。後続セッションで型の追加・変更が起きたとき一貫性が失われるリスクがある。`D` の中でエンティティ型定義も含めた「Memory MCP スキーマ設計書」を成果物として定義することを推奨。

### security-guidance 代替案への補足

Opus の 5 層代替案に同意。着手順としては以下を推奨:

1. **`hooks-patterns.md` を先に読む**（A の前に実施）: フック実装パターンの正解を把握してから実装に入ることで手戻りを防ぐ
2. **最初に実装する hook**: `Bash` 監視の PreToolUse hook（危険コマンド検出）。本キットの既存 `PostToolUseFailure` hook との連携設計を考慮しつつ実装する
3. **`hookify` プラグインの活用**: セキュリティガード hook を自然言語から生成できるかを試す。`hookify` は自動生成 + 管理 UI を持つため、手書き JSON より保守性が高い可能性がある

### 差別化軸への賛同と具体化

Opus 提案の「Windows + 日本語の一級サポート」を本キットの明示的な差別化軸にする点に**強く賛同**。現在既に本キットが持つ Windows 対応要素を可視化しておくと、将来のコントリビューターへの方針伝達が容易になる:

| 要素 | 現状 |
|-----|------|
| 音声通知 hooks | 実装済み（`Media.SoundPlayer` + `SAPI.SpVoice`）|
| パス区切り両対応 | `Write(.claude/reports/*)` + `Write(.claude\\reports\\*)` 併記 |
| PowerShell コマンド | hooks 内で `powershell.exe` 明示 |
| `ralph-loop` | Windows 動作確認済みプラグインとして推薦可能 |

---

*Sonnet 4.6 による補足追記終わり。*

---

## Opus 4.7 による二次追記（Sonnet 補足への応答）

Sonnet の補足は概ね同意できる内容で、特に「テスト戦略の不在」「Memory MCP エンティティ設計の未整備」は本キットの長期メンテに直結する重要指摘。以下、さらに踏み込んだ視点を追加する。

### 1. Sonnet 異議への応答

**B（Registry 未登録の後継サーバー）への対応方針**:  
Sonnet の指摘は正しい。Registry は申請ベースであり、ベンダー独自配布のみのケースは確かに存在する。ただし、**Registry 未登録のサーバーを推薦する場合は別の品質基準を設ける**ことを推奨:

- GitHub Stars 1000+ または週次ダウンロード数 1000+
- 直近 3ヶ月以内のメンテナンス活動
- 公式ベンダー（Sentry、GitHub 等）の管理下にある明確な証跡

これを満たさない MCP サーバーは「実験的・要評価」とラベル付けして、推薦リストとは別カテゴリで管理すべき。

**E（Haiku + MCP SDK 要約スクリプト）への懸念**:  
Sonnet の「session-report と用途が違う」点には同意するが、**コスト対効果が D 完了まで不明**という根本問題が残る。Memory MCP の検索が部分一致のみという制約下では、「要約品質」より「**キーワード設計**」の方が引き出し精度を支配する。E は D で「どんなキーワードで引きたいか」を明確化してから初めて、要約に何を含めるべきかが決まる。**E は D の成果物の一部として再定義する**ことを提案（独立タスクではなく、D の中に「キーワード設計に基づく自動要約パイプライン」として包含する）。

### 2. Sonnet 追加見落とし視点への補足

**テスト戦略の補足**:  
Sonnet が `validate-hook-schema.sh` 等を挙げているが、**実行テストには本質的な制約がある**:

- 音声通知 hook は CI 環境（音声デバイスなし）で再現不能
- PowerShell 依存 hook は Linux ランナーで動かない
- ⇒ テスト戦略は「**設計レベルのレビュー** + **ローカルでの目視確認**」が現実解

一方、**スキル（`commit-and-pr` / `orchestrate`）はテスト可能**。サンプル入力（モックの git status・PR description 等）に対する期待出力を定義しておけば、回帰テストとして機能する。優先順位としては「スキルのテストを先に整備、hook はレビュー型」が妥当。

**Memory MCP エンティティ設計書のスキーマ考慮事項**:  
作成する場合、以下の決定事項を含めるべき:

| 項目 | 候補 |
|-----|------|
| 型名命名規則 | PascalCase 統一（`MCPServer`・`ClaudePlugin`） |
| 粒度 | 1 リポジトリ = 複数エンティティではなく、1 主要概念 = 1 エンティティ |
| 観察書式 | 自然文 + 先頭にカテゴリプレフィックス（`[purpose]`・`[install]`・`[note]`） |
| 関係命名 | 動詞の現在形・能動態（`provides`・`replaces`・`recommends`） |

これを D の成果物に含めることで、後続セッションでの一貫性を担保できる。

### 3. Sonnet の `hookify` 推奨への懸念

Sonnet が security-guidance 代替案で `hookify` 活用を提案している点について、**セキュリティクリティカル用途では慎重になるべき**:

- `hookify` は自然言語生成のため、検出漏れ（false negative）のリスクが本質的に存在
- 危険コマンド検出 hook は **検出漏れ = セキュリティ事故** に直結する
- **推奨**: `hookify` はプロトタイピング・初稿生成までに留め、生成された hook を**手動レビュー + 固定化**してから本採用する。生成結果をそのまま信頼しない

### 4. 追加メタ視点

**「キット」と「ナレッジ成果物」の境界が曖昧**:  
今回の作業で生成した `doc-repos-index-20260427.md`・`recommended-mcp-and-plugins-20260427.md` は**本キットの一部ではなく、キット開発のための調査成果物**。これらが `.claude/reports/` に残り続けると、キット利用者には不要な情報がコピーされる。**3層分離**を提案:

| 層 | 配置先 | 内容 |
|---|------|------|
| キット本体（利用者向け） | `.claude/` 配下のテンプレート | 汎用設定・スキル・hooks |
| キット開発ナレッジ | `C:\workspace\claude-doc-repositories\` または別リポジトリ | 調査レポート・Memory MCP データ |
| 個人作業ログ | `.claude/reports/` （`.gitignore`） | 本日のような作業記録 |

現状、`.claude/reports/` がコミット対象か `.gitignore` 対象かが曖昧。`.gitignore` の見直しを推奨。

**「Windows + 日本語」差別化軸の二層化**:  
PowerShell 依存・音声通知は CI/CD で動かない。差別化軸を維持しつつ、**ローカル開発用フル構成と CI 用最小構成の 2 層分離**が必要:

- `.claude/settings.json`（チーム共有・CI 互換）: 音声通知・PowerShell hook を含めない
- `.claude/settings.local.json`（個人用）: Windows ローカル向けフル構成

現状の本キットはこの分離が不完全（settings.json が空、settings.local.json に Windows 固有 hook が混在）。整理が必要。

### 5. レポート構造の改善提案

本レポートは Sonnet → Opus → Sonnet → Opus と多層化しており、**後から読み返す際の追跡コストが高い**。次セッションでの参照負荷を下げるため、以下を提案:

- **統合版（コンパクト版）の作成**: 本レポートの結論部分のみを抽出した `.claude/reports/work-summary-20260427.md` を別ファイルとして出力
- 統合版には「最終結論としての A〜G 優先順位」「実施すべき具体的アクション 5 件」「未解決の論点」のみを含める
- 議論経緯は本ファイル（`work-report-20260427.md`）に保持し、参照用として残す

統合版作成は次セッションの最初のタスクとすることを推奨。

---

*Opus 4.7 による二次追記終わり。本レポートはこれで完結。次セッションでは統合版作成・C（Registry 走査）・hooks-patterns.md 先読みから着手することを推奨。*
