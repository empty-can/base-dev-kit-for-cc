# Claude Code ランチャースクリプトコンセプト・構成設計

> **【正本・IM-8】本書は設計書の正本**（実装と同一 PR で共進化する側）。
> research-by-cc 側の同名文書（`reports/04.資産インベントリ・統合/04.ランチャースクリプト実装/`）は
> 2026-07-05 時点の**スナップショット**であり、以後更新しない。差分が出たら本書が正。
> 根拠: Fable クロスレビュー統合 IM-8（2 リポ二重管理によるドリフトを実検出）。
>
> 実装の詳細・判定木・レビュー反映状況は [`launcher-implementation-plan.md`](launcher-implementation-plan.md) を参照。
>
> 変更履歴は [`【別紙】launcher-scripts-design変更履歴.md`](【別紙】launcher-scripts-design変更履歴.md) を参照

## 1. 構成ファイルと配置場所

1. `<repo-root>\start_claude_code.sh/.ps1`
2. `<repo-root>\.claude\launcher\setup-environment.sh/.ps1`
3. `<repo-root>\.claude\launcher\option-settings.sh/.ps1.template`
4. `<repo-root>\.claude\launcher\custom.env.template`
5. `<repo-root>\.claude\option-settings.sh/.ps1`
6. `<repo-root>\.claude\custom.env`

## 2. 構成ファイルの関係

拡張子の無いファイルはスクリプトファイル。

```txt
(1.) start_claude_code ─┬─(読み込み)→ (2.) setup-environment ─(読み込み)→ (6.) custom.env
                        │                                                        ↑
                        │                                                  （コピー作成）
                        │                                                        ❘
                        │                                          (4.) custom.env.template
                        │
                        └─(読み込み)→ (5.) option-settings
                                            ↑
                                      （コピー作成）
                                            ❘
                              (3.) option-settings.template
```

※ option-settings(5) をロードするのは start_claude_code(1)（起動コマンド組立のため）。setup-environment(2) は名称どおり「環境変数のセットアップ」に専念し、custom.env(6) のみをロードする。

### 2.1 各構成ファイルの管理場所

| #    | ファイル名                 | Git 追跡対象？ | 補足                                                      |
| ---: | :------------------------- | - | :--------------------------------------------------------------------- |
| (1.) | `start_claude_code`        | Y | 層1 `basic_cc_project` リポジトリで配布する資産                        |
| (2.) | `setup-environment`        | Y | 層1 `basic_dot_claude` リポジトリで配布する資産                        |
| (3.) | `option-settings.template` | Y | 同上                                                                   |
| (4.) | `custom.env.template`      | Y | 同上                                                                   |
| (5.) | `option-settings`          | N | 利用者がテンプレートから手動でコピーして拡張子を変更し利用するファイル |
| (6.) | `custom.env`               | N | 同上                                                                   |

## 3. 各ファイルの役割

### 3.1 `start_claude_code.sh/.ps1`

#### 3.1.1 機能的役割

- 環境変数や起動時オプションを設定した他のファイルをロードし、それらが適用された状態で Claude Code を起動する
- 必要があれば、Claude Code起動のために必要なロジック的な処理も実施する（ロードした起動時オプション群から起動コマンドを組み立てる処理、など）

#### 3.1.2 利用者向役割

利用者のユースケースは、ランチャーから `claude` を起動する **foreground 起動** と、ランチャーを通らずに別のプロセスとして起動される **background 起動** の 2 つに分かれ、ランチャーの効き方が違う。

- **foreground 起動**（ランチャースクリプトから `claude` を起動する通常の使い方）
    - ワンクリックで、適切な値が設定された環境変数と必要な起動時オプションが指定された状態で Claude Code が起動する。
    - 環境変数はプロセス単位（ローカルスコープ）なので、他のアプリケーションや **別途起動した** Claude Code プロセスには影響しない。
    - 起動前の検出（§5.5。ネットワークパスの `--add-dir`・キットの前提が崩れる起動オプション）が効くのはこの経路だけ。
- **background 起動**（`/bg`・`←`・`/fork`・`claude --bg`・agent view からの dispatch・agent teams の teammate など。ランチャーを通らずに別のプロセスとして起動されるセッション。§5.1）
    - ランチャーは通らない。ランチャーの設定のうち background に届くのは §5.1.3 の表の経路だけ ―― 引き継がれる起動時の構成フラグ（`--add-dir`・`--setting-sources` 等。§5.1.3 に列挙）、dispatch 元シェルの環境変数のうち列挙されたもの、そして supervisor が最初に起動されたときの環境（このランチャーで起動したセッションが最初に supervisor を起動した場合に限り、service がその環境を継承して後続の background セッション〔別の端末から dispatch したものを含む〕へ波及する。起動順次第で確実ではない ―― 2026-10-20 実測。ゲートウェイ変数が届く条件は §5.1.3 の表のとおり）。
    - background にも効かせたい値は、settings の `env` ではなく OS の環境変数で設定する（§3.6.2・§5.1.3）。
    - background 起動に関わる制約の網羅的な整理・検証・方針は §5。

### 3.2 `setup-environment.sh/.ps1`

#### 3.2.1 機能的役割

- 利用者が値を都度設定変更できる`custom.env`の読み込み + 利用者が値を変更不要or変更してはいけない（＝利用メンバー間で決まった値を使うルールになっている）環境変数の値を後勝ち設定で保証する。

#### 3.2.2 利用者向役割

- 存在を意識する必要が無い。強いて言えば決まった値を使うルールになっている環境変数の設定に気を遣う必要性から解放される。

### 3.3 `option-settings.sh/.ps1.template`

#### 3.3.1 機能的役割

- 利用者が実際に値を設定する`option-settings.sh/.ps1`の雛型。Claude Codeのバージョンアップでオプション項目が追加になったり廃止になったりした場合に更新される。

#### 3.3.2 利用者向役割

- オプション項目が追加になったり廃止になったりした場合に更新されるので、その変更を知るきっかけになるとともに、差分だけ`option-settings.sh/.ps1`に反映するという最小限の手間でClaude Codeの仕様変更に追随できる。
- 利用者が値を設定できる起動時オプションの全量が簡単なコメント付きで記載されており、公式ドキュメントを参照せずに利用できる
- 環境変数と異なり統制を取る必要があるものは少ないが、公式の既定値を持つ起動時オプションはその値をキーごとのコメントに記してある（launcher README 付録 A）。テンプレは全キーがコメントアウトされた状態で配布され、複写しただけでは何も有効にならない。既定値のまま使うキーは行頭の `# ` を外すだけでよい（当初の実装計画 §3 (4) にあった「設定済み＆有効化」は実装では採っていない）。

### 3.4 `custom.env.template`

#### 3.4.1 機能的役割

- 利用者が実際に値を設定する`custom.env`の雛型。Claude Codeのバージョンアップで環境変数が追加になったり廃止になったりした場合に更新される。

#### 3.4.2 利用者向役割

- 環境変数が追加になったり廃止になったりした場合に更新されるので、その変更を知るきっかけになるとともに、差分だけ`custom.env`に反映するという最小限の手間でClaude Codeの仕様変更に追随できる。
- 利用者が値を設定できる環境変数の全量が簡単なコメント付きで記載されており、公式ドキュメントを参照せずに利用できる
- 全キーがコメントアウトされた状態で配布される（複写しただけでは環境変数は 1 つも設定されない）。値・既定・注意はキーごとのコメントに記されているので、使うキーだけ行頭の `# ` を外して値を設定する。

### 3.5 `option-settings.sh/.ps1`

#### 3.5.1 機能的役割

- `start_claude_code.sh/.ps1`から読み込まれ、ここで定義した**起動時オプション**が`claude`コマンドの引数として組み立てられる（環境変数ではない）。

#### 3.5.2 利用者向役割

- 起動時オプションについて使いたいと思ったらこのファイルを見れば良い、という存在なので、毎度同じような調べものをしたりClaude Codeに質問したりする必要が無くなる。
- 本来なら`claude`コマンドに続くように記述する必要がある起動時オプションについて、スクリプトの連想配列形式で定義できる。不要なオプションは連想配列の該当行をコメントアウトするだけでよい。

### 3.6 `custom.env`

#### 3.6.1 機能的役割

- `setup-environment.sh/.ps1`から読み込まれ、設定された環境変数が反映される（ただし`setup-environment.sh/.ps1`内でハードコードされたユーザカスタマイズ不可の環境変数の値は後勝ちで上書き反映させない）

#### 3.6.2 利用者向役割

- 特にリポジトリでの作業の切り替えに合わせて都度変更するような環境変数について、OSの環境変数を設定してプロンプトを再起動する手間を踏まなくて済むようにする（claudeの再起動だけで反映される）
- `settings.json`系ファイルに`env`要素を設定しない習慣を根付かせる（うっかりcommit/pushしたり、`settings.local.json`に置いてClaude Codeから読めてしまう状態を作らない）。※ background セッションにも効かせたい値は、settings の `env` ではなく OS の環境変数（永続的なユーザー環境変数）で設定する（§5.1.3）。組織で固定する値だけは managed settings の `env`（管理者の経路）
- **機微情報（分類A: APIキー / 認証トークン / パスワード / 組織外秘URL）はこのファイルにも書かない**。OSの環境変数として設定する。`setup-environment`は分類Aの既知キーを検出すると**読み込まずに警告**する（実装計画 §5 / §6-bis）

## 4. 配布レール（publish の実態）

