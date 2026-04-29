# Memory MCP 構造化現状サマリ（既clone済みリポジトリ）

| 項目 | 内容 |
|---|---|
| 調査日 | 2026-04-29 |
| 調査範囲 | 既clone済みリポジトリ4件（claude-plugins-official / claude-ai-mcp / servers / cloudnative-co/claude-code-starter-kit）+ 対象外1件（life-sciences）|
| 関連計画書 | `計画書_basic-knowledge-gathering-ph2.md` |
| 用途 | Phase 3（ナレッジ抽出）の設計参考 / 重複登録の回避 |

---

## 1. 全体方針（既存設計）

`doc-repos-index-design` という WorkPlan エンティティに記録された設計方針：

- **目的**: `claude-doc-repositories` 内のリポジトリを Memory MCP にインデックス登録し、**MCP・プラグイン選定時の調査起点**として活用する
- **粒度方針**: 「プラグイン単位・MCPサーバー単位」を採用。ファイル単位は過剰、リポジトリ単位は粗すぎる
- **観察形式**: `key: value` 形式で統一（例: `usecase: code-review`, `lang: TypeScript`, `type: skill`）
- **走査手順**: (1) find でパス一覧取得 (2) `.md` の `^#` 見出しを grep (3) コードファイルはファイル名・ディレクトリ名のみ (4) Memory MCP に登録
- **登録対象**: claude-plugins-official / servers / claude-ai-mcp（**life-sciences は対象外**）
- **作業ステータス**: `scope_status: in_progress`（**完了していない**） / 次の作業: 目次走査の実施

---

## 2. エンティティタイプ一覧

| EntityType | 役割 | 例 |
|---|---|---|
| `Repository` | リポジトリ単位のメタ情報 | `anthropics/claude-plugins-official`, `modelcontextprotocol/servers` |
| `LocalCloneCollection` | クローン集合のルート | `claude-doc-repositories` |
| `Project` | このベースキット側のプロジェクト | `base-dev-kit-for-cc` |
| `Organization` | 組織 | `ModelContextProtocol` |
| `WorkPlan` | 構造化作業の計画 | `doc-repos-index-design` |
| `ClaudePlugin` | claude-plugins-official 内の個別プラグイン | `plugin-dev`, `hookify`, `code-review`, ... |
| `MCPServer` | servers 内の個別 MCP サーバー | `mcp-server-fetch`, `mcp-server-git`, ... |
| `Announcement` | claude-ai-mcp 内のアナウンス文書 | `announcement-sse-deprecation` |
| `StarterKit` | スターターキットそのもの | `cloudnative-co-claude-code-starter-kit` |
| `StarterKitMemoryDoc` | キット内 memory/ ドキュメント | `cloudnative-co:memory/best-practices` |
| `StarterKitCommand` | キット内 commands/ | `cloudnative-co:command/checkpoint` |
| `StarterKitSkill` | キット内 skills/ | `cloudnative-co:skill/strategic-compact` |
| `StarterKitFeature` | キット内 features/ | `cloudnative-co:feature/safety-net` |
| `StarterKitRule` | キット内 rules/ | `cloudnative-co:rule/git-workflow` |
| `RecommendedMCP` | 推奨MCPサーバー（横断的なリスト） | `recommended-mcp-github` |
| `ResourceIndex` | 外部レジストリ等への参照集 | `mcp-registry-index` |

---

## 3. リレーションタイプ

リレーションは最小限で、ほとんどの関連性は observation 内の `repo:` キー値などで内包。

| Relation | 意味 |
|---|---|
| `contains_clone_of` | LocalCloneCollection → Repository |
| `references_for_improvement` | Project → Repository |
| `owned_by` | Repository → Organization |

> **設計の特徴**: グラフのエッジは骨格用のみ。詳細関係（プラグインがどのリポ由来か等）は entity の observation 値で表現する設計。

---

## 4. リポジトリごとのカバレッジと粒度

### 4.1 anthropics/claude-plugins-official（カバレッジ: 高）

