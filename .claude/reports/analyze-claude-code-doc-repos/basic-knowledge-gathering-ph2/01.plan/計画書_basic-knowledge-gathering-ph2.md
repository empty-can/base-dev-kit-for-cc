# 計画書: basic-knowledge-gathering-ph2

| 項目 | 内容 |
|---|---|
| 文書ステータス | **確定版（v0.3）** |
| 作成日 | 2026-04-29 |
| 最終更新 | 2026-04-29 |
| 関連キックオフ | `../00.キックオフインプット.txt` |
| 関連別紙 | `別紙_提示希望情報(ユーザーへの質問リスト)回答.md` / `Memory-MCP構造化現状.md` |
| 想定変更頻度 | 中（選定基準は確定済。W1〜W4 進行中の微修正可能性あり） |

---

## 1. 活動の目的とスコープ

### 1.1 目的
`base-dev-kit-for-cc` リポジトリの目的（Claude Code を最大限活用するためのテンプレート整備）を達成するために必要な「基礎情報の蓄積」を、隣接フォルダ `C:\cc-workspace\claude-doc-repositories` 配下のリポジトリ群を拡充することで継続する。

### 1.2 スコープ（Phase 2）
3団体のGitHub組織から、`claude-doc-repositories` 配下に **clone する価値のあるリポジトリ群を選定する** ところまで。

| 団体 | GitHub URL（既知） | 既clone済み |
|---|---|---|
| Anthropic | https://github.com/anthropics | claude-plugins-official / claude-ai-mcp / life-sciences |
| Model Context Protocol | https://github.com/modelcontextprotocol（想定）| servers |
| cloudnative-co | https://github.com/cloudnative-co（想定）| claude-code-starter-kit（cloudnative-co/ 配下）|

> **注**: 各団体の参照ページ具体URLは、ユーザー側で本フォルダ配下にテキストファイルとして配置予定（Q14 = (a)）。

### 1.3 スコープ外（Phase 2 では実施しない）
- 実際の `git clone` 実行（ユーザー実施）
- clone 済リポジトリからのナレッジ抽出・構造化（→ 後続作業 `03.knowledge-extraction`）
- 4団体目以降の探索プロセス（cloudnative-co 以外の関連団体が出てきた場合は別途プロセス再検討）

---

## 2. 現在 clone 済みのリポジトリ（参考情報）

```
C:\cc-workspace\claude-doc-repositories\
├── claude-ai-mcp                     # anthropics 由来
├── claude-plugins-official           # anthropics
├── cloudnative-co/
│   └── claude-code-starter-kit       # cloudnative-co の組織配下
├── life-sciences                     # anthropics（MCP・プラグイン推薦の対象外）
└── servers                           # Model Context Protocol（公式サーバー集）
```

> **命名規則**: 既存は混在しているが、Phase 2 で追加する分は **`<organization>/<repo>` 形式に統一**（Q12 = (b)）。既存リポジトリも後々同形式へ移行予定。

---

## 3. 作業ブレークダウン

| # | 作業 | サブフォルダ | 現ステータス |
|---|---|---|---|
| W0 | キックオフ・計画立案 | `01.plan/`（このファイル + 別紙2点）| **完了**（v0.3で確定）|
| **W0.5** | **SDK役割確認**（公式ドキュメントSDKページ + 代表2件 README）| `01.plan/SDK調査メモ.md` | 未着手 |
| W1 | 3団体トップページから候補メタデータ全量取得 | `02.likely-repos-listup/01.raw-listings/` | 未着手（URLリスト待ち）|
| W2 | 粗振り（メタ情報による足切り）| `02.likely-repos-listup/02.coarse-filter/` | 未着手 |
| W3 | 本振り（READMEセクション単位読込）| `02.likely-repos-listup/03.deep-screen/` | 未着手 |
| W3.5 | アーカイブ移譲先追跡（必要時のみ）| `02.likely-repos-listup/04.archive-trace/` | 未着手 |
| W4 | 最終出力（CSV+MD 4本立て）| `02.likely-repos-listup/99.final-list/` | 未着手 |
| W5 | clone 実行・ナレッジ抽出（後続Phase）| `03.knowledge-extraction/` | 計画外（別 Phase）|

