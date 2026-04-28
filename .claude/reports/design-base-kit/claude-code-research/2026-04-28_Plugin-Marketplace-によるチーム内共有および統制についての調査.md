# Plugin Marketplace によるチーム内共有および統制についての調査

- **調査日**: 2026-04-28
- **調査者**: Claude Sonnet 4.6
- **参照元**:
  - https://code.claude.com/docs/en/plugins
  - https://code.claude.com/docs/en/plugin-marketplaces
  - https://code.claude.com/docs/en/discover-plugins
  - https://code.claude.com/docs/en/plugins-reference
  - https://code.claude.com/docs/en/settings

---

## 概要

Claude Code の「Plugin」は、Skill・Agent・Hook・MCP サーバーなどを**パッケージ化してチームや外部に配布する**仕組み。実体は **Plugin 単体 + Marketplace カタログ + 配布インフラ** の三層構造になっている。

本調査では、(1) Plugin と Marketplace の仕組みと実装方法、(2) 「`.claude` フォルダを git リポジトリ化して clone・fetch する」などの代替手段と比べたときの排他的優位性、の 2 点を明らかにする。

なお「三層構造」の各層の意味は以下の通り：**Plugin 単体**（Skills/Agents/Hooks 等をパッケージ化したディレクトリ）、**Marketplace カタログ**（`marketplace.json` による Plugin 一覧の定義）、**配布インフラ**（git ホスティング・自動更新機構・`~/.claude/plugins/cache/` によるキャッシュ管理）。

---

## Part 1: 仕組みの理解

### 1-1. Standalone vs Plugin ── 使い分け基準

| 観点 | Standalone (`.claude/` 配置) | Plugin |
|---|---|---|
| **スキル呼び出し名** | `/hello` | `/my-plugin:hello`（名前空間付き） |
| **適用範囲** | 1 プロジェクト | 複数プロジェクト横断 |
| **共有方法** | 手動コピー | Marketplace からインストール |
| **バージョン管理** | なし | `version` フィールドで制御 |
| **推奨シーン** | 個人用途・実験・単一プロジェクト | チーム配布・再利用・コミュニティ公開 |

> **推奨フロー**: まず `.claude/` で Standalone として開発・検証し、安定したら Plugin に変換する。

### 1-2. Plugin の構造

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          # プラグインマニフェスト（任意。省略時はディレクトリ名がプラグイン名になる）
├── skills/
│   └── <skill-name>/
│       └── SKILL.md
├── commands/                # フラット形式のスキル（新規は skills/ 推奨）
├── agents/
│   └── <agent-name>.md
├── hooks/
│   └── hooks.json
├── .mcp.json                # MCP サーバー設定
├── .lsp.json                # LSP サーバー設定
├── monitors/
│   └── monitors.json
├── bin/                     # PATH に追加される実行ファイル
└── settings.json            # プラグイン有効時に適用されるデフォルト設定
```

> **注意**: `skills/` / `agents/` / `hooks/` 等は**プラグインルート直下**に置く。`.claude-plugin/` 内に入れるのは `plugin.json` のみ。

#### plugin.json の構造

```json
{
  "name": "my-plugin",           // スキル名前空間になる（例: /my-plugin:hello）
  "description": "説明文",
  "version": "1.0.0",            // 省略時は git commit SHA が使われる
  "author": { "name": "Your Name" },
  "homepage": "https://...",
  "repository": "https://...",
  "license": "MIT",
  "dependencies": [
    "helper-lib",
    { "name": "secrets-vault", "version": "~2.1.0" }
  ]
}
```

### 1-3. Plugin Marketplace の仕組み

**Marketplace** = プラグイン一覧を記述した `marketplace.json` カタログを git リポジトリでホストする仕組み。

#### Marketplace リポジトリの構造

```
my-team-marketplace/
├── .claude-plugin/
│   └── marketplace.json               # マーケットプレイスカタログ
└── plugins/
    ├── code-formatter/
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   └── skills/
    │       └── format/
    │           └── SKILL.md
    └── deployment-tools/
        ├── .claude-plugin/
        │   └── plugin.json
        └── hooks/
            └── hooks.json