構成ファイルは `.claude/` の内外にまたがるため、**配布レールは 2 本**に分かれる（`publish-share` は `.claude/` 配下しか archive しない）。

| レール | 対象 | 配布先 |
|---|---|---|
| payload（`publish-share`） | `.claude/launcher/*`・`.claude/.gitignore`・`.claude/.gitattributes` | C-BDC（`basic_dot_claude`） |
| ルート直コミット | `start_claude_code.{sh,ps1}`・ルート用 `.gitattributes` | C-BCP（`basic_cc_project`） |

`.claude/.gitignore` と `.claude/.gitattributes` を `.claude/` 配下に置くのは、**配布先でも個人実体の除外と改行固定を効かせる**ため。C-BDK ルートの同名ファイルは payload に乗らず、配布先には届かない（Fable クロスレビュー CR-1）。

## 5. background 起動・foreground 起動とランチャーの関係

本節は、§3.1.2 の 2 つのユースケース ―― ランチャーから `claude` を起動する foreground 起動と、ランチャーを通らずに別のプロセスとして起動される background 起動 ―― について、ランチャーの効果がどこまで届くかと、それに伴う制約を整理し、ランチャーの方針を決める。5.1 で、どの起動がどちらに属するかと background 起動に届く経路を整理し、5.2 で、background 起動のセッションまで起動装置に通す公式の経路（企業ランチャー）との関係を判定する。5.3〜5.5 は foreground 起動でランチャーが行うこと（引数の組み立て・出力・起動前の検出）とその制約である。確認時点（何をいつ、どの版の docs で確かめたか）は各小節の末尾に書く。決定の経緯は別紙（変更履歴）にまとめる。

ランチャーが効くのは、**foreground 起動で自分が起動した `claude` プロセスと、そのプロセスから生成される SubAgent** まで（5.1.1）。

### 5.1 foreground 起動と background 起動の整理

本小節は、Claude Code のセッションや SubAgent を起動するそれぞれのしかたが、§3.1.2 の foreground 起動と background 起動のどちらに属するか（ランチャーの効果が届くか）を整理し（5.1.1・5.1.2）、background 起動に届く経路を示す（5.1.3）。

#### 5.1.1 判定の原則