- リポジトリ全体エンティティ: ✅
- 内部プラグイン個別エンティティ化: 約20件（plugin-dev, mcp-server-dev, hookify, ralph-loop, commit-commands, code-review, pr-review-toolkit, feature-dev, claude-code-setup, claude-md-management, frontend-design, math-olympiad, playground, skill-creator, session-report, explanatory-output-style, learning-output-style, agent-sdk-dev など）
- 外部プラグイン個別エンティティ化: 5件以上（discord, telegram, imessage, greptile, fakechat など）
- LSPプラグイン: **束ねて1エンティティ** (`lsp-plugins-bundle`、12LSP分)
- 観察粒度: コマンド名・スキル一覧・エージェント一覧・カテゴリ・ユースケース・特徴

### 4.2 modelcontextprotocol/servers（カバレッジ: 中）

- リポジトリ全体エンティティ: ✅
- 個別MCPサーバーエンティティ化: 7件（fetch, filesystem, git, memory, sequentialthinking, time, everything）
- アーカイブ済みサーバーは Repository 観察内に列挙のみで個別エンティティ化なし
- 観察粒度: 言語・ユースケース・ツール一覧・インストール方法・対応クライアント

### 4.3 anthropics/claude-ai-mcp（カバレッジ: 中）

- リポジトリ全体エンティティ: ✅
- ファイル単位エンティティ化: 3件（drafts/ 配下のアナウンス文書のみ）
- 「コード実装ではなく情報発信ハブ」という性質に合わせて、文書単位で個別化
- 観察粒度: ファイル名・タイトル・要旨・必要なアクション・ステータス

### 4.4 cloudnative-co/claude-code-starter-kit（カバレッジ: 高）

- StarterKit 本体エンティティ: ✅（**最も観察数が多い** — kit全体の構成要素を要約的に列挙）
- サブタイプ別個別エンティティ化:
  - StarterKitMemoryDoc: 4件（best-practices, context-engineering, settings-reference, architecture）
  - StarterKitCommand: 4件（checkpoint, handover, research, learn）
  - StarterKitSkill: 6件（strategic-compact, prompt-patterns, continuous-learning, eval-harness, verification-loop, coding-standards, project-guidelines-example）
  - StarterKitFeature: 3件（pre-compact-commit, memory-persistence, safety-net）
  - StarterKitRule: 1件（git-workflow）
- **ただしキット全体では**: 9 agents / 10 rules / 17 commands / 12 skills / 12 hooks / 14 plugins と公称されており、**個別エンティティ化されているのは部分集合**
- 観察粒度: 出典ファイル / 公式準拠フラグ / Relevance（既存検討事項との紐付け）

### 4.5 anthropics/life-sciences（対象外）

- リポジトリ全体エンティティ: ✅（ただし `scope_status: out_of_scope` を明記）
- 個別エンティティ化: なし

---

## 5. 観察形式の特徴

### 5.1 表記スタイル

| 項目 | 採用スタイル |
|---|---|
| 区切り | `key: value` を1観察1行 |
| 言語 | 主要メタ情報は英語 / 補足は日本語混在 |
| 引用 | `Source: ...` で原典ファイルパスを明記（cloudnative-co系で顕著） |
| 検証フラグ | `CONFIRMED OFFICIAL` / `NOT an official ...` のように公式準拠の有無を併記 |

### 5.2 共通フィールド（プラグイン・MCPサーバー系）

```
repo:        所属リポジトリ
path:        リポジトリ内パス
category:    カテゴリ
command(s):  提供する slash command
agents:      内蔵エージェント
skills:      内蔵スキル
usecase:     ユースケース要約
features:    特徴
install:     インストール方法
```

### 5.3 共通フィールド（cloudnative-co 系）

```
Source:    元ファイルパス
Context:   非公式/公式の区別
Relevance: 既存検討事項（事項(1) A-E など）との紐付け
```

> **注**: 上記の `Relevance: 事項(1) A-E` 等の参照は、**過去の別検討内容**（インタラクション改善検討等）への紐付けを残したものと推測される。Phase 3 で新たな観察を追加する際は、`Relevance` キーは廃止または整理が必要。

---

## 6. 構造化の未完了領域

### 6.1 完了していない作業