```

#### marketplace.json の構造

```json
{
  "name": "acme-tools",
  "owner": {
    "name": "DevTools Team",
    "email": "devtools@example.com"
  },
  "metadata": {
    "description": "社内開発ツール集"
  },
  "plugins": [
    {
      "name": "code-formatter",
      "source": "./plugins/code-formatter",
      "description": "保存時に自動フォーマット",
      "version": "2.1.0"
    },
    {
      "name": "deployment-tools",
      "source": {
        "source": "github",
        "repo": "your-org/deploy-plugin",
        "ref": "v1.0.0"
      },
      "description": "デプロイ自動化ツール"
    }
  ]
}
```

#### Plugin Source の種類

| 種類 | 記法 | 用途 |
|---|---|---|
| 相対パス | `"./plugins/my-plugin"` | Marketplace と同一リポジトリ内 |
| GitHub | `{ "source": "github", "repo": "org/repo" }` | GitHub の別リポジトリ |
| Git URL | `{ "source": "url", "url": "https://..." }` | GitLab・自社 Git サーバー等 |
| Git サブディレクトリ | `{ "source": "git-subdir", "url": "...", "path": "..." }` | モノレポ内の一部 |
| npm | `{ "source": "npm", "package": "...", "version": "..." }` | npm レジストリ |

---

## Part 2: チームへの配布実装

### 2-1. チーム配布の 4 ステップ

#### Step 1: Plugin を作成する

```bash
mkdir -p my-plugin/.claude-plugin
mkdir -p my-plugin/skills/code-review
```

```json
// my-plugin/.claude-plugin/plugin.json
{
  "name": "team-dev-tools",
  "description": "チーム開発ツール集",
  "version": "1.0.0"
}
```

```markdown
<!-- my-plugin/skills/code-review/SKILL.md -->
---
description: コードレビューの観点でファイルを分析する
---

変更されたコードについて以下を確認してください：
1. バグ・エッジケース
2. セキュリティ問題
3. パフォーマンス
4. 可読性

簡潔で実行可能なフィードバックを出力してください。
```

#### Step 2: Marketplace カタログを作成する

```json
// team-marketplace/.claude-plugin/marketplace.json
{
  "name": "acme-dev-tools",
  "owner": { "name": "Platform Team", "email": "platform@example.com" },
  "plugins": [
    {
      "name": "team-dev-tools",
      "source": "./plugins/team-dev-tools",
      "description": "チーム開発ツール集",
      "version": "1.0.0"
    }
  ]
}
```

#### Step 3: GitHub/GitLab にプッシュする

```bash
cd team-marketplace
git init && git add . && git commit -m "feat: add team marketplace"
git remote add origin https://github.com/your-org/claude-plugins.git
git push -u origin main
```

#### Step 4: プロジェクト設定でチームに自動配布する

**利用側プロジェクトの** `.claude/settings.json` に追加することで、リポジトリを信頼したチームメンバーに自動的にマーケットプレイスが提示される（Marketplace リポジトリ側ではなく、このツールを使う各プロジェクト側に書く）：

```json
{
  "extraKnownMarketplaces": {
    "acme-dev-tools": {
      "source": {
        "source": "github",
        "repo": "your-org/claude-plugins"
      }
    }
  }
}
```

### 2-2. インストールスコープの選択

| スコープ | 設定ファイル | 対象 |
|---|---|---|
| **managed** | システムファイル（変更不可） | IT 管理者による組織全体への強制 |
| **project** | `.claude/settings.json`（Git 管理） | このリポジトリの全コラボレータ |
| **local** | `.claude/settings.local.json`（gitignore） | 自分のみ・このリポジトリ限定 |
| **user** | `~/.claude/settings.json` | 自分のすべてのプロジェクト |

優先順位（高→低）: managed > Command line（CLI 引数） > local > project > user

チーム共有には **project スコープ**が基本。同一プラグインを複数スコープで同時インストールでき、例えば「チームは project スコープで v1.0.0 を使いつつ、自分だけ local スコープで v2.0.0-beta を試す」が可能。

```bash
# CLI でプロジェクトスコープにインストール
claude plugin install team-dev-tools@acme-dev-tools --scope project
```

### 2-3. 既存の Standalone 設定を Plugin に移行する手順

```bash
# ① Plugin ディレクトリ作成
mkdir -p my-plugin/.claude-plugin

# ② plugin.json 作成
cat > my-plugin/.claude-plugin/plugin.json <<'EOF'
{
  "name": "my-plugin",
  "description": "Migrated from standalone configuration",
  "version": "1.0.0"
}
EOF

