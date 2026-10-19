# base-dev-kit-for-cc

Claude Code を最大限活用するための、言語中立・クロスプラットフォームな最小構成の
**共有 `.claude/` キット（`<Share>` リポジトリ）**。

> このリポジトリ自体の説明・使い方・MCP ポリシーはこの `README.md` に集約している。
> `README.md` は `--add-dir` での参照時に**ロードされない**ため、利用先リポジトリの文脈を
> 汚さずにリポ固有情報を置ける（README 隔離方式）。チーム共通の指示は `.claude/CLAUDE.md` に
> あり、こちらは利用先にロードされることを想定している。

> 📚 **設計・配布リリース手順・統制の知見（正本）**: 本キットのエコシステム（供給元 `base-dev-kit-for-cc` →
> 配布本体 `basic_dot_claude` → 雛型ハブ `basic_cc_project`）の調査・設計・**開発/テスト手順書**・
> 配布リリース設計・レビュー報告は [`cc-relative-info` の `claude-dir-sharing-governance/`](https://github.com/empty-can/cc-relative-info/tree/develop/claude-dir-sharing-governance) が正本。
> とくに手順書 §6/§7 が記述する `publish-share` / `check-assets` の実体は本リポの `scripts/` にあるため、
> **スクリプトを改修したら手順書との乖離に注意する**（過去に v1.7 で乖離修正の実績あり）。

---

## 2 つの利用方法

### 方法 A: コピー展開（テンプレートとして）

新規プロジェクトの土台として丸ごとコピーする。

1. このリポジトリをクローンまたはダウンロード
2. 次を新規プロジェクトにコピーする:
   - `.claude/` ―― 共有資産一式（ランチャーの部品 `.claude/launcher/` を含む）
   - `start_claude_code.sh` / `start_claude_code.ps1` ―― **ランチャー本体**。これが無いと `.claude/launcher/` は
     部品だけ届いて起動する手段が無い
   - `.gitattributes` ―― **改行の固定**。これが無いと `core.autocrlf=true`（Git for Windows 既定）の clone で
     `.sh` が CRLF 化し、`set -euo pipefail` 下の起動が `$'\r'` で落ちる
   - `.gitignore` / `.mcp.json` / `.env.example`
3. プロジェクト固有の `CLAUDE.md` を作る。雛型が要るなら
   [`basic_cc_project`](https://github.com/empty-can/basic_cc_project) の `CLAUDE.md.sample` を使う
   （**雛型はそちらに一本化**している ―― 2 か所に置くと必ず片方が陳腐化するため）
4. 不要なファイルを削除、必要な設定を追加

> **新規プロジェクトを始めるだけなら [`basic_cc_project`](https://github.com/empty-can/basic_cc_project) を
> 使うほうが早い**。あちらは `.claude/` を submodule（`basic_dot_claude`）として持つため、コピーではなく
> `git submodule update --remote` で共有資産を追従できる。方法 A は「submodule を持ち込みたくない」
> 場合の経路。

チーム共通の規約（コーディング / Git / マルチエージェント）は `.claude/CLAUDE.md` に入っており、
コピー後もそのまま機能する。ランチャーの使い方は後述の「起動ランチャー」節を参照。

### 方法 B: `--add-dir` でライブ参照（`<Share>` として）

日々の作業リポジトリから、このキットを**クローンせず参照だけ**して共有資産を読み込む。
本リポジトリを `<Share>` としてローカルに 1 つ置き、各作業リポジトリから次のように結合する。

| 共有したい資産 | 結合方法 |
|---|---|
| skills / commands / subagents | `--add-dir <Share>` |
| `.claude/CLAUDE.md` / `rules/` | `--add-dir <Share>` ＋ 環境変数 `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` |
| `settings.json`（permissions / hooks 等） | `--settings <Share>/.claude/settings.json` |

```bash
# 例: 作業リポジトリのルートで
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 \
  claude --add-dir /path/to/base-dev-kit-for-cc \
         --settings /path/to/base-dev-kit-for-cc/.claude/settings.json
```

> **background セッション**（agent view・`claude --bg`・`/bg`）にも共有 CLAUDE.md / rules を効かせるには、
> `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` を **OS の環境変数**（永続的なユーザー環境変数。Windows は
> ユーザー環境変数、macOS / Linux はログインシェルの profile）として設定する。background service（supervisor）は
> 最初に起動したシェルの env を継承するので、どの端末から起動されても届く（既に動いている service には、それが
> 起動した時点の env が使われる）。公式 memory は `~/.claude/settings.json` の `env` を勧めているが、本キットは
> 利用者に settings の `env` を使わせない方針（`docs/launcher/launcher-scripts-design.md` §3(6)）のため、この経路は使わない。
> `--add-dir` / `--settings` は background へ引き継がれるが、シェルの export・ランチャーの値は background
> セッションに確実には届かない（agent-view「Settings and provider」）。

> **注意**: `output-styles/`・hooks 単体は `--add-dir` では結合されない（これらを共有したい場合は方法 A の
> コピー展開を使う）。`commands/` は結合される（ライブリロードなし。同名なら作業リポ側が優先）。
> skills / commands / subagents は `project` 設定ソースとしてロードされるため、`--setting-sources` から
> `project` を外すと結合されない（permissions「Additional directories grant file access, not configuration」）。
> `settings.local.json` は個人用・共有不可。ローカル全リポジトリに効かせたい個人設定は `~/.claude/settings.json` に置く。
>
> **⚠ 方法 A と方法 B では効く settings キーが違う**。`--settings` は user settings に置けるキーなら何でも効く
> （settings「It can set any key your user settings file can set」）ため、方法 A（`.claude/` を project として配置）
> では無視されるキー ―― `check-assets` 3. が WARN するもの（`defaultMode` の `auto` / `bypassPermissions`、
> `autoMode`、`skipDangerousModePermissionPrompt` 等）―― が方法 B では有効になり、**配布方式で挙動が割れる**。
> 共有 `settings.json` にはこれらを入れず、各自に効かせたいなら `~/.claude/settings.json` に置く。
>
> **⚠ hook は方法 B では動作しない**。本キットの hooks（`.claude/hooks/*.py`）は
> `${CLAUDE_PROJECT_DIR}`（＝**作業リポジトリ**のルート）を基準にコマンドを組み立てるため、
> `--settings` で hook の定義だけを結合しても**スクリプトの実体が作業リポに存在せず起動に失敗する**。
> したがって **`.bat` の作業コピー機構と `.ps1` の保存形式検査は方法 A（コピー展開）専用**。
> 方法 B では `permissions.deny` による原本の保護だけが効く。`.bat` は**読めない**（スクリプトが見つからない
> `python` は exit 2 で終わり ―― 実測 ―― PreToolUse の exit 2 は Read を止める。Python 自体が無ければ
> `onFailure: "block"` が止める）が、編集は拒否されるので壊れない。

---

## 構成

```
.claude/                       # ← publish-share が配布するのはここだけ（payload）
├── CLAUDE.md                  # チーム共通指示（利用側にロードされる共有資産）
├── settings.json              # チーム共有のパーミッション・hooks 設定
├── .gitignore                 # 配布先での除外（個人実体・セッション成果物）※payload に同乗
├── .gitattributes             # 配布先での改行固定（既定 LF ＋ *.ps1 / *.bat だけ CRLF）※payload に同乗
├── launcher/                  # 起動ランチャーの部品（本体は repo ルートの start_claude_code.*）
│   ├── setup-environment.{sh,ps1}      # 環境変数のセットアップ（custom.env ロード＋統制 env を後勝ち固定）
│   ├── custom.env.template             # 利用者可変 env の雛型（→ .claude/custom.env にコピー）
│   └── option-settings.{sh,ps1}.template  # 利用者可変の起動オプション雛型（→ .claude/option-settings.* にコピー）
├── hooks/                     # settings.json が登録する hook（Python。無くても壊れない設計）
│   ├── bat_cp932_guard.py     # .bat（CP932）を壊さずに読み書きするための影＋書き戻し
│   └── ps1_bom_crlf_check.py  # .ps1 編集後に UTF-8 BOM + CRLF が保たれているか検査する
├── rules/
│   ├── coding-standards.md    # path-scoped コーディング規約（コードファイル編集時のみロード）
│   └── win-file-encoding.md   # path-scoped（.ps1/.bat 等の編集時のみロード）
├── skills/
│   ├── commit-and-pr/         # /commit-and-pr — コミット・プッシュ・PR 作成
│   ├── orchestrate/           # /orchestrate — マルチエージェント協調
│   ├── request-new-skill/     # /request-new-skill — 新規 skill 依頼フロー
│   ├── review-skill-request/  # /review-skill-request — skill 依頼レビュー
│   ├── pre-compact/           # /pre-compact — /compact 前の文脈保全（メモリ・未コミット確認）
│   └── win-file-encoding/     # /win-file-encoding — UTF-8/LF ⇄ CP932/CRLF の安全往復
├── agents/
│   └── code-reviewer.md       # code-reviewer サブエージェント
├── output-styles/
│   └── code-review.md         # コードレビュー出力フォーマット定義
├── templates/
│   └── skill-request/         # skill 依頼書テンプレート
└── settings.local.json.example  # 個人用ローカル設定の雛形

start_claude_code.{sh,ps1}     # 起動ランチャー本体（.claude/launcher/ を読んで claude を起動）
.gitattributes                 # ルートの改行固定（scripts/ と起動装置の .sh=LF / .ps1=CRLF）※.claude/ には効かない
.gitignore                     # ルートの除外設定（個人実体・作業一時物）
CLAUDE.md                      # ← 配布されない（このリポジトリを開発・リリースするための指示）
CLAUDE.local.md.example        # 個人用補足指示の雛形（コピーして CLAUDE.local.md に）
.mcp.json                      # プロジェクト固有の MCP サーバー設定（既定は空の雛型）
.env.example                   # 環境変数テンプレート
LICENSE                        # MIT
scripts/                       # ← 配布されない（このキットを開発・公開するためのツール）
├── check-assets.{sh,ps1}      # 公開前チェック：個人ファイル・セッション成果物の混入、設定キー等を検査
├── clean-test-env.{sh,ps1}    # クリーン隔離テスト：~/.claude を切り離し共有資産だけを検証
├── publish-share.{sh,ps1}     # 配布：指定 ref の .claude を共有本体 basic_dot_claude へ publish
└── publish-plugin.{sh,ps1}    # 配布：層2 plugin を Marketplace へ publish（ドラフト・未運用）
docs/                          # ← 配布されない（内部設計ドキュメント）
└── launcher/                  # ランチャーの構成設計・実装計画（設計書の正本）
```

> **`.claude/` の内と外**: `publish-share` は `.claude/` 配下だけを payload として取り出す。
> `start_claude_code.*` / ルート `.gitattributes` / `scripts/` / `docs/` は**配布されない**。
> ランチャーは「部品（`.claude/launcher/`＝配布される）」と「本体（ルート＝配布されない）」に
> 分かれている点に注意する。

## 起動ランチャー

環境変数と起動オプションを統制した状態で `claude` を起動する。

```bash
./start_claude_code.sh            # bash（要 bash 4.4+。macOS 同梱の 3.2 は不可）
.\start_claude_code.ps1           # PowerShell（5.1 / 7 両対応）
```

追加の引数はそのまま `claude` へ委譲される（例: `./start_claude_code.sh --model opus`）。
プロンプトを起動時引数で渡すときは、**フラグをすべてプロンプトより前に置く**（`--add-dir` のように複数の値を取る
フラグや値を省略できるフラグは、直後のプロンプトを値として取り込む。ランチャーは追加引数が全部プロンプト〔`-` で
始まらない〕のときだけ `--` を補ってこれを防ぐ。PowerShell で自分で区切るなら `'--'` と引用する）。

利用者が値を設定するファイルは**テンプレートからコピーして作る**（いずれも `.gitignore` 済みの個人実体）:

| 作るもの | テンプレート | 用途 |
|---|---|---|
| `.claude/custom.env` | `.claude/launcher/custom.env.template` | 環境変数（統制不要・非機微） |
| `.claude/option-settings.{sh,ps1}` | `.claude/launcher/option-settings.{sh,ps1}.template` | 起動オプション |

> **⚠ 置き場所に注意**: コピー先は **`.claude/` 直下**であって、テンプレートの隣（`.claude/launcher/`）ではない。
> 誤配置すると読み込まれない（ランチャーが警告する）。

> **⛔ 機微情報（API キー / 認証トークン / パスワード / 組織外秘の URL）は、`custom.env` を含む
> いかなるランチャーファイルにも書かない。** OS の環境変数として設定すること。`setup-environment` は
> 既知の機微キーを `custom.env` 内に見つけても**読み込まずに警告する**（規律を機構で担保している）。

チームで揃えたい値は、利用者が触らない場所に置く ―― env は `setup-environment.{sh,ps1}`、
起動オプションは `start_claude_code.{sh,ps1}` の `TEAM_OPTS` / `$TeamOpts`。ただしこれは
**既定値を揃える仕組みであって強制力はない**（起動時引数で上書きできる）。強制したい統制は
`settings.json` / managed settings 側で行う。

### 公開前チェック・テスト

`<Share>` を更新したら公開前に次を回す（詳細はスクリプト冒頭のコメント参照）。

```bash
bash scripts/check-assets.sh .                  # 個人ファイル・成果物混入・設定キーを機械チェック（CI 可）
bash scripts/clean-test-env.sh /path/to/share   # 自分の設定を切り離し共有資産だけで起動して動作確認
```

PowerShell では `scripts\check-assets.ps1 -Share .` / `scripts\clean-test-env.ps1 -Share <path>`。

`check-assets` は**検査対象の層で基準を変える**（同じチェック項目でも判定が違う）:

| 層 | 対象 | 基準 |
|---|---|---|
| **追跡基準** | リポジトリのルート（＝開発者の作業ツリー） | **Git 追跡されていれば FAIL**。gitignore 済みで実在するだけなら WARN |
| **実体基準** | 非リポジトリ（＝publish 時に取り出した payload の実体） | **実在すれば FAIL**。実際に配布される中身なので追跡状態は無関係 |

層は自動判定される（対象がリポジトリのルートなら追跡基準）。`publish-share` は `--payload` / `-Payload` で
実体基準を明示強制して呼ぶ ―― 「追跡解除したから大丈夫」は publish する ref を取り違えた瞬間に崩れるため、
配布経路では必ず実体で検査する。

検査項目:

- **個人ファイル** ―― `settings.local.json` / `CLAUDE.local.md` / `custom.env` / `option-settings.{sh,ps1}`
- **セッション成果物** ―― `.claude/reports/` `.claude/work/` `.claude/workspace/` `.claude/plans/`
  `.claude/agent-memory-local/` `work_instructions.txt` `.claude/.bat-shadow/` `.claude/worktrees/`
  `.claude/scheduled_tasks.json`（**この一覧が正本**。`check-assets` の 2-c 配列がそれで、ルートと `.claude/`
  双方の `.gitignore` はこれに追随させる）。置き場所が固定でない plugin eval の結果 `*/evals/results/` は 2-c'
  （`.claude/worktrees/` の中は数えない。`Worktrees/` 等の大文字小文字違いも中は数えず、それ自体を 2-c が大文字小文字
  だけが違う成果物として報告する。ジャンクション・シンボリックリンクは辿らない）
- **配布先の統制ファイルの不在** ―― `.claude/.gitignore` / `.claude/.gitattributes`。ミラー処理は payload に
  無いファイルを配布先から削除するため、これらを欠いた ref を publish すると**配布先の除外設定・改行保護が
  黙って消える**（payload では FAIL / 作業ツリーでは WARN）
- **`.claude/CLAUDE.md` の不在** ―― **FAIL**。同じ理由で、これを持たない ref を publish すると配布先の
  共通 CLAUDE.md が消える。

**名前は二段階で照合する**（セッション成果物 2-c / 2-c' と、`settings.json` の `env` のうち project / local から
設定できない変数名 ＝ 3. の E 区分）。まず完全一致（大文字小文字を区別）で比べ、一致しなければ ASCII（A〜Z）だけを
小文字に畳んで比べる。

| 照合の結果 | 判定 |
|---|---|
| 完全一致 | 上の基準のまま（成果物: 追跡基準は追跡で FAIL・未追跡の実在で WARN、実体基準は実在で FAIL。env キー: WARN） |
| 大文字小文字だけが違う成果物（`.claude/Reports/`・`Evals/Results/` 等） | **実体基準は FAIL・追跡基準は WARN**（別の文言で、実際のパスを示す） |
| 大文字小文字だけが違う env キー（`systemroot` 等） | **層によらず WARN**（別の文言で、実際のキーを示す） |

大文字小文字だけが違うものは、区別する OS では正当な別物でありうる一方、区別しない Windows では `.gitignore` を
すり抜けた成果物（env なら同じ変数）でありうる。`publish-share` は **FAIL でしか止まらず**、WARN は確認プロンプトを
経て公開まで進むため、成果物は**配布する実体（payload）では FAIL にして publish を中止**する（公開前に名前を直すか
除外する）。開発中の作業ツリー（追跡基準）では WARN に留めるので、読んで意図したものか確かめること。env キーは
配布物の流出ではないため、層によらず WARN のまま。ただし `settings.json` の**同じオブジェクト内**に完全一致または
大文字小文字だけが違うキーが並ぶもの（`systemroot` と `SystemRoot` 等。`env` 以外の階層も同じ）は、照合の前に
**重複キーとして層によらず FAIL** にする ―― どちらの値が効くかが読み手で変わる（python と PowerShell は完全一致の
重複を黙って後勝ちにし、PowerShell は大文字小文字だけの違いを拒否する）うえ、Windows の環境変数名は大文字小文字を
区別しない。

### 配布（publish）

`.claude/` を共有本体 `basic_dot_claude` へ反映する。**publish はこのスクリプトでしか push しない**。

```bash
bash scripts/publish-share.sh --ref <ref>       # 例: --ref v1.0.0
```

PowerShell では `scripts\publish-share.ps1 -Ref <ref>`。

- **`--ref` は必須**（既定値は無い）。grooming 済み・リリースタグ済みの ref を明示すること。
  かつて既定は `main` だったが、未 grooming の ref を無自覚に publish する事故を招くため撤去した。
- publish 前に `check-assets` が**実体基準で**自動実行され、成果物が混入していれば **FAIL して中止**する。
- symlink（mode 120000）を含む ref は**中止**する（zip 経由では中身がターゲットのパス文字列に化けるため）。
- payload の取り出しは `core.autocrlf` を無効化して行う。付けないと `git archive` が publisher のローカル
  設定で改行を変換し、**同じ ref でも publish するマシン次第で配布内容が変わる**。
- 続いて `/security-review` 実行済みかの手動確認が入る。
- 成功後は参照ハブ `basic_cc_project` で submodule を bump する（コマンドは実行後に表示される）。

> **feature ブランチからの publish は検証用に限る**。本番の共有本体へ向けるのは、
> develop → main へ統合しタグを打った ref だけにすること。

---

## 含まれるもの

### Skills（スラッシュコマンド）

| コマンド | 説明 |
|---|---|
| `/commit-and-pr` | 変更をコミットして PR を作成 |
| `/orchestrate` | 複数エージェントを協調させる（並列調査・段階的処理・役割分担） |
| `/request-new-skill` | 新しい skill の依頼書テンプレを生成する |
| `/review-skill-request` | skill 依頼書をレビューし実装方針をまとめる |
| `/pre-compact` | `/compact` 前にメモリ・未コミット変更・保留タスクを整理し文脈を保全する |
| `/win-file-encoding` | CP932 ⇄ UTF-8 の**一括変換・事前検査**（移行作業用の手動ツール。日常の `.bat` 編集は下記の hook が自動処理するため不要） |

### Windows 向けファイルの文字コード

**原則は一律 UTF-8。CP932 は `.bat` だけの例外**。「Windows 向けは一律 CP932」は成立しない ―― PowerShell 7 は
既定が UTF-8 で CP932 の `.ps1` を読めず、Windows PowerShell 5.1 は BOM 無し UTF-8 を CP932 と誤読する。
**5.1 と 7 の両方で読める形式は UTF-8 + BOM だけ**。改行は `.gitattributes` が拡張子ベースで固定する。

| 拡張子 | 保存形式 | Claude の扱い |
|---|---|---|
| `.ps1` / `.psm1` / `.psd1` | UTF-8 + BOM + CRLF | 普通に読み書きしてよい（**編集後に BOM/CRLF を hook が検査**する。`Write` ツールは CRLF を保持せず新規作成では BOM も付かないため、新規作成すると必ず壊れる） |
| `.bat` | CP932 + CRLF・BOM なし | **原本には触らせない**（下記） |
| `.cmd` | 使用禁止（`.bat` に一本化） | `.bat` と同じく `permissions.deny` で編集を拒否 |
| `.reg` | スコープ外 | `permissions.deny` で R/W 禁止 |
| `.ini` | **規定しない** | `tox.ini` / `pytest.ini` のように **UTF-8 が正しい `.ini` が広く存在する**ため、拡張子で一律に扱えない。**deny もしない**（Win32 プロファイル用途の CP932 な `.ini` を扱うときは都度バイト列で確認する） |

`.bat` は CP932 なので Claude のツールで直接読むと文字化けする。`Edit` は非 UTF-8 ファイルへの変更を拒否する
（v2.1.296〜。tools-reference「Non-UTF-8 files」）が、ASCII だけの `.bat` は UTF-8 としても有効なので通ってしまい、
日本語を足すと UTF-8 で保存されて壊れる。`Write` による上書きは docs では UTF-8 化、changelog 2.1.299 では拒否と
されていて食い違うが、v2.1.302 の実測（`.txt`）は changelog のとおりで、日本語を含む CP932 ファイルへの `Write` は
`File is not valid UTF-8` で拒否されバイト列は変わらない（ASCII だけのファイルは `Write` も通り、日本語は UTF-8・LF
で書かれる。新規作成も UTF-8）。そこで `.claude/hooks/bat_cp932_guard.py` が**原本を隠して UTF-8 の作業コピーを見せる**:
`Read` は自動で作業コピー（`.claude/.bat-shadow/`・`.gitignore` 済み）へ差し替わり、そこを編集して保存すると
**CP932 + CRLF で原本へ書き戻される**。CP932 に符号位置の無い文字（`⚠` `✓` 等）があれば書き戻しを中止して
原本を保全する（fail-closed）。原本への `Edit` / `Write` は `permissions.deny` で拒否される
（hook は Python が無い環境では既定で素通りする。`.bat` の Read ガードには `"onFailure": "block"`（hooks「Block the
action when a hook fails」・v2.1.295〜）を付けてあり、hook が起動できない・タイムアウトした等のときは `.bat` の
Read 自体を止める（対応する最低版は v2.1.295 で、それ未満は対象外。「動作環境」参照）。いずれにせよ
**ハードなガードは permission 側が担い、hook は利便性を担う**）。
`.bat` をシェルやスクリプト経由で作成・編集するのは禁止（hook が守れない）。例外は CP932 + CRLF で書くキット同梱の
2 つだけ: `bat_cp932_guard.py new`（新規作成）と、`win-file-encoding` skill の `convert_encoding.py --to-win`
（UTF-8 で保存されてしまった `.bat` の修復・一括変換。実行後は作業コピーが古くなるので原本を Read し直す）。
`Edit` / `Write` の拒否メッセージが勧める iconv・`Set-Content -Encoding`・「消してから Write」には `.bat` では従わない。
手順の詳細は `.claude/rules/win-file-encoding.md`。**Python が必要**（CPython 3.x）。

### Sub-agents

| エージェント | 説明 |
|---|---|
| `code-reviewer` | コード変更の品質・セキュリティ・保守性レビュー |

### MCP サーバー

**`.mcp.json` の中身は空**（`{"mcpServers": {}}`）＝**サーバー定義そのものは同梱していない**。
どのサーバーを使うかはプロジェクトごとに決めるため、`.mcp.json` は雛型として置いてある。

`.claude/settings.json` の `enabledMcpjsonServers` には、このキットが想定する 4 つを
**あらかじめ許可リストとして**書いてある（定義を `.mcp.json` に足した時点で有効になる）:

| サーバー | 用途 |
|---|---|
| `anthropic-docs` | Anthropic / Claude ドキュメント検索 |
| `context7` | ライブラリドキュメント取得 |
| `fetch` | 汎用 URL 取得 |
| `github` | GitHub リポジトリ・Issue・PR の参照 |

MCP サーバーの起動には Node.js（v18 以上）が必要。GitHub MCP の認証には `GITHUB_TOKEN`
環境変数（OS レベルで設定）が必要。

#### このキット開発時の MCP ポリシー

本リポジトリ（base-dev-kit-for-cc）を**開発・改善する作業**では、MCP の利用に制限を設けない。
各種 MCP サーバーの調査・評価・活用を積極的に行う。コピー展開先のプロジェクトでは、
`CLAUDE.md` の「MCP ポリシー」セクションに利用可否を改めて記述すること。

---

## 動作環境

- [Claude Code](https://claude.ai/code) CLI ―― **v2.1.295 以上**。`.bat` の Read ガードの `"onFailure": "block"`
  （hook が起動できない・タイムアウトした等のとき Read を止める）の導入版であり、これを最低版とする
  （v2.1.295 未満は対象外）。hook の `if` 条件（Read/Edit/Write のパス指定）は v2.1.176 以上で正しくマッチするが、
  これは v2.1.295 に包含される（v2.1.176 未満では **hook が一度も起動しない**〈v2.1.85〜2.1.175〉か、
  条件を無視して毎回起動する〈〜v2.1.84〉）。`permissions.deny` は版に関係なく効くため原本は壊れない。
  **推奨は v2.1.299 以上**: Edit が非 UTF-8（CP932 の `.bat` を含む）への変更を拒否し（v2.1.296）、changelog 2.1.299
  によれば Write も Shift-JIS 等を黙って UTF-8 化しなくなる（docs 未反映。v2.1.302 の実測では、日本語を含む CP932
  ファイルへの Write は拒否された。ASCII だけのファイルは通る）。
- Node.js v18 以上（MCP サーバー用）
- **Python 3.10 以上**（`python` として PATH にあること）―― `.bat` を扱う hook と `win-file-encoding` skill 用。
  無くても壊れないが、`.bat` は読めなくなる（Read ガードの `onFailure: "block"` で `.bat` の Read が
  止まる。`permissions.deny` により編集は常に拒否されるので、原本が壊れることはない）。
  macOS / Linux で `python3` しか無い場合は hook が毎回起動に失敗する ―― `.bat` の Read は止まり、
  PostToolUse の `.ps1` 検査は素通りする（`.bat` は Windows 専用資産なので実害は無いが、気になる場合は
  `python` を PATH に通すか hook を無効化する）
- Git

---

## 拡張オプション

以下はデフォルト無効。必要に応じて有効化する。

### Sandbox モード（コード実行の隔離）
`.claude/settings.json` の `"sandbox": { "enabled": true }` で有効化（セッション内の `/sandbox` でも切り替えられる）。
**ネイティブ Windows では動作しない**（コマンドは隔離されずに実行される。Windows で使うなら WSL2 内で Claude Code を
動かす）。対象はシェルコマンド（Bash / PowerShell / Monitor）だけで、ファイルツール・MCP・hooks は隔離の外。
詳細: https://code.claude.com/docs/en/sandboxing

### MCP サーバー接続

| スコープ | 設定場所 | 用途 |
|---|---|---|
| グローバル（ユーザー全体） | `~/.claude.json` の `mcpServers` | 全プロジェクト共通のサーバー |
| プロジェクト固有 | `.mcp.json` の `mcpServers` | このプロジェクト専用のサーバー |

グローバル MCP のプロジェクト別 有効/無効は `~/.claude.json` の該当プロジェクトエントリ内
`enabledMcpjsonServers` / `disabledMcpjsonServers` で制御する。詳細: https://code.claude.com/docs/en/mcp

### output-styles（出力フォーマット統一）
`.claude/output-styles/code-review.md` に設定済み。追加は `.claude/output-styles/<name>.md` に定義する。

### Agent Teams（実験的）
環境変数 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` で有効化。現在実験段階のため本番利用は非推奨。
チームを組まずに自分で動かしているセッション間で知見を渡すだけなら、cross-session messaging（v2.1.224〜、
ネイティブ Windows は v2.1.234〜）で足りる（agent-teams「check whether a lighter option does the job」）。
詳細: https://code.claude.com/docs/en/agent-teams

### Plugin 化
複数プロジェクトで設定を共有する別手段として、`.claude/` の一部を Plugin として切り出す方法もある。
詳細: https://code.claude.com/docs/en/plugins/overview

---

## ライセンス

[MIT](LICENSE)