- **foreground 起動の側**: ランチャーが起動した `claude` プロセスと、そのプロセスから生成されるもの。ランチャーが設定した環境変数と起動オプションがそのまま効く。
- **background 起動の側**: ランチャーを通らずに別のプロセスとして起動されるセッションと、その中で動くもの。ランチャーの効果は 5.1.3 の経路で届くものに限られ、確実には届かない。
- **セッションの中で動くものは、そのセッションと同じ側に属する**。Agent ツールで起動する SubAgent は、foreground 実行か background 実行か（既定では主会話から起動した SubAgent は background で動く）、入れ子（既定で主会話の下 3 層まで）か、会話を引き継ぐ fork か、dynamic workflow の `agent()` が起動するものかを問わず、起動したセッションの中で動き、別のセッションにはならない（公式: [sub-agents](https://code.claude.com/docs/en/sub-agents)「Subagents work within a single session」、[agent view](https://code.claude.com/docs/en/agent-view#monitor-sessions-with-agent-view)「Subagents and teammates a session spawns aren't listed as separate rows」）。
  - ランチャーから foreground 起動したセッションがオーケストレータとして起動した SubAgent と、その SubAgent がさらに起動した SubAgent は、foreground 起動の側にあり、セッションが受け取ったランチャーの環境変数と起動オプションのもとで動く（主会話が読む CLAUDE.md の階層・`--add-dir` のディレクトリ・`CLAUDE_CODE_SUBAGENT_MODEL` や `CLAUDE_CODE_AUTO_COMPACT_WINDOW` などの環境変数が SubAgent にも効くと公式が記す）。
  - background セッションの中で起動した SubAgent は background 起動の側で、5.1.3 の経路で届いたものだけが効く。
- SubAgent と違って**別のセッションになるものは、background 起動の側**に置く。`/fork`（agent view が有効なとき）は会話を複製した background セッションを起動する。agent teams（実験的機能。既定で無効）の teammate は、lead のセッションが自分の binary から起動する別の Claude Code インスタンスで、supervisor は介さない。lead の `--setting-sources` は引き継がれるが、環境変数の引き継ぎは公式に記載が無く未確認のため、5.1.3 の表の対象にしていない。

#### 5.1.2 起動のしかたごとの分類

| 起動のしかた | 側 | 根拠・補足 |
|---|---|---|
| ランチャー（`start_claude_code.*`）から `claude` を起動する（対話起動・`-p`・スクリプトからの起動） | foreground 起動 | ランチャーが起動したプロセスそのもの |
| そのセッションが Agent ツールで起動する SubAgent（foreground 実行・background 実行） | foreground 起動（セッションと同じ側） | セッションの中で動く。既定では background 実行 |
| SubAgent が起動する SubAgent（入れ子。既定で主会話の下 3 層まで） | 同上 | 同上 |
| fork（`/subtask`・fork モードで Claude が起動するもの。agent view が無効なときの `/fork` も同じ） | 同上 | 会話を引き継ぐ SubAgent |
| dynamic workflow（`ultracode`・`/deep-research` 等）の `agent()` が起動する SubAgent | 同上 | 公式: 「orchestrates many subagents」。セッションを終了すると run は続かない |
| `/bg`・`←`（今のセッションを background へ送る） | background 起動 | supervisor（background service）配下の別プロセスとして起動し直される |
| `/fork`（agent view が有効なとき） | background 起動 | 会話を複製した background セッションを起動する |
| `claude --bg`・agent view からの dispatch | background 起動 | supervisor 配下の別プロセス |
| background セッションの中で起動する SubAgent | background 起動（セッションと同じ側） | — |
| agent teams の teammate（実験的機能。既定で無効） | background 起動 | lead が自分の binary から起動する別の Claude Code インスタンス。supervisor は介さない。lead の `--setting-sources` は引き継ぐ。環境変数の引き継ぎは公式に記載が無く未確認 |
| Desktop の `/resume` で開いた CLI セッション | background 起動（ランチャーを通らない） | ランチャーの env は無い（5.1.3 の表） |
| `claude-cli://` の deep link で開いたセッション | background 起動（ランチャーを通らない） | deep link で開いたセッションは、ランチャー無しで新しい端末で始まる（公式: corporate-launcher「Processes that start outside the launcher」。登録された `claude-cli://` のハンドラが開く ―― deep-links）。ランチャーの env と起動オプションは無い |
| `CLAUDE_CODE_PROCESS_WRAPPER` で起動装置に通す | 本ランチャーの対象外 | Windows では無視される（5.2） |

確認時点: 5.1.1〜5.1.2 の SubAgent・fork・teammate の記述と deep link の行は、2026-11-03 に v2.1.317 の docs で確かめた（差分なし。sub-agents で変わったのは `/btw` の説明の 2 か所だけで、agent-view・agent-teams・workflows・corporate-launcher・deep-links はページごと v2.1.316 と同じ）。

#### 5.1.3 background 起動に届く経路

background 起動のうち supervisor 配下のセッション（`/bg`・`←`・`/fork`・`claude --bg`・agent view からの dispatch）は、supervisor（background service）配下の別プロセスとして起動し直され、構成を次の経路から読む（公式: [agent view「Settings and provider」](https://code.claude.com/docs/en/agent-view#settings-and-provider)、[network-config「Apply network settings to background agents」](https://code.claude.com/docs/en/network-config)）。agent teams の teammate は supervisor を介さないので、この表の対象ではない（5.1.1）。

| 経路 | background に届くか | 備考 |
|---|---|---|
| 実行ディレクトリの settings（`env` ブロック含む） | 届く | 公式は個人の `~/.claude/settings.json` の `env` を勧めるが、**キットは §3.6 の方針によりこの経路を利用者に使わせない**。組織で固定する分類B/C は managed settings の `env`（管理者の経路）。settings の `env` はシェルの export より優先される |
| 起動時の構成フラグ | 列挙されたものだけ | `--mcp-config` `--strict-mcp-config` `--settings` `--setting-sources`（v2.1.281〜） `--add-dir` `--plugin-dir` `--fallback-model` `--allow-dangerously-skip-permissions`。セッション中に `/add-dir` で足したディレクトリも届く |
| dispatch 元シェルの env | 列挙されたものだけ | `PATH`、`CLAUDE_CODE_USE_BEDROCK` / `CLAUDE_CODE_USE_VERTEX`、`ANTHROPIC_DEFAULT_*_MODEL`、`CLAUDE_CODE_EXTRA_BODY`。ゲートウェイ（`ANTHROPIC_BASE_URL` と一緒に export した `ANTHROPIC_CUSTOM_HEADERS`・資格情報、プロバイダのゲートウェイ URL と `CLAUDE_CODE_SKIP_*_AUTH` の組）は、supervisor 自身が同じゲートウェイを持つシェルから起動されていて、かつ自分のセッションの background 化・今いるディレクトリへの dispatch・wake・`claude respawn` のときに限る。別のフォルダから dispatch / wake したセッションには渡らず、`No LLM gateway` で失敗する（v2.1.302〜この表示） |
| supervisor を最初に起動したシェルの env | 継承される（起動順次第・2026-10-20 実測） | supervisor は全端末で共有され、それを立ち上げたプロセスの環境を継承する。上の行に無い env はこの経路で決まり、dispatch 元に同名の値があっても supervisor 側の値が使われる。ランチャー経由の `claude` が supervisor を立ち上げた場合に限り、以後は別の端末から dispatch したセッションにもランチャーの env が届く。素のシェル等が先に立ち上げていると、ランチャー経由の `claude --bg` でも届かない＝**確実ではない**。その env は supervisor が止まるまで使われ、auto-update による自己再起動でも変わらない（手順と結果は実装計画 §8-ter (1)） |
| `custom.env` / `setup-environment` の値 | **確実には届かない** | dispatch 元シェルの行に入るもの（`PATH`・プロバイダ選択等）だけは届く。それ以外は、ランチャー経由の `claude` が supervisor を立ち上げた場合だけ届く（上の行）。例: `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`（分類C）が欠け、`--add-dir <Share>` は引き継がれるのに `<Share>` の CLAUDE.md / rules がロードされない |
| system prompt 置換・`--tools` 許可リスト | 引き継がれない | これらで起動したセッションは `/fork` を拒否される |
| Desktop の `/resume` で開いた CLI セッション | ランチャーの env は無い | Windows の Desktop はユーザー／システム環境変数を継承し、PowerShell プロファイルは読まない |

**帰結**: §3.6 の「`settings.json` 系に `env` を置かない習慣」は background でも例外にしない。background にも効かせたい値は **OS の環境変数**（永続的なユーザー環境変数。Windows はユーザー環境変数、macOS / Linux はログインシェルの profile）で設定する。supervisor は最初に起動したシェルの env を継承するので、OS の環境変数ならどの端末から起動されても届く（既に動いている service には、それが起動した時点の env が使われ、auto-update による自己再起動でも変わらない ―― 2026-10-20 実測）。分類A（機微）も同じく OS 環境変数で供給し、settings には書かない。組織で固定する値だけは managed settings の `env`（管理者の経路）。

**起動環境からしか読まれない変数**もある（公式: [settings-reference「Variables Claude Code ignores in `env`」](https://code.claude.com/docs/en/settings-reference#variables-claude-code-ignores-in-env)）。`CLAUDE_CODE_RESTRICTED`・`CLAUDE_CODE_DISABLE_POWERSHELL_CMD_RM_DENY`・`CLAUDE_CODE_DISABLE_{DANGEROUS_RM_TIMEOUT,SUBSTITUTION_RM_PROMPT,INLINE_SHELL_RM_PROMPT,MOUNTED_DRIVE_RM_PROMPT}`・`CLAUDE_CODE_WARN_{DISK,MEMORY}_FREE_GIB`（v2.1.304〜）などは、managed を含む**どの settings ファイルの `env` でも無視される**。これらは custom.env / setup-environment（foreground のみ）か OS の環境変数（background を含む）でしか効かず、将来 managed settings の `env` へ移す対象にもならない。`CLAUDE_AX_SCREEN_READER` と `CLAUDE_AX_*` は project / local の settings でだけ無視される（v2.1.305〜。user / managed / `--settings` では効く）。

確認時点: 5.1.3 の経路の表と起動環境からしか読まれない変数は、2026-11-03 に v2.1.317 の docs で確かめた（agent-view「Settings and provider」と network-config「Apply network settings to background agents」は v2.1.310 から差分なし。settings-reference「Variables Claude Code ignores in `env`」には、v2.1.311 以降の docs で `CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS` が加わったが、background セッションはこの変数を持たずに始まる〔permission-modes〕ので、上の列挙には載せていない。v2.1.317 の docs で加わった claude.ai のサインインの変数〔`CLAUDE_CODE_OAUTH_TOKEN`・`CLAUDE_CODE_OAUTH_REFRESH_TOKEN`・`CLAUDE_CODE_OAUTH_SCOPES`〕は project / local の settings でだけ無視され〔user / managed では効く〕、起動環境からしか読まれない変数ではないので、これも載せていない。supervisor を最初に起動したシェルの env の継承は 2026-10-20 の実測）。

### 5.2 企業ランチャー（`CLAUDE_CODE_PROCESS_WRAPPER`）との関係

本小節は、background 起動のセッションまで起動装置に通す公式の経路（`CLAUDE_CODE_PROCESS_WRAPPER`）が本キットで使えるかを判定し、本ランチャーの位置づけを決める。

#### 5.2.1 本ランチャーの位置づけ

**本ランチャーは利用者が端末から起動するスクリプトであって、`CLAUDE_CODE_PROCESS_WRAPPER` に登録するランチャーではない**。公式の分類では「自分で端末から起動したセッション」に当たり、起動したとおりに動いて `CLAUDE_CODE_PROCESS_WRAPPER` の対象外になる（corporate-launcher「Processes that start outside the launcher」）。

#### 5.2.2 `CLAUDE_CODE_PROCESS_WRAPPER` を使えない理由

background service と agent view の全セッションを起動装置に通す公式経路は `CLAUDE_CODE_PROCESS_WRAPPER`（v2.1.208〜。同等の `processWrapper` 設定は v2.1.210〜）だが、**本ランチャーの代替にも、本ランチャーをそこへ差し込む用途にも使えない**:

- **Windows では無視される**（`exec` 前提の契約のため。設定してもデバッグログに警告が出るだけで、全プロセスがラップされずに動く）。Windows を主とする本キットでは効かない
- user / managed settings の `env`（または `processWrapper` キー）からしか読まれない。project / local settings の値は無視され、シェルの export も on demand で起動してシェルより長く生きる background service には届かない（読み込み経路の事実。本キットが settings の `env` を勧めるものではない）
- 契約を `start_claude_code.*` は満たさない（下表）
- macOS / Linux で必要になったら、本ランチャーとは**別の**薄いスクリプトとして作る。その際は契約に加えて値の書式に従う: 値はシェルのコマンドではなく引数列として読まれる（変数展開・glob なし。引用していない `;` `|` `&` `$(` は設定エラー）。空白で区切り、二重引用符でまとめる（単一引用符は普通の文字なので `'a b'` は 2 トークン）。`[` で始まる値は JSON 文字列配列で、settings ファイルに書くときは JSON 文字列の中に入れて `"[\"/opt/corp/launcher\", \"--profile\", \"cc\"]"` のようにエスケープする。ランチャー自身の引数は値のパスの後ろに書き、Claude Code のコマンドより先に届くので `exec` の前に `shift` で除く
- 参照: https://code.claude.com/docs/en/corporate-launcher

#### 5.2.3 契約との対照

契約と本ランチャーの関係:

| 契約 | 本ランチャー | 扱い |
|---|---|---|
| `exec "$@"` で終わる | bash 版は `exec`、PS 版は子プロセスとして `& claude` を呼んで終了コードを返す | 不適用（登録用途ではない） |
| Claude Code の引数を並べ替え・取り込み・追加しない（ランチャー自身の引数は先頭に届くので、除いてから残りをそのまま渡す） | OPTS / TEAM_OPTS を足すのが役割。ランチャー自身の引数は持たない | 不適用 |
| 受け継いだ env をすべて `exec` へ渡す（足すのは可） | 足すだけで削らない | 満たす |
| 毎回約 3 秒以内に `exec` する（background セッションは最初の出力までに最大 3 回続けて呼ぶ。ネットワーク待ちには個別の時間制限を付ける） | Claude Code からは呼ばれない | 不適用 |
| 自分の中から呼ばれても耐える | 同上 | 不適用 |
| 起動前に端末にも標準出力にも書かない（標準出力は `claude -p` の結果を読むプログラムにも届く） | 警告・エラーを出しうる。**出力先はすべて stderr**（§5.5.1） | 端末への表示は役割上残す。stdout には書かない |
| 引数の綴り（`--flag value` / `--flag=value`）に依存しない | `--` の補完は「`-` で始まるか」だけで判定する（§5.4） | 満たす |
| 起動したディレクトリから `exec` する | `cd` しない（ルートの解決はサブシェル／`$PSScriptRoot`） | 満たす |
| 標準入力を読まない（読む命令は `/dev/null` から与える） | 読まない（custom.env はファイルとして読む） | 満たす。**`claude` の標準入力を `/dev/null` へ向けることはしない**（対話起動は標準入力が端末でないと Windows では exit 1 で終わり、`… \| start_claude_code -p` の入力も失う） |
| 他のプログラムは絶対パスで呼ぶ（シェルのプロファイルが足す `PATH` が無い状態で起動されうる） | `claude` を `PATH` から探す（利用者のシェルの `PATH` で起動されるため。見つからなければ案内して終了） | 不適用 |

確認時点: 5.2.1 の判定と 5.2.3 の契約は、2026-11-03 に v2.1.317 の docs（corporate-launcher）で確かめた（Windows では引き続き無視される。corporate-launcher はページごと v2.1.316 と同じ。「What the launcher covers」の Windows の記述と「The launcher contract」は v2.1.310 から差分なし）。

### 5.3 サブコマンドの委譲

ランチャーは組み立てたオプションを利用者の追加引数（`"$@"` / `@args`）の前に置く。`remote-control` / `agents` を追加引数で渡すと verb の前に `--settings` 等が付き、remote-control は起動を拒否し、agents は `--add-dir` / `--mcp-config` が前にあると `--json` が失敗する。サブコマンドは `claude` を直接使う（フラグ形式の `claude --bg "<prompt>"` は問題ない）。

確認時点: 2026-11-03 に v2.1.317 の docs で確かめた（agent-view「Settings, plugins, and MCP servers」の `--add-dir` / `--mcp-config` を `agents` の後ろに置く注意と、errors の「`<flag>` before `remote-control` is not carried over to the sessions Remote Control starts」。どちらも v2.1.310 から差分なし）。

### 5.4 位置引数（プロンプト）の取り込みと `--` の補完

本小節は、ランチャーが組み立てたオプションの後ろに利用者の追加引数を付けるとき、プロンプトがフラグの値として取り込まれて消える問題と、その対策（`--` の補完）・限界を定める。

#### 5.4.1 取り込みの仕組み

ランチャーは `claude <OPTS> <TEAM_OPTS> <追加引数>` の順に組み立てる。`claude --help`（2.1.302）で値を複数取る（`<x...>`）フラグと値を省略できる（`[x]`）フラグは、直後の非フラグ引数を値として取り込む。組み立てたオプションの最後がこの型だと、追加引数の先頭にあるプロンプトが消える。

- 値を複数取る: `--add-dir` / `--mcp-config` / `--tools` / `--betas` / `--allowedTools` / `--disallowedTools` / `--file`
- 値を省略できる: `--debug` / `--resume` / `--from-pr` / `--worktree` / `--cloud` / `--prompt-suggestions` / `--remote-control` / `--teleport`

#### 5.4.2 実測

実測（2026-10-19。v2.1.302。`-p`・無効な API キー・空の `CLAUDE_CONFIG_DIR`・一時 cwd・`timeout 60`。結果は下の表のとおり）:

| 引数（`claude -p …`） | 出力 | 判定 |
|---|---|---|
| `"hello world test"`（対照） | `Invalid API key · Fix external API key` | プロンプトとして扱われた（セッション記録に user prompt が残る） |
| `--add-dir <dir> "…"` / `--tools Read "…"` / `--allowedTools Read "…"` / `--debug "…"` / `--from-pr "…"` | `Error: Input must be provided either through stdin or as a prompt argument when using --print` | 取り込まれた（プロンプトが消えた。間接証拠） |
| `--betas X "…"` | `Beta header 'hello world test' is not allowed` ＋上の Error | 取り込まれた（値として検証された） |
| `--mcp-config <json> "…"` | `MCP config file not found: …\work\hello world test` | 取り込まれた |
| `--resume "…"` | `Provided value "hello world test" is not a UUID and does not match any session title.` | 取り込まれた |
| `--disallowedTools Bash "…"` | `Permission deny rule "hello" matches no known tool`（`world` / `test` も）＋上の Error | 取り込まれた（空白で分割された） |
| `--add-dir <dir> -- "…"`（`--tools Read` / `--debug` / `--betas` でも同じ） | `Invalid API key · Fix external API key` | `--` で区切れる。フラグも効く（add-dir が作業ディレクトリに載る・tools が Read だけ・debug ログが出る） |
| `claude -- mcp`（`-p` なし） | `claude mcp` のヘルプ | `--` の後でもサブコマンド名は dispatch される |
| `claude --add-dir <dir> -- mcp`（`-p` なし） | `claude mcp` のヘルプ | 前にオプションがあっても dispatch される |
| `claude -p --add-dir <dir> -- mcp` / `claude -p -- mcp` / `claude -p mcp` | `Invalid API key · Fix external API key` | `-p` があると dispatch されない。`mcp` はプロンプトとして送られた（セッション記録に user prompt `'mcp'`。`--` の有無・前のオプションに関係しない） |

`--add-dir` は存在しないパス（プロンプト文字列）でもエラーを出さないので、対話起動では REPL が開いてプロンプトだけが黙って消えると推定される（未実測）。`--worktree` は worktree を作る副作用があるため実行せず、`[name]` 表記から同型と推定した。

#### 5.4.3 対策

対策は `start_claude_code.{sh,ps1}` の両版に対称に入れてある。

1. 組み立てたオプションが 1 個以上あり、追加引数が 1 個以上で、そのどれも `-` で始まらない（＝プロンプトだけ）ときに限り、間に `--` を挿入する。フラグを含むとき（混在を含む）は挿入しない（素の claude と同じ責任分界）。組み立てたオプションが無いときも挿入しない（既定構成の引数列を素の claude と同一に保つ）。
2. bash 版は連想配列のキーを C ロケールでソートして列挙する。bash の連想配列の列挙はハッシュ順で、書いた順とも一致しないため（実測: 書いた順 `--tools --add-dir --model` → 列挙 `--add-dir --tools --model`）。PS 版は `[ordered]` の記述順のまま。**両版の組立順が一致するのは、記述順がソート順と同じときだけ**。
3. PS 版は `--` を `$cliArgs` の要素として足す。コマンド行に裸の `--` を書くと、`claude` が `.ps1`（npm のシム等）に解決されたときパラメータバインダに消される。配列要素の `'--'` は pwsh 7.4 / 5.1 とも残る（実測）。

#### 5.4.4 限界

- `"<prompt>" -p` のような混在と、`-` で始まるプロンプトには `--` を補わない。フラグはプロンプトより前に置くか、利用者が自分で `--` を書く。PowerShell では裸の `--` はランチャーに届く前に消えるので `'--'` と引用する（裸の `--` ＋プロンプトだけなら、ランチャーが補うので結果は同じ）。
- `--` はサブコマンドの dispatch を止めない。`-p`（`--print`）なしの構成では、プロンプトが 1 語でサブコマンド名（`mcp` / `doctor` / `update` 等）と一致すると、素の claude と同じくサブコマンドとして実行される（サブコマンドは §5.3 のとおり `claude` を直接使う）。前にオプションがあっても同じ（`claude --add-dir <dir> -- mcp` で実測）。
- `-p` を含む構成（OPTS に `--print` を置く等）では、その 1 語はサブコマンドとして dispatch されず、プロンプトとして送られる（`claude -p --add-dir <dir> -- mcp`・`claude -p -- mcp`・`claude -p mcp` で実測。`--` の有無に関係せず、素の claude と同じ）。
- 判定は「`-` で始まるか」だけで、claude 側のフラグ型を見ない。そのためフラグが増えても追随は不要だが、利用者自身が並べた引数（`--add-dir X "prompt"` を追加引数で渡す等）は守らない。

#### 5.4.5 `--bg` との関係

`--bg` / `--background` は裸の `--` より前でだけフラグとして読まれ、`--` の後ろでは文字列になる（v2.1.299〜。[agent view](https://code.claude.com/docs/en/agent-view) の「Prompts that contain `--bg`」）。ランチャーが `--` を補うのは起動時引数に `-` で始まるものが 1 つも無いときだけなので、`start_claude_code --bg "<prompt>"` の `--bg` は従来どおりフラグとして届く。

確認時点: 5.4.1〜5.4.4 の事実は 2026-10-19 に v2.1.302 で実測した（条件は 5.4.2）。5.4.1 の型（`<x...>`・`[x]`）は `claude --help`（2.1.302）の表記で、cli-reference には型の表記が無いため docs では確かめられない（2026-11-03 には、v2.1.317 の cli-reference の CLI flags の表でフラグの追加・削除が無いこと〔80 のまま。変わったのは 5.4.1 の一覧に無い `--input-format` の例と `--max-turns` の説明だけ〕を確かめた）。5.4.5 は 2026-11-03 に v2.1.317 の docs（agent-view「Prompts that contain `--bg`」）で確かめた（差分なし）。

### 5.5 ランチャーの出力と起動前の検出

Claude Code は v2.1.257 以降、`--add-dir` に渡されたネットワークパスを拒否し、そのディレクトリを黙って外して起動する。さらに v2.1.305 以降は、対話起動での自身の起動時警告をデバッグログにしか出さないので、`<Share>` を UNC で指定してキットが読まれなくなっても、利用者の画面には何も出ない（出典は本小節の末尾の参照）。キットの settings・hooks・CLAUDE.md を読ませない起動オプション（区分 1）も、同じく黙ってキットの前提を崩す。`claude` が起動する前に画面へ知らせを出せるのはランチャーだけで、本小節はそのために設けた。本小節で設計するのは、ランチャー自身の出力の約束（stderr）と、起動前の検出（UNC・区分 1）、および検出したときの扱いを決める中断モードである。

本小節は foreground 起動だけに関わる（§3.1.2）。background 起動はランチャーを通らないので、出力の約束も検出も background セッションには及ばない（5.1.1。ランチャーは Claude Code からは呼ばれない ―― §5.2.3 の表）。

まずランチャーが何をどこへ出すかの約束を決め（5.5.1）、次にその約束が要る理由である Claude Code 側の事実を置き（5.5.2）、そのうえで検出の規則に進む（5.5.3 以降）。5.5.1 と 5.5.2 は両版に共通し（出力の約束は両版の約束で、Claude Code 側の事実は版に依らない）、5.5.3〜5.5.8 は PowerShell 版の現行の仕様で、bash 版は凍結中のため一部に追随していない（5.5.9）。

#### 5.5.1 出力の約束（stderr）

- ランチャー（`start_claude_code.*`・`setup-environment.*`）自身の警告・エラーは、両版とも stderr にだけ書く。stdout には `claude` の出力だけを流す。5.5.3〜5.5.5 の検出の行・まとめ行・不正値の行も、この約束に従って stderr に出す。
- 理由: `start_claude_code -p "…" > out.txt` のように `claude -p` の結果を読むスクリプトへ、警告が混ざらないようにするため（§5.2.3 の契約の表「標準出力に書かない」と同じ理由）。
- bash 版はすべて `>&2` で書く。
- PS 版のランチャーは、自身の警告・エラーを `[Console]::Error` へ直接書く。`setup-environment.ps1` を dot-source するときは、パイプラインで warning（3）と information（6）のストリームを受けて `[Console]::Error` へ書き直す（warning には前置き `警告: ` を付ける）。
  - 理由: PowerShell は別のプログラムから起動されると、warning / information のストリームを stdout に書く（pwsh 7.x と Windows PowerShell 5.1 の両方で 2026-10-24 に実測。pwsh 7 では色付けのエスケープ列ごと出る）。
  - `setup-environment.ps1` を単体で動かしたときは `Write-Warning` のままにしている。verify-kit が warning ストリームで受けて bash 版と比べているため。

#### 5.5.2 Claude Code の起動時警告とデバッグログ

この小節は Claude Code 側の事実で、ランチャーの版に依らない。

- **ネットワークパスの `--add-dir` を黙って外す（v2.1.257〜）**: `--add-dir` に UNC（`\\server\share`）などのネットワークパスを渡すと、Claude Code はそれを拒否し、そのディレクトリを外して起動する（参照: errors の「working directory is a network path」の節）。
- **対話起動の起動時警告はデバッグログにだけ出る（v2.1.305〜）**: 対話起動での Claude Code 自身の起動時警告は、上の `--add-dir` を外した警告も含めてデバッグログにしか出ない（それより前は stderr に出ていた）。例外として、権限ルールの一部の警告だけはバナーの下の行に出る。`-p`（text 出力で background でないとき）では stderr に出る（参照: errors の「configuration warnings」の節）。
  - デバッグログはデバッグモードのときだけ残る。読むには起動時引数に `--debug-file <path>` を足す。option-settings テンプレにも `--debug-file` のキーがある。
- 帰結: 対話起動で `<Share>` を UNC で指定すると、**キット（CLAUDE.md・rules・skills）が読まれないまま、画面に何も出さずに起動する**。Claude Code 側の知らせは、デバッグログの中にしか無い。
- 回避: Windows ではドライブ文字に割り当ててから渡す（`net use Z: \\server\share` の後に `--add-dir Z:\`）。option-settings テンプレの `--add-dir` の注記にも同じ趣旨が書いてある。
- そこでランチャーは、`claude` を起こす前に option-settings とチーム統制を確かめ、キットの前提が崩れる設定を画面に出す（5.5.3）。この知らせは起動前に出るので、デバッグログを開かなくても気づける。`--debug-file` を付けていない利用者には、これが唯一の知らせになる。

#### 5.5.3 起動前の検出の規則

option-settings（`OPTS` / `$Opts`。3) で読み込む）とチーム統制（`TEAM_OPTS` / `$TeamOpts`。2) で定義する）に、キットの前提が黙って崩れる起動オプションがあれば、`claude` を起こす前に知らせる。検出は次の 2 種類で、見つけたあとの扱い（中止するか警告するか）は 5.5.4 で決まる。

- **UNC**: ネットワークパスの形をした `--add-dir`
- **区分 1**: キットの前提が黙って崩れる起動オプション。launcher README 付録 A に「載せない理由」を示したオプションのうち、settings・hooks・CLAUDE.md / rules の一部が読まれないまま起動してしまう 5 キーと、値に `project` を含まない `--setting-sources`（テンプレに載っているキーで、値によって区分 1 になる）を指す。区分 2 以降は定義していない

| 検出名 | 見る出どころ | キー | 判定 | 見ないもの | 理由文の出典 |
|---|---|---|---|---|---|
| UNC | option-settings → チーム統制 | `--add-dir` | 値を文字列にして、`\\` か `//` で始まる（序数比較） | 起動時引数・「=」形のキー・シンボリックリンクやジャンクションの解決・`/net/<host>` | README 付録 B「--add-dir とネットワークパス」。文はコードに固定 |
| 区分 1 | option-settings → チーム統制 | `--restricted` | キーがある | 起動時引数・「=」形のキー・値 | README 付録 A の表 |
| 区分 1 | 同上 | `--bare` | 同上 | 同上 | 同上 |
| 区分 1 | 同上 | `--safe-mode` | 同上（文は `--bare` と同じ） | 同上 | 同上 |
| 区分 1 | 同上 | `--system-prompt` | 同上 | 同上 | 同上 |
| 区分 1 | 同上 | `--system-prompt-file` | 同上（文は `--system-prompt` と同じ） | 同上 | 同上 |
| 区分 1 | 同上 | `--setting-sources` | キーがあり、値を文字列にしてカンマで分け、前後の空白を除いた要素に `project`（大文字小文字を区別する完全一致）が無い | 起動時引数・「=」形のキー・未設定（既定で全ソースを読むので対象外） | README 付録 B「--setting-sources の影響範囲」 |

共通の規則:

- **出どころごとに独立に判定する**。option-settings とチーム統制を合成した実効値（`--setting-sources` はチーム値が後勝ち）は見ない。両方に書けば両方を検出する。
  - 理由: UNC と区分 1 で同じ責任分界にし、書いた場所ごとに直せるようにするため。
- **キーの照合は大文字小文字を区別しない**。`[ordered]` の `Contains` を使うので、`'--Bare'` も検出する。
  - 理由: `claude` 自身が綴りの違うキーをエラーにするので、既定の `abort` でランチャーが先に止まったほうが早く気づける。
- 判定はキーの綴りと表の値の条件だけで行い、値の正しさは `claude` に任せる。値は文字列にしてから見る（PS 版で `$true` と書くと `True` になり、`project` が無いので検出する）。
- option-settings とチーム統制には、キーごとに値を 1 つしか書けない（同じキーを 2 回書けない。README §3-2）。`--add-dir` の 2 個目以降は起動時引数で渡すので、検出の対象にならない。
- **起動時引数と「=」形のキー（`'--add-dir=<パス>'`・`'--bare=…'` 等。テンプレで案内していない書き方）は見ない**。
  - 理由: 利用者が自分で並べた引数は守らない（§5.4 の責任分界）。
- UNC の判定は綴りだけで行う。
  - 理由: パスを解決するとランチャー自身がネットワークへ触れてしまう。Claude Code もそれを避けるため、パスを解決せずに拒否している。
- UNC をチーム統制でも見る。
  - 理由: チームが `<Share>` を固定するのはチーム統制であり、そこに UNC を書くと全員がキット無しで黙って起動するため。
- 対象外にしたもの:
  - `--allowedTools` / `--disallowedTools`: 権限の付け外しであり、deny が allow に勝つのでキットの deny は崩れない。方針の話として settings 側で管理する。
  - `--desktop` / `--environment` / `--ref` とサブコマンド専用のオプション: 他の起動オプションとの併用や、サブコマンドの外での使用を、`claude` 自身が目に見える形で拒否する。
- ランチャーは統制の境界ではない。チームとして禁じたいなら managed settings で固定する（ランチャーの統制には強制力が無い。launcher README §3-1・付録 A）。

文の形（1 件につき 1 行。前置きは 5.5.4 で決まる）:

| 検出 | 文の形 |
|---|---|
| UNC | `<出どころ> の --add-dir <値> はネットワークパスの形です。ネットワークパスは v2.1.257 以降拒否され、Claude Code はこのディレクトリを黙って外して起動するため、ドライブ文字に割り当てて指定してください。` |
| 区分 1（5 キー） | `<出どころ> の <キー> は、<理由>。`（理由はキーごとの表で、`start_claude_code.ps1` の `$kitBreakingOpts` にある。README 付録 A の載せない理由に揃えてある） |
| 区分 1（`--setting-sources`） | `<出どころ> の --setting-sources <値> に project が含まれません。キットの .claude/settings.json（permissions.deny・hooks）と、--add-dir で足したディレクトリの skill 等が読まれません。` |

- `<出どころ>` は `option-settings` か `start_claude_code のチーム統制（TEAM_OPTS / $TeamOpts）` のどちらか。表記は bash 版と同じ。
- 文はモードに依存しない。中止するか起動するかは、まとめ行で伝える（5.5.4）。

#### 5.5.4 中断モード（`$TeamKitCheck`）

- `$TeamKitCheck` は、`start_claude_code.ps1` の 2) で `$TeamOpts` の直後に置くチーム定数で、既定値は `'abort'`。5.5.3 の検出（UNC と区分 1 の両方）の扱いを全体で一括して切り替える。キーごとに切り替える設定は無い（見送った）。
- 検出したものは配列に溜める（順は 5.5.5）。1 件以上あれば各行に前置きを付けて出し、最後にまとめ 1 行を出す。0 件ならまとめ行も出さない。

| 値 | 各行の前置き | まとめ行 | `claude` | 終了コード |
|---|---|---|---|---|
| `'abort'`（既定） | `エラー: ` | `エラー: キットの前提が崩れる起動オプションが N 件あるため起動を中止します。該当のキーを外すか、start_claude_code の TEAM_KIT_CHECK / $TeamKitCheck を 'warn' にすると警告だけで起動します。` | 起こさない | 1（0) の実行要件のエラーと同じ） |
| `'warn'` | `警告: ` | `警告: キットの前提が崩れる起動オプションが N 件あります。TEAM_KIT_CHECK / $TeamKitCheck が 'warn' のため、そのまま渡して起動します。` | キーを捨てずにそのまま渡して起動する | 通常の起動と同じ（`claude` の終了コード） |

- **不正な値**: `'abort'` / `'warn'` 以外の値は fail-closed で `'abort'` として扱う。比較は序数で行い、空の値・大文字小文字の違い・定数の行を消した場合も不正とみなす。検出の有無にかかわらず、次の 1 行を出す。
  - `エラー: start_claude_code のチーム定数 TEAM_KIT_CHECK / $TeamKitCheck の値「<値>」は 'abort' / 'warn' のどちらでもないため、'abort' として扱います。`
  - チーム定数の誤りは毎回知らせる。検出が無ければ中止する理由も無いので、そのまま起動する。
- まとめ行に含まれる `TEAM_KIT_CHECK / $TeamKitCheck` は、bash 版と共通にする ASCII の断片（verify-kit が照合する。5.5.8）。
- 置き場はランチャー本体のチーム定数で、`$TeamOpts` と同じく利用者は触らない。設計 v2 でチーム統制の置き場が外部ファイルに移るなら、一緒に移す。
- 強制力は無い。起動時引数で渡した `--bare` 等は止まらない（§5.4 の責任分界）。誤設定に対する防護柵であって強制ではなく、確実な強制は managed settings の仕事（5.5.3）。
- 既定を `abort` にした理由:
  - 警告はランチャーが stderr に書いた直後に `claude` の画面が始まるので、目を離すと見逃す。
  - `warn` のまま見逃しを防ぐには起動前の入力待ちが要るが、それは `-p`・スクリプトからの起動・background セッションを壊す。中断なら入力待ちなしで、メッセージがプロンプトと一緒に画面に残る。
  - 多くの利用者は、前提が崩れた状態で起動しても終了して設定を直すので、最初から止めたほうが時間を食わない。
  - ただし全員がそう考えるとは限らず、確実な強制は managed settings の仕事なので、切り替えられるようにした。
- 前置きの使い分け:
  - `abort` で出す行はログレベル ERROR に当たるので `エラー: `（作業指示者の補足の指示）。
  - `warn` で出す行は `警告: `。
  - setup-environment の警告と、誤配置の option-settings の警告は、モードに関係なく `警告: `。

#### 5.5.5 stderr の出力順

1. setup-environment の警告（1)）
2. 誤配置の option-settings の警告（3)）
3. `$TeamKitCheck` が不正な値のときの 1 行（不正なときだけ）
4. UNC の検出（option-settings → チーム統制）
5. 区分 1 の検出（option-settings → チーム統制の出どころ順。各出どころの中は 5.5.3 の表の 5 キーの順で、最後に `--setting-sources`）
6. まとめ行（検出が 1 件以上のときだけ）