# ③ 既存ファイルをコピー
cp -r .claude/commands my-plugin/
cp -r .claude/agents   my-plugin/
cp -r .claude/skills   my-plugin/

# ④ hooks を移行（settings.json の "hooks" オブジェクトを抽出して hooks/hooks.json へ）
mkdir my-plugin/hooks
jq '{hooks: .hooks}' .claude/settings.json > my-plugin/hooks/hooks.json

# ⑤ テスト
claude --plugin-dir ./my-plugin
```

| 移行前 (Standalone) | 移行後 (Plugin) |
|---|---|
| `.claude/commands/` | `my-plugin/commands/` |
| `settings.json` の hooks | `hooks/hooks.json` |
| `/skill-name` | `/my-plugin:skill-name` |
| 手動コピーで共有 | `/plugin install` でインストール |

### 2-4. ローカルでのテスト・開発

```bash
# プラグインを直接ロードして起動（インストール不要）
claude --plugin-dir ./my-plugin

# 複数プラグインを同時にロード
claude --plugin-dir ./plugin-one --plugin-dir ./plugin-two

# 変更を再起動なしで反映
/reload-plugins
```

インストール済みの同名プラグインより `--plugin-dir` 版が優先されるため、本番を壊さずに開発できる。

---

## Part 3: 代替手段との比較優位性分析

### 3-1. 比較対象とする代替手段

| # | 代替手段 | 概要 |
|---|---|---|
| A | **`.claude` リポジトリ clone 方式** | 専用リポジトリに `.claude/` 内容を格納し、各プロジェクトで submodule/clone してシンボリックリンクで参照。更新は `git pull` を手動実行 |
| B | **プロジェクトへの直接コピー方式** | スキルや hooks を各プロジェクトの `.claude/` に手動コピー。更新は手動 diff + コピー |
| C | **CLAUDE.md + git submodule 方式** | 共通設定を別リポジトリで管理し、git submodule で取り込んだローカルパスを `CLAUDE.md` に `@<path>` インポートで参照（URL インポートは未サポート） |

### 3-2. Plugin Marketplace 固有の機能（代替不可能な優位性）

#### (1) 組織レベルの強制適用（Managed Settings）

IT 管理者がシステムレベルのファイルに以下を記述することで、ユーザーが変更できない設定を組織全体に強制できる。

配置先（OS 別）:
- macOS: `/Library/Application Support/ClaudeCode/managed-settings.json`
- Linux: `/etc/claude-code/managed-settings.json`
- Windows: `C:\Program Files\ClaudeCode\managed-settings.json`

```jsonc
{
  "enabledPlugins": {
    "security-scanner@company-tools": true,
    "code-formatter@company-tools": true
  },
  "strictKnownMarketplaces": [
    { "source": "github", "repo": "your-org/approved-plugins" }
  ]
}
```

| 機能 | Plugin Marketplace | 代替手段 |
|---|---|---|
| 全社員へ特定プラグインを強制インストール | ✅ `managed` スコープ | ❌ 個人が clone するかどうかは任意 |
| 承認済み以外のマーケットプレイスをブロック | ✅ `strictKnownMarketplaces` | ❌ 制御手段なし |
| ユーザーが無効化できない設定を配布 | ✅ managed は変更不可 | ❌ 個人が自由に変更可能 |

`strictKnownMarketplaces` は **Managed Settings 専用**で、ユーザー・プロジェクト設定から上書きできない。代替手段では「信頼できないスクリプトを使わないでください」という規約レベルの対応しかできず、技術的な強制力が存在しない。

#### (2) 機密情報のセキュアストレージ（userConfig + sensitive）

```json
// plugin.json
{
  "userConfig": {
    "api_token": {
      "type": "string",
      "title": "API トークン",
      "description": "認証トークンを入力",
      "sensitive": true    // システムキーチェーンに保存（settings.json には書かれない）
    }
  }
}
```

プラグイン有効化時に UI で入力を求め、`sensitive: true` のフィールドは**システムキーチェーン**（または `~/.claude/.credentials.json`）に格納される。設定値は `${user_config.api_token}` としてスキル・フック・MCP 設定内で参照できる。

代替手段では API トークン等を `.claude/settings.json` や環境変数に平文で書く必要があり、Git 管理対象ファイルに機密情報が混入するリスクがある。

#### (3) セキュリティ境界：プラグインキャッシュへのコピー

インストールされたプラグインは `~/.claude/plugins/cache/` に**コピー**される（参照ではなく実体のコピー）。

```
~/.claude/plugins/cache/
└── formatter-company-tools/
    ├── v2.1.0-a1b2c3d/   # 現行バージョン
    └── v2.0.0-e4f5g6h/   # 旧版（7日後に自動削除）