### 3.1 W0.5 SDK役割確認の詳細

- **目的**: SDK が「Claude を活用する一般利用者にとって必須でない技術深度」かを実例で確認し、SDK 系リポジトリを「候補に含めない」と確定する根拠を得る
- **手順**:
  1. Claude Code 公式ドキュメントの SDK 関連ページを読み、SDK の種類（Agent SDK / Anthropic API SDK 等）を把握
  2. 代表的な 2 件の SDK リポジトリ README を確認（候補: `claude-agent-sdk-python` / `anthropic-sdk-typescript`）
  3. SDK の役割・想定読者・利用ケースをサマリ
- **アウトプット**: `01.plan/SDK調査メモ.md`
- **判定の出口**: 本キット利用者の典型業務（運用ノウハウ・テンプレート・hooks 等）に直接寄与しないことが確認できれば、Phase 2 全体で SDK 系リポジトリを「除外」確定

---

## 4. ツール使い分け方針

### 4.1 動作確認結果（2026-04-29 時点）

| ツール / MCP | ステータス | 備考 |
|---|---|---|
| github MCP | ✅ OK | `Higashi-no-Gensokyo` として認証済み |
| fetch MCP | ✅ OK | HTML→Markdown変換あり |
| WebFetch（組み込み）| ✅ OK | AIによる抽出 |
| WebSearch（組み込み）| 必要時に検証 | 米国限定の制約あり |
| context7 MCP | ❌ NG（APIキー無効）| 本作業では不要のため代替不要 |

### 4.2 局面別の推奨ツール

| 局面 | 第一選択 | 第二選択 | 備考 |
|---|---|---|---|
| 組織配下のリポジトリ全量取得（メタ情報）| github MCP `search_repositories` (`org:anthropics` 等)| fetch MCP（HTML）| star/最終更新で sort 可、構造化済 |
| トップページの「Popular repositories」順位 | fetch MCP（HTML）| WebFetch | API では「popular」概念なし |
| 個別リポジトリの README 取得 | github MCP `get_file_contents` | fetch MCP（raw URL）| API は認証済・レート制限緩和 |
| README 内のセクション抽出 | （取得後に Bash の grep/sed で範囲特定）| - | API呼び出し回数は同じ、Claudeが読むトークン量を削減 |
| 関連リポジトリ発見 | github MCP `search_code` | WebFetch | キーワード横展開 |
| アーカイブ移譲先の追跡 | github MCP `search_repositories` + WebSearch | WebFetch | 後継リポジトリ特定用 |
| 外部評価記事 | WebSearch | WebFetch | 必要時のみ |

### 4.3 効率化フロー（確定版）

```
W0.5: SDK役割確認
  └─ 公式ドキュメントSDKページ → 代表2件のREADME
     → SDK調査メモ.md として独立記述
     → 結果に応じて Phase 2 全体で SDK 系を除外確定

W1: 全量取得
  └─ org ごとに search_repositories で全件取得 (perPage=100, page=1..N)
     + トップページHTMLを fetch して "Popular repositories" 順位を補強
     + 組織の verified マーク有無も取得

W2: 粗振り（メタ情報のみで判定 - Lazy方針）
  └─ メタ情報のみで「明白に対象外」「明白に対象」を仕分け
     - description / topics / language の単純照合
     - アーカイブフラグ + last_pushed_at で古いものを除外（移譲アーカイブは W3.5 へ）
     - 既clone済との重複除外
     - 除外指定（life-sciences / SDK系 / ドメイン特化 / 営業外部資料系）の適用

W3: 本振り（曖昧候補にセクション単位 README 読込）
  └─ 曖昧候補に対し github MCP get_file_contents で README 取得後、
     1. grep -nE '^#{1,3} ' で目次抽出
     2. 判定に必要なセクションを優先順位で読み込み:
        ① 冒頭〜最初の見出し直前（プロジェクト概要）
        ② "Features" / "What is this" / "Overview" / "Why" 系
        ③ "Use cases" / "Examples" 系
        ④ "Installation" / "Quickstart" 系
     3. sed -n '<開始>,<終了>p' で範囲抽出して読込
     4. 主要セクション読了後も判定不能なら confidence: low で保留候補リストへ
  └─ ※ CLAUDE.md は判断材料として弱い想定のため基本読まない

W3.5: アーカイブ移譲先追跡（必要時のみ）
  └─ W2 で `archived: true` のリポジトリのうち:
     1. Claude が連携先ドメイン特性で追跡対象の絞り込み案を提示
        （例: Brave/Google/Slack/EverArt 等の容易導入困難・用途限定はスキップ）
     2. ユーザーが絞り込み案を承認/修正
     3. 承認分について後継リポジトリを能動探索
     4. 後継リポジトリが見つかれば W2 のフローに合流

W4: 最終出力
  └─ 4本立てのファイル + サマリ:
     - recommended_repos.csv / recommended_repos.md
     - pending_repos.csv（保留候補）
     - rejected_repos.csv
     - selection_summary.md（全体サマリ）
```