- 区分 1 の表の行の順が、そのまま出力の順になる。§6.1.2 で表を共有データにするときも、この性質を保つ。

#### 5.5.6 処理の順序と中止したときの状態

- ランチャーは節の番号順に処理する。
  - 0) 実行要件の確認 → 1) 環境変数の設定（setup-environment）→ 2) チーム統制（`$TeamOpts` と `$TeamKitCheck` の定義）→ 3) option-settings の読み込みと検出 → 4) 引数の組み立て → 5) 起動
  - 中止（5.5.4）は 3) の最後で行い、`claude` を起こす前に終わる。
- **読み込みの順序は変えない**。option-settings の読み込みと検出を setup-environment より前に出せば、環境変数を設定する前に止められるが、その案は採らなかった。理由は次の 3 つ。
  - 中止は `claude` を起こす前なので、設定済みの環境変数が残っても `claude` の動作には関わらない。
  - option-settings は dot-source して実行するスクリプトで、setup-environment が設定した環境変数を参照しうる。前に出すと結果が変わりうる。
  - setup-environment の警告が先に出る出力の順（5.5.5）と、節の構成を保てる。
- 中止したときの状態:
  - 対話セッションで `.\start_claude_code.ps1` と実行して中止すると、setup-environment が設定した環境変数（`$env:`。プロセス単位）はそのセッションに残る。これは `claude` が終了した後と同じ状態であり、中止によって新たに生じる状態ではない。
  - `-File` で起動したときと bash 版は子プロセスで動くので、環境変数は残らない。