`doc-repos-index-design.scope_status: in_progress` の通り、構造化作業自体が完了していない。具体的には：

- claude-plugins-official: 約30プラグインのうち**約20件のみ個別化済み**（残り10件未登録の可能性）
- modelcontextprotocol/servers: アクティブサーバー7件は登録済み、**アーカイブ済みサーバー13件は未登録**
- cloudnative-co/claude-code-starter-kit: **キット公称数 vs 登録済み数**に差異
  - agents 9 → 0件
  - rules 10 → 1件
  - commands 17 → 4件
  - skills 12 → 6件
  - hooks 12 → 3件
  - plugins 14 → 0件（外部plugin扱い）

### 6.2 観察観点の偏り

- claude-plugins-official 系: **機能カタログ的**（コマンド・スキル・エージェント名の列挙）
- cloudnative-co 系: **批評的・参照重視**（公式準拠フラグ、相互比較、Relevance タグ）
- claude-ai-mcp 系: **ニュース整理的**（個別アナウンス）

→ Phase 3 でリポジトリ追加する際は、**リポジトリの性質に応じて観察観点を変える**設計を踏襲すべき。

---

## 7. Phase 3（ナレッジ抽出）への含意

### 7.1 そのまま継承できる設計

- ✅ 粒度方針: 「プラグイン単位・MCPサーバー単位」（ファイル単位 / リポジトリ単位の中間）
- ✅ 観察形式: `key: value` 統一
- ✅ リレーション最小化（`contains_clone_of` / `owned_by`）+ observation 内の `repo:` キーで関連付け
- ✅ 公式準拠フラグの併記（特に外部キット系で重要）
- ✅ 大規模なリポジトリでは「束ね」エンティティの併用（lsp-plugins-bundle 方式）

### 7.2 改善・確認が必要な論点

1. **既存の `doc-repos-index-design` WorkPlan を Phase 2/3 計画とどう統合するか**
   - 既存ステータスは `in_progress`。本キックオフ計画書（v0.1）と整合させる必要
2. **登録漏れの解消をいつ実施するか**
   - 新規clone前に既存リポジトリの構造化を完了させるか
   - 新規clone後に一括で対応するか
3. **EntityType 命名規則**
   - cloudnative-co 系は `cloudnative-co:command/checkpoint` のように **コロン区切りで階層を表現**
   - 一方 claude-plugins-official 系は `plugin-dev` のように単純名
   - → 新リポジトリ追加時は **コロン区切り階層命名に統一すべきか** を決める
4. **`Relevance` キーの扱い**
   - 過去検討との紐付けを残すか / Phase 3 で再整理するか
5. **MCP 検索の制約への配慮**
   - Memory MCP の検索は **部分一致文字列検索**。エンティティ名にプレフィックス（例: `repo-name:type/sub-name`）を入れておかないと、検索が組織横断で漏れる可能性
   - 現状 cloudnative-co のみプレフィックス付きで、anthropics 系はプレフィックスなし → 統一性なし

### 7.3 Phase 2 選定作業への直接的影響

- 選定後にどのリポジトリを構造化対象にするかは、本サマリの「粒度方針」「観察形式」を引き継ぎ、計画書の Phase 3 で再検討する
- 既存の登録漏れ（4.1〜4.4 で示した未登録分）も、Phase 3 のスコープに含める旨を計画書に追記する想定

---

## 8. 計画書（`計画書_basic-knowledge-gathering-ph2.md`）への反映候補

以下のいずれかで計画書側を更新する：

- (a) 新セクション「Memory MCP 既存資産との関係」を追加し、本サマリへ参照を張る
- (b) 質問リスト（Q1〜Q15）に **Q16〜18 として「Memory MCP 既存登録の扱い」「未登録分の補完タイミング」「命名規則統一の要否」を追加**
- (c) 7章 質問 Q1（既clone済リポジトリの再評価扱い）に、Memory MCP 登録状態の再評価論点を統合

> **推奨**: (a) + (b)。本サマリは独立ドキュメントとして残し、計画書からは参照のみ張る。質問は新規追加して回答時にユーザー判断を仰ぐ。