---

## 5. 選定基準（確定版）

別紙 `別紙_提示希望情報(ユーザーへの質問リスト)回答.md` の Q1〜Q18 + G1〜G7 への回答に基づく。

### 5.1 評価優先度

| 順位 | 観点 | 備考 |
|---|---|---|
| **★最高** | **小規模ローカルRAGの効率実現に資する情報**（観点 d または a の文脈で）| 詳細は7章 |
| 1 | 観点 d: 運用ノウハウ・ベストプラクティス（チーム共有・統制・CI連携）| |
| 2 | 観点 c: Plugin / Skill / Agent のテンプレート性 | |
| 3 | 観点 a: Claude Code 機能（hooks/commands/agents/skills/settings）の参考 | 観点 d/c の裏取り用途 |
| 4 | 観点 b: MCP サーバー・クライアント実装の参考 | 観点 d/c の中で利用されるものから自然取得 |
| 4 | 観点 e: ドメイン特化サンプル | 観点 d/a と関わりの深いドメインに限り価値あり |

### 5.2 採否フィルタ

| 軸 | 確定基準 |
|---|---|
| **強い除外** | 業界・ドメイン特化（観点 d/a に薄いもの）/ 営業・外部資料作成系 / SDK 本体（W0.5 確認後に確定）/ 最終更新 2024 年以前（移譲アーカイブを除く）|
| **形態判定** | チュートリアル: 個別判断 / SDK: 候補に含めない（W0.5 で確定）/ 公式 docs / specification: 含める |
| **アーカイブ** | 一律除外。ただし「他団体に移譲」アーカイブは W3.5 で後継を追跡し含める。後継なし廃止は完全除外 |
| **言語** | Shell系を最優先、それ以外は広く浅く |
| **Star 数** | 最低ライン無し。CSV/MD に併記してユーザーが見てから再考 |
| **ライセンス** | 個別判断（独自・未記載も許容）|
| **候補数** | 件数制限なし（基準合格は全採用）|
| **3団体外** | 制限なし。README 内で発見した別組織のリポジトリも積極推奨 |
| **verified マーク** | 列で記録。非verified組織は個別判断で必要に応じ notes に注記 |

### 5.3 採否の3区分

| 区分 | 出力先 | 配置基準 |
|---|---|---|
| **recommended** | recommended_repos.csv/.md | 採用判定したもの。`confidence` は high/medium/low |
| **pending** | pending_repos.csv | メタ→READMEまで読んでも判定できなかったボーダーライン候補（confidence: low）|
| **rejected** | rejected_repos.csv | メタ情報の段階で「明白に対象外」と判定したもの |

---

## 6. 想定するアウトプット

### 6.1 W0.5 アウトプット

```
01.plan/
└── SDK調査メモ.md                    # SDK役割確認結果
```

### 6.2 W1 アウトプット（粗データ）

```
02.likely-repos-listup/01.raw-listings/
├── anthropics_repos_<date>.json     # github MCP の生レスポンス
├── anthropics_popular_<date>.md     # トップページHTMLから抽出した人気順
├── modelcontextprotocol_repos_<date>.json
├── modelcontextprotocol_popular_<date>.md
├── cloudnative-co_repos_<date>.json
└── cloudnative-co_popular_<date>.md
```