- 共有データ（区分 1 の表など。§6）を足しても、この順序は変えない（§6.4）。
  - 必須のデータのパースは副作用の前（0) の続き）に置く。検出は従来どおり 3) の option-settings の読み込みの後に置く。
  - データが読めないときの扱いは §6.3 で決めている（区分 1 の表はモードに依らず必須）。

#### 5.5.7 既知の帰結と限界

- UNC の判定は綴りだけなので、ネットワークパスではない次のパスも検出し、既定の `abort` では起動が止まる。
  - `\\wsl$\…`（Claude Code はネットワークパスとみなさない。本小節の末尾の参照の errors の network path の節）
  - ローカルの長いパスやデバイスのパス（`\\?\C:\…`・`\\.\…`）
  - 該当する利用者は、パスの書き方を変える（`\\?\C:\…` なら `C:\…` と書く等）か、`$TeamKitCheck` を `'warn'` にする（launcher README 付録 B に記載）。
  - `\\?\` / `\\.\` に対しては、文の「黙って外して起動する」は当たらないと考えられる。ただし docs に扱いの記載は無く、未実測（2026-10-27 のレビューで確認した点）。
- シンボリックリンク・ジャンクション経由のネットワークパスや `/net/<host>` は検出しない（5.5.3 の「見ないもの」）。
- 出どころごとに独立に判定する（5.5.3）ため、option-settings に `--setting-sources user`、チーム統制に `project,user` と書くと、既定の `abort` では option-settings 側の検出で起動が止まる。実効値は `project` を含むが、止まる。
  - メッセージが出どころとキーを示すので、1 回の修正（option-settings から外す）で済む。チーム値に上書きされて効いていない設定の掃除にもなる。
- 起動時引数で渡したオプションは検査しないので、中断モードでも止まらない（5.5.4）。

#### 5.5.8 verify-kit の検証

- 項目は「ランチャー stdout / stderr の振り分け（スタブ）」（項目キー `launcher-streams`）、fixture は `scripts/verify-kit.d/launcher-streams.txt`。
  - 一時ツリーに複製したランチャーと `claude` スタブで実行し、実物のランチャーは書き換えない。
  - PowerShell 系統はランチャーを `-File` で起動する。
- probe が置く警告・検出のもと:

| fixture のタグ | 置き場 | 現行の中身 |
|---|---|---|
| `env` | `.claude/custom.env` | 分類A のキー `ANTHROPIC_API_KEY` を含む |
| （probe が固定で置く） | 誤配置の `.claude/launcher/custom.env` と `.claude/launcher/option-settings.ps1`（bash 系統は `.sh`） | 前段の警告のもと |
| `opt` | `.claude/option-settings` | UNC の `--add-dir`（`\\vk-unc-host\share`）・`--restricted`・`--setting-sources user,local` |
| `team` | 複製したランチャーの `TEAM_OPTS` / `$TeamOpts` の定義の行の直後 | UNC の `--add-dir`（別のホスト名 `\\vk-unc-team\share`）・`--bare`・検出しない対照の `--setting-sources project,user` |
| `in` | 起動時引数 | `verify-kit prompt` |

- 同じ一時ツリーで 2 回実行する。項目キーは 1 つのままで、結果は節 `launcher-streams abort` / `launcher-streams warn` に分けて書く。

| 回 | 準備 | 照合するタグ | 終了コード | `claude` スタブ | stdout | stderr |
|---|---|---|---|---|---|---|
| 1 | 複製のまま（`abort`） | `stderr-abort` | 0 以外 | 起動しない | 空 | 9 行 |
| 2 | probe が複製の `$TeamKitCheck = 'abort'` の行（bash 系統では `TEAM_KIT_CHECK=abort`）を `warn` に書き換える | `stderr-warn` | 0 | 起動する | 空 | 9 行 |

- stderr 9 行の内訳:
  - 前段の警告 3 行: 誤配置の custom.env、custom.env 中の分類A のキー、誤配置の option-settings
  - 検出 5 行: UNC 2 行（option-settings → チーム統制）・`--restricted`・`--setting-sources user,local`・`--bare`
  - まとめ 1 行
  - 対照の `--setting-sources project,user` が出ないことは、行数で確かめる。
- 次のどちらかがちょうど 1 行でなければ FAIL にする: 差し込み先の定義の行（`declare -A TEAM_OPTS=(` / `$TeamOpts = [ordered]@{`）、書き換える定数の行。
- 照合に使う断片は ASCII だけで書く。PowerShell 系統の stderr はコンソールのコードページで書かれ、日本語が化けるため。
  - そのため、前置き（`⚠ ` / `警告: ` / `エラー: `）と出どころの表記（日本語）は照合しない。モードの違いは、終了コードとスタブが起動したかどうかで見る。
  - まとめ行は断片 `TEAM_KIT_CHECK / $TeamKitCheck` で照合する。
  - stderr は `\` を `/` に揃えてから比べる。
- 出どころの表記が 3 系統で一致することは、スタブを使った 2026-10-27 の手元の実測で確かめた（verify-kit の照合の外）。
- bash 系統は `scripts/verify-kit.d/frozen.txt` の行（項目 `launcher-streams`・系統 `bash`）で凍結している。判定は pwsh 7 と 5.1 の 2 系統で行い、結果は FROZEN として集計する。
  - bash 版の probe は `TEAM_KIT_CHECK=abort` の行を書き換える形なので、その行が無い今は 2 回目が FAIL になる。凍結解除で移植されるまでは、FAIL になるのが正しい。

#### 5.5.9 bash 版との差（凍結中）

bash 版の 3 本は 2026-10-30 から凍結している。範囲・終了条件・移植の手順は `docs/launcher/sh-freeze-backlog.md` にある。

| 項目 | PS 版（現行） | bash 版（凍結中） | バックログ |
|---|---|---|---|
| 区分 1 の検出 | あり（5.5.3） | なし | SH-DEFER-01 |
| 中断モード | `$TeamKitCheck`（既定 `abort`。5.5.4） | なし（`TEAM_KIT_CHECK` の行も無い）。UNC は警告するだけで、起動は止めない | SH-DEFER-02 |
| UNC の文 | モードに依存しない文（5.5.3） | B-5 より前の文のまま（`<出どころ> の --add-dir <値> はネットワークパスの形です。ネットワークパスは v2.1.257 以降拒否され、v2.1.305 以降は警告がデバッグログにしか出ないため、Claude Code はこのディレクトリを黙って外して起動します。ドライブ文字に割り当てて指定してください。`） | SH-DEFER-02 |
| 前置き | `警告: ` / `エラー: `（5.5.4） | `⚠ `（移植後は、`warn` を `⚠ `、`abort` を既存のエラーと同じ `エラー: ` にする予定） | SH-DEFER-02 |
| キーの照合 | 大文字小文字を区別しない（5.5.3） | 区分 1 は未実装（移植のときに PS 版の扱いに揃える） | SH-DEFER-01 |
| UNC の検出の範囲と出どころの表記 | option-settings とチーム統制 | 同じ（K-01 で両版に入れた） | — |
| verify-kit の `launcher-streams` | pwsh 7・5.1 で判定 | 凍結（FROZEN） | SH-DEFER-01・02 |

- 凍結とは関係なく、設計として次の差もある。
  - 中止した後に環境変数が残るのは、PS 版を対話セッションで実行した場合だけ（5.5.6）。
  - setup-environment の警告は、PS 版では単体で動かしたとき `Write-Warning`、bash 版では `>&2` で出る（5.5.1）。

確認時点: 5.5.2 の事実は 2026-11-03 に v2.1.317 の docs（errors の「Configuration warnings」「Working directory is a network path」）で確かめた（差分なし。「Configuration warnings」で変わったのは小節「Unrecognized model ID on a request」の 2 文だけで、起動時警告がデバッグログに出る旨の記述と「Working directory is a network path」は v2.1.316 と同じ）。5.5.3 以降の仕様は 2026-11-01（issue #4 の B-5）時点の実装を記したもの。

- 参照: https://code.claude.com/docs/en/errors#configuration-warnings 、https://code.claude.com/docs/en/errors#working-directory-is-a-network-path

## 6. 両版が読む共有データ（フェーズ 3 設計。2026-11-02 裁定済み）

> 2026-11-02 の設計（スクリプト追加改善活動のフェーズ 3。設計だけで、実装はまだ無い）。**本節の内容は 2026-11-02 の作業指示者の裁定（GitHub issue #4 の C-6〜C-10。すべて Claude の推奨案を採用）で決定した**。実装は 6.6 のステップ順に行う。候補ごとの事実（行番号・件数）と移行の各ステップの詳細（verify-kit の項目・fixture）は 2026-11-02 の設計の報告書（非追跡）にあり、裁定に要る要点は issue #4 に転記する。

### 6.1 目的と対象

#### 6.1.1 目的

- bash 版と PowerShell 版が同じ表をそれぞれ埋め込んでいる二重管理を減らす。表をデータファイルに出して両版が読む。
- 実装は PowerShell 版から行い、凍結中の `.sh` 3 本は埋め込みのまま（凍結解除のときに追従）。凍結中の突き合わせは、verify-kit が「データファイル ↔ `.sh` の埋め込み ↔ docs」で行う（issue #4 の C-4 (a)）。

#### 6.1.2 対象

- 対象は次の 4 件（issue #4 の C-2 で確定）。表に落ちない判定（両版で構文が違う照合式・条件付きの判定・UNC の検査）はコードに残す。

| データ | 今ある場所 | データにする部分 | コードに残す部分 | ファイル |
|---|---|---|---|---|
| 機微情報（分類A）の判定 | setup-environment 両版 | 既知キー 18 個 | 名前の形（bash は `case` の glob、PS は正規表現で、構文が違う）・URL の形の正規表現 2 本（bash 版はリテラルのタブを含み、タブ区切りの列に置けない） | `.claude/launcher/sensitive-keys.txt` |
| 内部変数名の一覧 | setup-environment.sh の `case`・ps1 の配列・`launcher-implementation-plan.md` L52 | 20 個（PS 版が読む） | bash 版の `case`（凍結解除後も残す。C-10 (b)） | `.claude/launcher/internal-keys.txt` |
| 区分 1 の表 | `start_claude_code.ps1` だけ（bash 版は SH-DEFER-01） | キー 5 個と理由文（行の順が出力の順） | `--setting-sources` の `project` 欠落の判定・UNC の検査・文の枠・`$TeamKitCheck` | `.claude/launcher/kit-breaking-opts.txt` |
| check-assets の U / M / E（＋ W） | check-assets 両版 | U 18 個・M 26 個・E の選択肢 38 個（1 行 1 個。各版が `\|` で結んで `^(…)$` で包む）・W のツール名 4 個 | `defaultMode` の条件・W の `\([\s\S]+\)` の部分・全体一致の包み方 | `scripts/check-assets.d/settings-scope.txt` |

### 6.2 書式と置き場（C-7 (1)〜(3)。2026-11-02 決定）

6.1.2 の 4 件を出すデータファイル（`.claude/launcher/` の 3 本と `scripts/check-assets.d/` の 1 本）に共通の書式と、それぞれの置き場を定める。読み手は `start_claude_code.ps1`・`setup-environment.ps1`・check-assets 両版（凍結解除後は `start_claude_code.sh`・`setup-environment.sh` も）。

#### 6.2.1 書式

- UTF-8（BOM なし）・LF・1 行 1 件・列の区切りは TAB。1 文字目が `#` の行と空行は無視する（行頭の空白は剥がさない）。列の意味は行頭のタグで決める（`scripts/verify-kit.d/launcher-streams.txt` と同じ型）。最初のデータ行は `format<TAB>1`（スキーマ版。6.5）。未知のタグ・列の過不足・空の値・重複・`format` 行の欠落と版の違いは、どれも書式の誤りとして扱う。値の形の検査（キーパス・ツール名・正規表現の選択肢に使える文字と括弧の釣り合いなど）はデータの種類ごとに読み手に足す（両版で同じ判定・同じ文言にする）。
- 読み手の規則は両版で同じにする。bash は `while IFS= read -r` で 1 行ずつ読み、行末の CR と 1 行目の BOM を剥がし（`.claude/.gitattributes` は LF を既定にするが、コピー展開や手で保存したファイルに備える）、列は `${line%%$'\t'*}` のようなパラメータ展開で切る（`IFS=$'\t'` の `read` は連続する TAB を 1 個に潰す）。PowerShell はファイルをバイト列で読んで UTF-8 として復号し（先頭の BOM は剥がす。`Get-Content` は単独の CR でも行を分け、`ReadAllText` は UTF-16 の BOM を見て別の符号化で読むため、どちらも bash 版と結果が割れうる。5.1 の既定が ANSI である点も避けられる）、LF で行に分けて ``Split("`t")`` で切り、タグや値の比較は序数で行う（ステップ ① の実装で決めた読み方。2026-11-02）。

#### 6.2.2 置き場

- ランチャーが実行時に読むもの（機微情報の既知キー・内部変数名・区分 1 の表）は `.claude/launcher/`（payload）。
- check-assets の表は、検査対象のツリー（publish-share は `.claude/` だけを取り出して渡す）ではなくスクリプトの位置から引くので `scripts/check-assets.d/` とし、両版に自身の位置の解決を足す（今の check-assets は自身の位置を使っていない）。
- 拡張子は `.txt`。verify-kit の `format` 項目は今の区分ではこれらの保存形式を検査しないので、`fmt_class` / `Fmt-Class` に区分を足す。

### 6.3 致命度（方式は issue #4 の C-3 (a)。割り当ては C-6 (b)。2026-11-02 決定）

#### 6.3.1 致命度とは

- 本書で「致命度」は、データファイルごとに決める属性で、そのファイルが無い・読めない・書式が壊れているときにランチャーがどう振る舞うかを定める（issue #4 の C-3 (a) の方式）。
- 値は 3 つ。**必須** = stderr にエラー 1 行を出し、副作用（環境変数の設定・`claude` の起動）の前に起動を中止する（終了コード 0 以外）。**任意** = stderr に警告 1 行を出し、そのデータに依る検査だけを省いて起動する。**対象外** = ランチャーは読まない（開発ツールだけが読むデータ。読めないときの扱いはそのツールが決める）。
- 「無い」と「書式が壊れている」は同じ致命度で扱う（書式の誤りは verify-kit が開発時に検出する前提）。
- 致命度の表はランチャー本体に埋め込む。読めないファイルの中に致命度は書けず、別のファイルに持つとそのファイルが読めないときの扱いが再び問題になるため。
- 必須のデータの読み込み（パース）は副作用の前に済ませる（検出の位置との関係は 6.4）。

#### 6.3.2 データごとの割り当て

| データ | 致命度 | 読めないときの挙動 | 理由 |
|---|---|---|---|
| 機微情報の既知キー | 必須 | エラー 1 行 ＋ 起動中止 | 欠けると、名前の形で拾えない 3 個（`ANTHROPIC_CUSTOM_HEADERS`・`AWS_BEARER_TOKEN_BEDROCK`・`AWS_ACCESS_KEY_ID`）が環境変数として渡る |
| 内部変数名 | 必須 | エラー 1 行 ＋ 起動中止 | bash 版では custom.env が内部変数を書き換えないためのガードそのもの。PS 版ではキットの部品の欠落として扱う |
| 区分 1 の表 | 必須（`$TeamKitCheck` のモードに依らない。C-6 (b)） | エラー 1 行 ＋ 起動中止（`warn` でも止める） | 暫定案「B-5 のモードに従う」は採らなかった。モードを決める `$TeamKitCheck` は 2) で定義され、1) の環境変数の設定より後にある。モードに従わせたうえで副作用の前に止めるには定数を 1) より前へ動かすことになる。パースだけを前に置き、中止か警告かの判断を 2) の後に回せば定数は動かさずに済む（`abort` の中止が環境変数の設定の後になるが、§5.5 が B-5 で許容している状態と同じで、C-3 (a) の「読み込みは副作用の前」は満たす）。常に必須にした理由は、データの欠落はキットの部品の欠落で、0) が setup-environment の欠落で止めるのと同じ扱いにできること |
| check-assets の U / M / E | 対象外（ランチャーは読まない） | check-assets が FAIL | 検査器自身の表が欠けた状態を PASS にしない（2-g の「未検査」の WARN は検査対象の一時的な読み取りの失敗で、ほかの検査は続く） |