```

| 特性 | Plugin Marketplace | 代替手段（clone 方式） |
|---|---|---|
| プロジェクトのファイルシステムから分離 | ✅ キャッシュにコピー | ❌ プロジェクト内ファイルを直接使用 |
| 旧バージョンの自動クリーンアップ | ✅ 7日後に自動削除 | ❌ 手動管理が必要 |
| 孤立バージョンを Glob/Grep の検索対象外に | ✅ 自動除外 | ❌ 検索結果に旧ファイルが混入 |
| `../` での外部ファイル参照を制限 | ✅ サンドボックス的に制限 | ❌ 制限なし（意図しない参照が可能） |

#### (4) 依存関係の自動解決

```json
// plugin.json
{
  "dependencies": [
    "helper-lib",
    { "name": "secrets-vault", "version": "~2.1.0" }
  ]
}
```

プラグイン A がプラグイン B を依存関係として宣言でき、`/plugin install A` 時に B も自動インストールされる。semver 制約指定も可能。代替手段では「このスクリプトを使う場合は事前にあのスクリプトも clone してください」というドキュメント上の指示しかなく、自動解決の仕組みがない。

#### (5) 永続データディレクトリ（CLAUDE_PLUGIN_DATA）

`${CLAUDE_PLUGIN_DATA}` はプラグインのアップデートをまたいで保持される永続ストレージ（`~/.claude/plugins/data/{id}/`）。**最後のスコープからアンインストールされたとき**自動削除される（複数スコープにインストールされている場合、最後の1つを削除するまでデータは保持される）。以下は SessionStart フックで `node_modules` をキャッシュする例：

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "diff -q \"${CLAUDE_PLUGIN_ROOT}/package.json\" \"${CLAUDE_PLUGIN_DATA}/package.json\" >/dev/null 2>&1 || (cd \"${CLAUDE_PLUGIN_DATA}\" && cp \"${CLAUDE_PLUGIN_ROOT}/package.json\" . && npm install)"
      }]
    }]
  }
}
```

代替手段では「プラグインに紐づいた永続データ」という概念がなく、`node_modules` 等の管理を個人が担う必要がある。

#### (6) バックグラウンドモニターの自動起動

```json
// monitors/monitors.json
[
  {
    "name": "error-log",
    "command": "tail -F ./logs/error.log",
    "description": "アプリのエラーログを監視",
    "when": "always"
  }
]
```

プラグイン有効時にバックグラウンドプロセスが自動起動し、stdout の各行を Claude への通知として届ける。`when: "on-skill-invoke:<skill-name>"` で特定スキル呼び出し時のみ起動することも可能。代替手段ではバックグラウンドプロセスの起動・管理・セッション終了時の停止を一切自動化できない。

#### (7) bin/ による分離された実行環境

```
my-plugin/
└── bin/
    └── my-tool    # プラグイン有効中のみ Bash ツールの PATH に追加される
```

プラグインの `bin/` 内の実行ファイルは**プラグインが有効な間だけ** Bash ツールの PATH に追加される。プラグインを無効化すれば自動的に PATH から消える。代替手段では実行ファイルをシステムの PATH に直接追加するため、使わなくなった後の PATH 汚染をクリーンアップできない。

#### (8) 名前空間による衝突防止

複数のプラグインが同名のスキルを持っていても `/plugin-a:hello` と `/plugin-b:hello` として共存できる。代替手段（`.claude` 共有）では全スキルが同一名前空間に入るため、`/commit` や `/review` のような汎用名が衝突する。

#### (9) 自動更新・バージョン追跡

| 機能 | Plugin Marketplace | 代替手段（clone 方式） |
|---|---|---|
| スタートアップ時の自動更新 | ✅ auto-update 機能 | ❌ `git pull` を手動実行 |
| バージョン固定（特定 SHA で pinning） | ✅ `sha` フィールド | △ git tag/submodule で可能だが UI なし |
| インストール済みバージョンの一覧表示 | ✅ `/plugin` UI | △ `git log` で確認可能（UI なし） |
| 古いバージョンの自動削除 | ✅ 7日後 | ❌ 手動 |