### 6.3 W4 アウトプット（最終成果物）

```
02.likely-repos-listup/99.final-list/
├── recommended_repos.csv               # 推奨リスト（CSV / 機械可読）
├── recommended_repos.md                # 推奨リスト（Markdown / 人間向けサマリ）
├── pending_repos.csv                   # 保留候補リスト
├── rejected_repos.csv                  # 却下リスト
└── selection_summary.md                # 全体サマリ（採用基準・件数・所感）
```

#### 6.3.1 CSV 列定義（共通）

| 列名 | 説明 |
|---|---|
| `org` | GitHub組織名 |
| `repo` | リポジトリ名 |
| `url` | URL |
| `stars` | star数 |
| `forks` | fork数 |
| `last_pushed_at` | 最終push日時（ISO8601）|
| `archived` | アーカイブフラグ（true/false）|
| `language` | 主言語 |
| `license` | ライセンス |
| `topics` | topics（カンマ区切り、CSVのカンマと混同しないよう囲み文字で対応）|
| `one_line_desc` | 1行説明 |
| `verified` | 組織のverifiedマーク有無（true/false）|
| `recommendation` | recommended / pending / rejected |
| `reason` | 推奨/却下/保留の理由 |
| `knowledge_areas` | 推定知見領域（カンマ区切り）|
| `confidence` | high / medium / low |
| `priority_flag` | 通常空欄 / `local-rag-highest` |
| `notes` | 個別注記（特にverified関連の特筆点等）|

#### 6.3.2 ファイル仕様

- **文字コード**: UTF-8 BOM付き
- **区切り**: カンマ
- **改行**: CRLF（Windows互換）
- **囲み文字**: ダブルクォート（カンマや改行を含む値のみ）
- **ヘッダ行**: あり

#### 6.3.3 Markdown版（recommended_repos.md）

主要列のみで組織別グルーピングした表形式。**ローカルRAG関連は専用セクション**として切り出し。容量が肥大化した場合は `local-rag-candidates.md` として独立ファイルへ分割。

#### 6.3.4 却下記録の粒度

却下リストの記録は **「URL＋却下理由＋取得済みメタ情報」** とし、簡易的な内容サマリは記載しない。簡易サマリを書きたくなる事例は却下根拠が弱い兆候とし、判断そのものを再検討する。

---

## 7. ローカルRAG例外条項（最高優先扱い）

### 7.1 対象範囲

「小規模ローカルRAGを効率的に実現する情報」を含むリポジトリは、評価優先度の **★最高** として扱う。具体的に対象とする RAG 構成：

- ベクトルDB（chroma / sqlite-vss / qdrant local 等）
- ハイブリッド検索（BM25 + ベクトル + Reranker）
- GraphRAG（知識グラフ + ベクトル統合）

> **対象外**: ファイル grep / Markdown 索引レベル（RDB 全文検索の方が優位）/ ナレッジグラフ単体（構造設計依存・拡張性に限界）

### 7.2 判定指標

| 主指標 | トークン効率（検索結果の精度・コンパクトさ）|
|---|---|
| 補助指標 | Claude Code との統合容易さ（hook / skill / mcp 経由）|

主指標を満たすが補助指標が弱い場合も、最高優先扱いを維持する。「LLMにしかできないことに注力させ、それ以外は他のツールに任せる」方針が背景。

### 7.3 出力上の扱い

- CSV: `priority_flag` 列に `local-rag-highest` を記録
- Markdown サマリ: 専用セクションを作成
- 該当数が多くセクションに収まらない場合: `local-rag-candidates.md` として独立ファイル化

---

## 8. プロセス・進め方の確定事項

質問への詳細回答は別紙 `別紙_提示希望情報(ユーザーへの質問リスト)回答.md` 参照。