- 出力は stderr に 1 行。必須のデータは `エラー: <ファイルのパス> を読めないため起動を中止します（<無い / 書式: N 行目 …>）。` の形で、`claude` を起こさずに終了コード 0 以外で終わる。任意のデータは無い（どのデータも必須か対象外のどちらか）。
- verify-kit は、一時ツリーのデータファイルを消す・壊す・版を変える probe で、終了コード・`claude` スタブが起動しないこと・stderr の行数とファイル名の断片を見る（bash 系統は凍結中なので `frozen.txt` に行を足す）。

### 6.4 §5.5 の「読み込みの順序は変えない」との関係（2026-11-02 決定）

- §5.5 の判断（setup-environment → option-settings → 検出 → 中止の順を変えない）は、共有データを足しても変えない。そのために「データを読む（パースと書式の検査）」と「検出（option-settings / `$TeamOpts` との照合）」を分け、必須のデータのパースは副作用の前に置き（ランチャーの表は 0) 実行要件の確認の続き、setup-environment の表は custom.env の行ループの前）、検出は従来どおり option-settings の読み込みの後に置く。
- §5.5 が順序を変えなかった理由（option-settings は dot-source して実行するスクリプトで、setup-environment が設定した環境変数を参照しうる）は、静的なデータファイルのパースには当たらない（データは実行されず、環境変数も参照しない）。順序を見直した結果、変えない。
- §5.5 の順序のまま凍結解除で bash 版へ移すときは、`start_claude_code.sh` が setup-environment を source する前に代入して後で読む変数（パースした表など）を内部変数名の一覧に入れる（今の `_ROOT_DIR` と同じ扱い。custom.env の行が export でその変数を書き換えないように）。