### 3-3. 代替手段でも同等に実現できること

以下の機能は代替手段でも実現可能なため、Plugin Marketplace の排他的優位性ではない：

| 機能 | Plugin Marketplace | 代替手段 | 補足 |
|---|---|---|---|
| スキルの git バージョン管理 | ✅ | ✅ clone 方式で同等 | |
| チームへの共有・更新通知 | ✅ | △ PR/Slack で代替可 | 更新通知の自動化は Plugin が優れる |
| フックの配布 | ✅ | △ `settings.json` コピーで可能（変数置換・bin/ 参照は不可） | |
| 複数プロジェクトへの適用 | ✅ user スコープ | △ submodule/symlink で可能 | |

### 3-4. 結論：「圧倒的優位性」が本当にある領域

Plugin Marketplace が代替手段に対して**技術的に代替不可能な**優位性を持つのは以下の 3 領域：

**★★★ 組織統制が必要な場合**  
`Managed Settings` + `strictKnownMarketplaces` + `enabledPlugins` の組み合わせにより、IT 管理者が全社員に特定プラグインを強制し・承認外プラグインをブロックできる。clone 方式では「ユーザーが任意に `git pull` を実行しないことを強制できない」ため**原理的に代替不可能**。

**★★★ 機密情報を含む設定の配布**  
`userConfig.sensitive: true` によるシステムキーチェーン格納。API トークンを settings.json に平文で書かずに配布できる仕組みは Plugin 固有。

**★★ バックグラウンドモニター・自動依存解決**  
バックグラウンドプロセスの自動起動管理と、プラグイン間の依存関係自動解決は Plugin の構造的特性であり、ファイル共有方式では実装できない。

**★ セキュリティサンドボックス**  
プラグインキャッシュへのコピーによる `../` パストラバーサル制限・旧バージョンの自動クリーンアップは、clone 方式にはないセキュリティ特性。

---

## Part 4: 適用方針

### 4-1. チーム共有のベストプラクティスまとめ

1. **Standalone から始める**: `.claude/skills/` で実験 → 安定したら Plugin に変換
2. **モノレポ構成**: Marketplace リポジトリにプラグインをまとめると管理が楽（`git-subdir` source で分散も可能）
3. **バージョン管理**: チームへの影響を制御したい場合は `version` を明示してバンプで更新を制御。実験用は省略して commit SHA 追随にする
4. **`extraKnownMarketplaces` を `.claude/settings.json` に追記**: リポジトリ信頼時にメンバーへ自動的にマーケットプレイスが提示される
5. **インストールスコープ**: チーム全体への必須ツールは `project` スコープ、個人の好みは `user` スコープ
6. **README.md を必ず含める**: スキルの一覧・使い方・インストール方法を記載
7. **予約名の回避**: `claude-code-marketplace` 等 Anthropic が予約している名前は使用不可

### 4-2. 利用規模別の推奨アプローチ

| 状況 | 推奨アプローチ |
|---|---|
| 個人または小規模チーム（数名規模を目安）、組織統制不要 | Standalone（`.claude/` 配置）で十分 |
| チーム規模が大きくなってきた（自動更新・バージョン管理が煩雑） | Plugin + 社内 Marketplace に移行 |
| 組織として使用ツールを統制したい、API トークンを安全に配布したい | Managed Settings + Plugin Marketplace が**唯一の選択肢** |

### 4-3. base-dev-kit-for-cc への適用方針案

現在の `.claude/skills/` 配下の `commit-and-pr`・`orchestrate` スキルは Standalone 構成。将来的に Plugin 化を検討する場合のシナリオ：

| シナリオ | 対応方針 |
|---|---|
| 社内チームへ配布 | 社内 Git サーバーにプライベート Marketplace を設置。`.claude/settings.json` に `extraKnownMarketplaces` を追記 |
| OSS コミュニティへ公開 | GitHub に public Marketplace リポジトリを作成し、Anthropic 公式 Marketplace へ申請 |
| 現時点はプロジェクト内のみ | Standalone のまま維持（Plugin 化の優先度は低い） |

現時点では Standalone で十分な規模のため、Plugin 化は不要。チーム利用拡大時に改めて検討する。