| 項目 | 決定内容 |
|---|---|
| 既clone済の扱い | 重複扱い（再評価不要）|
| 段階承認 vs 一括 | 3団体まとめて一括提示。cloudnative-co 以外の追加団体は別途プロセス再検討 |
| URLリスト共有 | ユーザーが本フォルダ配下にテキストファイルとして配置 |
| 件数 | 全件評価。情報過剰回避は W3 のセクション単位読込で担保 |
| クローン後フォルダ命名 | `<organization>/<repo>` 形式に統一 |
| 出力形式 | CSV（UTF-8 BOM付き / カンマ）+ Markdown 併用、4本立て |
| 却下記録 | URL＋理由＋メタ情報（簡易サマリは付けない）|
| 保留候補 | 独立ファイル `pending_repos.csv` として管理 |

### 8.1 アーカイブ移譲追跡の運用（W3.5）

1. W2 で `archived: true` のリポジトリを抽出
2. Claude が **連携先ドメインの特性に基づき**、追跡対象を絞り込む案を提示（例: Brave/Google/Slack/EverArt 等は追跡スキップ）
3. ユーザーが絞り込み案を承認/修正
4. 承認分についてのみ後継リポジトリを能動探索

### 8.2 Memory MCP 既存資産との関係

別紙 `Memory-MCP構造化現状.md` 参照。要旨:

- 構造化方針（粒度・観察形式）は `doc-repos-index-design` WorkPlan で確立済 → 新規も同方針で継続可能
- 既存の登録漏れあり → **Phase 3 冒頭で補完**（Q17 = (b)）
- 既存登録は **再評価・上書き可**（Q16 = (b)）
- 命名規則の統一は **保留**（Q18）

---

## 9. オープン論点・後から決めること

- リポジトリの内容を「ナレッジ」として構造化する際のスキーマ（→ Phase 3 冒頭で別途検討）
- Memory MCP 命名規則の統一（→ Phase 3 で発見性設計後に判断）
- 同一組織で大規模モノレポと多数の小リポジトリが両立する場合の優先付け
- README に記述された外部参照（YouTube・ブログ等）を二次情報として扱うか
- 4団体目以降の探索プロセス

---

## 10. セッションをまたぐ際の作業継承

本計画書を **Single Source of Truth** とする。セッション再開時は以下の順で読む：

1. `00.キックオフインプット.txt`（活動の動機・スコープ）
2. 本計画書（最新ステータス・残作業）
3. 別紙2点（質問回答 / Memory MCP 現状）
4. `02.likely-repos-listup/` 配下の最新成果物（中間生成物）
5. `auto-memory` の `MEMORY.md`（横断的な指示・嗜好）

各作業フェーズの完了時には、本計画書の **3章「作業ブレークダウン」のステータス** を更新する。

---

## 11. 暫定スケジュール（粗）

| # | 作業 | 所要 | 主担当 | 備考 |
|---|---|---|---|---|
| 1 | W0.5 SDK役割確認 | 30〜60分 | Claude | 公式ドキュメント+代表2件 |
| 2 | URLリスト共有 | ユーザー次第 | ユーザー | 本フォルダにテキストファイル配置 |
| 3 | W1（全量取得）| 30〜60分 / 団体 | Claude | API呼び出し中心 |
| 4 | W2（粗振り）| 15〜30分 / 団体 | Claude | 自動 |
| 5 | W3（本振り）| 30〜60分 / 団体 | Claude | セクション単位読込により短縮 |
| 6 | W3.5（アーカイブ追跡）| 必要時 | Claude＋ユーザー承認 | 絞り込み案提示型 |
| 7 | W4（最終出力）| 30分 | Claude | 統合・整形 |
| 8 | レビュー・微修正 | ユーザー次第 | ユーザー＋Claude | 反復前提 |

> **トークン消費の見積**: W3 はセクション単位読込採用により、READMEを全文取得する場合と比べてClaudeが読むトークン量を **1/3〜1/5 程度に削減** できる見込み。

---

## 12. 改訂履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-04-29 | 初版（たたき台）|
| v0.2 | 2026-04-29 | Memory MCP 構造化現状の調査結果を反映（7.5節追加 / Q16〜Q18追加）|
| v0.3 | 2026-04-29 | **確定版**。Q1〜Q18 + G1〜G7 + 確認1〜3 の合意を反映。SDK調査タスク(W0.5)・アーカイブ移譲追跡(W3.5)を追加。READMEセクション単位読込フローを採用。出力ファイルを4本立てに確定。ローカルRAG例外条項を新章として独立 |