### 6.5 配布レールのずれ（C-9 (a)。2026-11-02 決定）

- 結論: 全データファイルに `format` 行（スキーマ版）を持たせ、読み手に埋め込んだ期待値と違えば書式の誤りと同じ扱い（必須なら起動中止）にする。あわせて、publish のゲート（check-assets）の 2-d（配布先の統制ファイル）と同じ二層基準で、payload に必須のデータファイル 3 本があることを確かめる。
- 背景: `start_claude_code` はルート直コミットのレール、`.claude/launcher/` は payload のレールなので、「本体が新しくデータが古い」とその逆が起きうる。
  - この組み合わせに当たるのは区分 1 の表（本体が読む）。setup-environment とその表（機微情報の既知キー・内部変数名）はどちらも payload で、レールをまたがない。
- 版を上げる基準: 行を足す・消す・文を直すだけの変更では上げず、タグや列の意味を変えるときだけ上げる。
- 存在検査を check-assets に置く理由: publish-share の前段で走るのは check-assets だけで、verify-kit は走らない。

### 6.6 移行の順序と verify-kit（C-8 (1)(a)・(2)(b)・C-10 (b)。2026-11-02 決定）

- **論点 1: どのデータから、どの順で移すか**（C-8 (1)）
  - 課題: 4 件は読み手も凍結の影響も違い、順によって検証のしやすさと二重管理の減り方が変わる。
  - 結論: ① check-assets の U / M / E → ② 区分 1 の表 → ③ 機微情報の既知キー → ④ 内部変数名。
  - 理由: ① は凍結の対象外なので両版がすぐ読め、部数が 2 から 1 に減る。利用者の起動経路に乗らず、`ca-fixture` の期待値が変わらないことで移行の正しさを見られる。② は PS 版にしか無く、今データにすれば bash 版へ移植するときに 2 部目を作らずに済む。③ は分類A のガードなので慎重に後へ置き、データ ↔ `.sh` の集合を突き合わせる項目を足す（今は表そのものを抽出する検査が無い）。④ は凍結中は部数が減らないので最後。
- **論点 2: verify-kit の一時ツリー**
  - 課題: 今の一時ツリー（ランチャーと setup-environment の probe）は 2 本のスクリプトしか複製しないので、ランチャーがデータファイルを必須にすると probe が「データが無い」で止まる。
  - 結論: どのステップでも、一時ツリーにデータファイルを複製する変更を両版に入れる。
  - 理由: 複製しなければ既存の項目がすべて FAIL になり、移行の正しさを見られない。
- **論点 3: `internal-keys` の比較と docs の列挙**（C-8 (2)）
  - 課題: 今は「`.sh` の `case`・`.ps1` の配列・`launcher-implementation-plan.md` L52 の列挙」の 3 者を比べ、docs は文の形を構文解析している。
  - 結論: 比較を「データファイル・`.sh`・docs」に置き換え、`.sh` が代入する変数がすべて一覧にあることの検査を足す。docs の列挙はステップ ④ で名前の列挙をデータファイルへの参照に置き換え（読み飛ばす理由の説明は残す）、verify-kit は docs を比較から外す（C-8 (2)(b)）。
  - 理由: 直す場所が 1 つ減り、文の構文解析が要らなくなる。データファイルは追跡ファイルなので、追跡文書から非追跡の成果物を参照しない約束には当たらない。
- **論点 4: 凍結解除後の bash 版の内部変数名**（C-10）
  - 課題: 一覧を実行時にファイルから読むと、「判定は変数を介さない `case` にする」という今の性質（判定に使う変数自体が書き換えの対象になりうる）が失われる。
  - 結論: データファイルは PS 版が読み、bash 版は恒久的に `case` の直書きを残す（C-10 (b)）。
  - 理由: 一覧は bash のコードの性質（使う変数）そのもので、コードの隣にあるのが自然。利用者の手元のファイルから 1 行消えてもガードが崩れない。

### 6.7 設計 v2 との突き合わせ点（起草者への問いと回答）

- 作業指示者の設計 v2 ドラフトはまだ無い。2026-11-02 の作業指示者の回答で分かった構想は次のとおり（確定ではない。推測は推測と記す）。
  - 外出しするのは起動オプションではなく**環境変数**。環境変数を「どんな環境でも使えるもの」と「何らかの前提でなければ使えないもの」に分け、後者を前提の分類軸ごとに別ファイルにする。軸の候補はプロバイダ固有（Anthropic 固有もサードパーティ固有も同列に扱う）とプラットフォーム固有で、公式 docs の env-vars の全環境変数の有効条件を整理してから採用する軸を決める。スクリプト固有の環境変数はそのスクリプト内に直接定義する。利用者に設定を委ねられるものは `*.template`、ガバナンス・セキュリティの面でみだりに変えさせないものは setup-environment と同じ場所の別ファイル。起動時オプションにも同じ観点が当てはまる可能性がある（作業指示者の注記）。
- 問いと回答（2026-11-02）:
  1. 区分 1 の表の置き場 ―― 回答: 採用する軸次第。利用者に委ねないものは setup-environment と同じ場所の別ファイル。→ 現行の `.claude/launcher/kit-breaking-opts.txt`（6.2.2）と整合する。
  2. `$TeamKitCheck` と `$TeamOpts` を外出しファイルへ移すか（issue #4 の C-1 の補足）―― 回答（推測）: どちらも今の位置のままで問題ない。→ 6.3.2 の区分 1 の扱い（常に必須）は据え置き。
  3. v2 で外出しするファイル自体の致命度（v2 で新しく外出しする環境変数のファイルが無い・読めないとき、6.3 の共有データと同じく必須として起動を止めるか、既定値で起動するか）―― 回答: 基本は必須にしない（エラー処理を複雑にしない）。ただし、ファイル内の設定にキットの前提を壊すものがあれば、そのファイルを必須にするか、その設定項目だけを共通ファイル（必須）で扱う。拡張の費用も踏まえて釣り合いの良い方を採る。→ 6.3.1 の致命度（必須／任意）を v2 のファイルにもそのまま当てはめ、割り当てはファイルの中身（キットの前提に関わる設定の有無）で決める。
  4. `.claude/launcher/` の配布レール（6.5 の前提は「ランチャー本体はルート直コミット、`.claude/launcher/` は payload」の 2 本のレール。v2 で部品の置き場やレールが変わらないかの確認）―― 回答: 変わらない想定（利用者へ配布するファイルに含める）。→ 6.5 のずれの分析はそのまま。
  5. v2 の bash 版でも内部変数名の一覧は要るか ―― 回答: custom.env を export で読む方式を続ける想定。→ 一覧は引き続き要る（C-10 (b) のとおり bash 版は `case` の直書き）。
