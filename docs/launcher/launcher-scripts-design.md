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

利用者のユースケースは、ランチャーから `claude` を起動する **foreground 起動** と、起動済みのセッションから supervisor（background service）が起動し直す **background 起動** の 2 つに分かれ、ランチャーの効き方が違う。

- **foreground 起動**（ランチャースクリプトから `claude` を起動する通常の使い方）
    - ワンクリックで、適切な値が設定された環境変数と必要な起動時オプションが指定された状態で Claude Code が起動する。
    - 環境変数はプロセス単位（ローカルスコープ）なので、他のアプリケーションや **別途起動した** Claude Code プロセスには影響しない。
    - 起動前の検出（§5.4。ネットワークパスの `--add-dir`・キットの前提が崩れる起動オプション）が効くのはこの経路だけ。
- **background 起動**（`/bg`・`/fork`・`claude --bg`・agent view からの dispatch など。supervisor が別プロセスとして起動し直すセッション）
    - ランチャーは通らない。ランチャーの設定のうち background に届くのは §5 の表の経路だけ ―― 引き継がれる起動時の構成フラグ（`--add-dir`・`--setting-sources` 等。§5 に列挙）、dispatch 元シェルの環境変数のうち列挙されたもの、そして supervisor が最初に起動されたときの環境（このランチャーで起動したセッションが最初に supervisor を起動した場合に限り、service がその環境を継承して後続の background セッション〔別の端末から dispatch したものを含む〕へ波及する。起動順次第で確実ではない。ゲートウェイ変数は転送対象から外される ―― 2026-10-20 実測）。
    - background にも効かせたい値は、settings の `env` ではなく OS の環境変数で設定する（§3.6.2・§5）。
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
- `settings.json`系ファイルに`env`要素を設定しない習慣を根付かせる（うっかりcommit/pushしたり、`settings.local.json`に置いてClaude Codeから読めてしまう状態を作らない）。※ background セッションにも効かせたい値は、settings の `env` ではなく OS の環境変数（永続的なユーザー環境変数）で設定する（§5）。組織で固定する値だけは managed settings の `env`（管理者の経路）
- **機微情報（分類A: APIキー / 認証トークン / パスワード / 組織外秘URL）はこのファイルにも書かない**。OSの環境変数として設定する。`setup-environment`は分類Aの既知キーを検出すると**読み込まずに警告**する（実装計画 §5 / §6-bis）

## 4. 配布レール（publish の実態）

構成ファイルは `.claude/` の内外にまたがるため、**配布レールは 2 本**に分かれる（`publish-share` は `.claude/` 配下しか archive しない）。

| レール | 対象 | 配布先 |
|---|---|---|
| payload（`publish-share`） | `.claude/launcher/*`・`.claude/.gitignore`・`.claude/.gitattributes` | C-BDC（`basic_dot_claude`） |
| ルート直コミット | `start_claude_code.{sh,ps1}`・ルート用 `.gitattributes` | C-BCP（`basic_cc_project`） |

`.claude/.gitignore` と `.claude/.gitattributes` を `.claude/` 配下に置くのは、**配布先でも個人実体の除外と改行固定を効かせる**ため。C-BDK ルートの同名ファイルは payload に乗らず、配布先には届かない（Fable クロスレビュー CR-1）。

## 5. background セッションとランチャーの関係（Claude Code v2.1.302 時点。v2.1.310 の docs で再確認）

ランチャーが効くのは**自分が起動した foreground の `claude` プロセス**まで。background セッション（`/bg`・`←`・`/fork`・`claude --bg`・agent view からの dispatch）は background service（supervisor）配下の別プロセスとして起動し直され、構成を次の経路から読む（公式: [agent view「Settings and provider」](https://code.claude.com/docs/en/agent-view#settings-and-provider)、[network-config「Apply network settings to background agents」](https://code.claude.com/docs/en/network-config)）。

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

### 5.1 企業ランチャー（`CLAUDE_CODE_PROCESS_WRAPPER`）との関係

**本ランチャーは利用者が端末から起動するスクリプトであって、`CLAUDE_CODE_PROCESS_WRAPPER` に登録するランチャーではない**（2026-10-24、v2.1.310 の docs で再判定）。公式の分類では「自分で端末から起動したセッション」に当たり、起動したとおりに動いて `CLAUDE_CODE_PROCESS_WRAPPER` の対象外になる（corporate-launcher「Processes that start outside the launcher」）。

background service と agent view の全セッションを起動装置に通す公式経路は `CLAUDE_CODE_PROCESS_WRAPPER`（v2.1.208〜。同等の `processWrapper` 設定は v2.1.210〜）だが、**本ランチャーの代替にも、本ランチャーをそこへ差し込む用途にも使えない**:

- **Windows では無視される**（`exec` 前提の契約のため。設定してもデバッグログに警告が出るだけで、全プロセスがラップされずに動く）。Windows を主とする本キットでは効かない
- user / managed settings の `env`（または `processWrapper` キー）からしか読まれない。project / local settings の値は無視され、シェルの export も on demand で起動してシェルより長く生きる background service には届かない（読み込み経路の事実。本キットが settings の `env` を勧めるものではない）
- 契約を `start_claude_code.*` は満たさない（下表）
- macOS / Linux で必要になったら、本ランチャーとは**別の**薄いスクリプトとして作る。その際は契約に加えて値の書式に従う: 値はシェルのコマンドではなく引数列として読まれる（変数展開・glob なし。引用していない `;` `|` `&` `$(` は設定エラー）。空白で区切り、二重引用符でまとめる（単一引用符は普通の文字なので `'a b'` は 2 トークン）。`[` で始まる値は JSON 文字列配列で、settings ファイルに書くときは JSON 文字列の中に入れて `"[\"/opt/corp/launcher\", \"--profile\", \"cc\"]"` のようにエスケープする。ランチャー自身の引数は値のパスの後ろに書き、Claude Code のコマンドより先に届くので `exec` の前に `shift` で除く
- 参照: https://code.claude.com/docs/en/corporate-launcher

契約（v2.1.310 時点。v2.1.302 からの追加・変更は太字）と本ランチャーの関係:

| 契約 | 本ランチャー | 扱い |
|---|---|---|
| `exec "$@"` で終わる | bash 版は `exec`、PS 版は子プロセスとして `& claude` を呼んで終了コードを返す | 不適用（登録用途ではない） |
| Claude Code の引数を並べ替え・取り込み・**追加**しない（**ランチャー自身の引数は先頭に届くので、除いてから残りをそのまま渡す**） | OPTS / TEAM_OPTS を足すのが役割。ランチャー自身の引数は持たない | 不適用 |
| 受け継いだ env をすべて `exec` へ渡す（足すのは可） | 足すだけで削らない | 満たす |
| 毎回約 3 秒以内に `exec` する（**background セッションは最初の出力までに最大 3 回続けて呼ぶ。ネットワーク待ちには個別の時間制限を付ける**） | Claude Code からは呼ばれない | 不適用 |
| 自分の中から呼ばれても耐える | 同上 | 不適用 |
| 起動前に端末**にも標準出力にも**書かない（**標準出力は `claude -p` の結果を読むプログラムにも届く**） | 警告・エラーを出しうる。**出力先はすべて stderr**（§5.4） | 端末への表示は役割上残す。stdout には書かない（PS 版は 2026-10-24 に修正） |
| 引数の綴り（`--flag value` / `--flag=value`）に依存しない | `--` の補完は「`-` で始まるか」だけで判定する（§5.3） | 満たす |
| 起動したディレクトリから `exec` する | `cd` しない（ルートの解決はサブシェル／`$PSScriptRoot`） | 満たす |
| **標準入力を読まない**（読む命令は `/dev/null` から与える） | 読まない（custom.env はファイルとして読む） | 満たす。**`claude` の標準入力を `/dev/null` へ向けることはしない**（対話起動は標準入力が端末でないと Windows では exit 1 で終わり、`… \| start_claude_code -p` の入力も失う） |
| **他のプログラムは絶対パスで呼ぶ**（シェルのプロファイルが足す `PATH` が無い状態で起動されうる） | `claude` を `PATH` から探す（利用者のシェルの `PATH` で起動されるため。見つからなければ案内して終了） | 不適用 |

### 5.2 サブコマンドの委譲

ランチャーは組み立てたオプションを利用者の追加引数（`"$@"` / `@args`）の前に置く。`remote-control` / `agents` を追加引数で渡すと verb の前に `--settings` 等が付き、remote-control は起動を拒否し、agents は `--add-dir` / `--mcp-config` が前にあると `--json` が失敗する。サブコマンドは `claude` を直接使う（フラグ形式の `claude --bg "<prompt>"` は問題ない）。

### 5.3 位置引数（プロンプト）の取り込みと `--` の補完（2026-10-19 実測・v2.1.302）

ランチャーは `claude <OPTS> <TEAM_OPTS> <追加引数>` の順に組み立てる。`claude --help`（2.1.302）で値を複数取る（`<x...>`）フラグと値を省略できる（`[x]`）フラグは、直後の非フラグ引数を値として取り込む。組み立てたオプションの最後がこの型だと、追加引数の先頭にあるプロンプトが消える。

- 値を複数取る: `--add-dir` / `--mcp-config` / `--tools` / `--betas` / `--allowedTools` / `--disallowedTools` / `--file`
- 値を省略できる: `--debug` / `--resume` / `--from-pr` / `--worktree` / `--cloud` / `--prompt-suggestions` / `--remote-control` / `--teleport`

実測（2026-10-19。`-p`・無効な API キー・空の `CLAUDE_CONFIG_DIR`・一時 cwd・`timeout 60`。結果は下の表のとおり）:

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

**対策（`start_claude_code.{sh,ps1}`。両版対称）**:

1. 組み立てたオプションが 1 個以上あり、追加引数が 1 個以上で、そのどれも `-` で始まらない（＝プロンプトだけ）ときに限り、間に `--` を挿入する。フラグを含むとき（混在を含む）は挿入しない（素の claude と同じ責任分界）。組み立てたオプションが無いときも挿入しない（既定構成の引数列を素の claude と同一に保つ）。
2. bash 版は連想配列のキーを C ロケールでソートして列挙する。従来はハッシュ順で、書いた順とも一致しなかった（実測: 書いた順 `--tools --add-dir --model` → 列挙 `--add-dir --tools --model`）。PS 版は `[ordered]` の記述順のまま。**両版の組立順が一致するのは、記述順がソート順と同じときだけ**。
3. PS 版は `--` を `$cliArgs` の要素として足す。コマンド行に裸の `--` を書くと、`claude` が `.ps1`（npm のシム等）に解決されたときパラメータバインダに消される。配列要素の `'--'` は pwsh 7.4 / 5.1 とも残る（実測）。

**限界**:

- `"<prompt>" -p` のような混在と、`-` で始まるプロンプトには `--` を補わない。フラグはプロンプトより前に置くか、利用者が自分で `--` を書く。PowerShell では裸の `--` はランチャーに届く前に消えるので `'--'` と引用する（裸の `--` ＋プロンプトだけなら、ランチャーが補うので結果は同じ）。
- `--` はサブコマンドの dispatch を止めない。`-p`（`--print`）なしの構成では、プロンプトが 1 語でサブコマンド名（`mcp` / `doctor` / `update` 等）と一致すると、素の claude と同じくサブコマンドとして実行される（サブコマンドは §5.2 のとおり `claude` を直接使う）。前にオプションがあっても同じ（`claude --add-dir <dir> -- mcp` で実測）。旧ランチャーでは、最後が可変長フラグの構成だとこの 1 語がフラグの値として黙って取り込まれていた。新版ではサブコマンドとして動く（素の claude に近づいた）。
- `-p` を含む構成（OPTS に `--print` を置く等）では、その 1 語はサブコマンドとして dispatch されず、プロンプトとして送られる（`claude -p --add-dir <dir> -- mcp`・`claude -p -- mcp`・`claude -p mcp` で実測。`--` の有無に関係せず、素の claude と同じ）。
- 判定は「`-` で始まるか」だけで、claude 側のフラグ型を見ない。そのためフラグが増えても追随は不要だが、利用者自身が並べた引数（`--add-dir X "prompt"` を追加引数で渡す等）は守らない。

補足（v2.1.310 の docs で確認）: `--bg` / `--background` は裸の `--` より前でだけフラグとして読まれ、`--` の後ろでは文字列になる（v2.1.299〜。[agent view](https://code.claude.com/docs/en/agent-view) の「Prompts that contain `--bg`」）。ランチャーが `--` を補うのは起動時引数に `-` で始まるものが 1 つも無いときだけなので、`start_claude_code --bg "<prompt>"` の `--bg` は従来どおりフラグとして届く。

### 5.4 ランチャーの出力と Claude Code の起動時警告（v2.1.305〜）

- ランチャー（`start_claude_code.*`・`setup-environment.*`）自身の警告・エラーは **stderr にだけ**書き、stdout は `claude` の出力だけにする。`start_claude_code -p "…" > out.txt` のように結果を読むスクリプトへ警告が混ざらないようにするため（§5.1 表の「標準出力に書かない」と同じ理由）。bash 版は当初からすべて `>&2`。PS 版は `Write-Warning` が別のプログラムから起動されたとき stdout に出ていた（pwsh 7.x・Windows PowerShell 5.1 とも 2026-10-24 に実測。pwsh 7 では色付けのエスケープ列ごと出る）ため、`start_claude_code.ps1` が `setup-environment.ps1` を dot-source するパイプラインで warning ストリームを受け、`[Console]::Error` へ「警告: 」付きで書き直すようにした。`setup-environment.ps1` 単体は `Write-Warning` のまま（verify-kit が warning ストリームで受けて bash 版と比べている）。
- Claude Code 自身の起動時警告は、**v2.1.305 以降の対話起動ではデバッグログにしか出ない**（それまでは stderr。権限ルールの一部の警告だけはバナー下の行に出る）。デバッグログはデバッグモードのときだけ残るので、読むには起動時引数に `--debug-file <path>` を足す（option-settings テンプレにも 2026-10-27 に `--debug-file` のキーを足した。W42-F-01）。`-p`（text 出力・background でない）では従来どおり stderr に出る。
- 帰結: `--add-dir` に UNC（`\\server\share`）などのネットワークパスを渡すと、Claude Code はそのディレクトリを外して起動し、対話起動では画面に何も出さない。`<Share>` を UNC で指定すると**キット（CLAUDE.md・rules・skills）が読まれないまま黙って起動する**。Windows ではドライブ文字に割り当ててから渡す（`net use Z: \\server\share` の後に `--add-dir Z:\`）。option-settings テンプレの `--add-dir` の注記にも同旨がある。
- ランチャー側の事前検出は **2026-10-27 決定: 最小範囲で警告**（W42-C-08 の判断。反映は W42-F-05）。option-settings（`OPTS` / `$Opts`）の `--add-dir` の値を見て、`\\` または `//` で始まれば stderr に 1 行警告し、起動は止めない（**2026-11-01 の B-5 で、区分 1 と同じ中断モードの対象になり、PS 版の既定では起動を中止する**。下の中断モードの箇条書き）。**同日のレビューで派生した判断 J-3（2026-10-27。反映は K-01）で、チーム統制の `TEAM_OPTS` / `$TeamOpts` の `--add-dir` も同じ判定で見るように広げた**（チームが `<Share>` を固定するのはそこで、UNC を書くと全員がキット無しで黙って起動するため）。警告文の先頭で値の出どころを示す（`option-settings の --add-dir …` / `start_claude_code のチーム統制（TEAM_OPTS / $TeamOpts） の --add-dir …`。出どころの表記も両版同じ）。両方に UNC があれば option-settings → チーム統制の順に 1 行ずつ出る。文言は両版で同じだった（前置きは bash 版が `⚠ `、PS 版が `警告: `。§5.4 冒頭の出力の約束どおり stderr）が、B-5 で PS 版の文はモードに依存しない形（「… はネットワークパスの形です。ネットワークパスは v2.1.257 以降拒否され、Claude Code はこのディレクトリを黙って外して起動するため、ドライブ文字に割り当てて指定してください。」）に変わり、凍結中の bash 版とは食い違っている（SH-DEFER-02）。ランチャーの警告は v2.1.305 以降も起動前に画面に出るので、デバッグログを開かなくても気づける（`--debug-file` を付けていない利用者には唯一の警告点になる）。範囲を絞った理由:
  - **起動時引数の `--add-dir` は見ない**。利用者が並べた引数は守らない（§5.3 の責任分界と同じ）。
  - **判定は綴りだけ**。シンボリックリンク・ジャンクション経由のネットワークパスや `/net/<host>` は検出しない。解決するとランチャー自身がネットワークへ触れてしまう（Claude Code もそれを避けるために見ないで拒否している）。逆に `\\wsl$` は Claude Code ではネットワークパスとみなされない（errors の同節）が、綴りが `\\` 始まりなので警告が出る（止めないので害は小さい）。ローカルの長いパスやデバイスのパス（`\\?\C:\…`・`\\.\…`）も同じく `\\` 始まりなので警告が出る（2026-10-27 のレビューで確認。ローカルのパスなので警告文の「黙って外して起動します」は当たらないと考えられるが、docs に `\\?\` / `\\.\` の扱いの記載は無く、未実測）。**B-5 以後の既知の帰結**: これらのローカルのパスも、PS 版の既定（`abort`）では起動が止まる。該当する利用者はパスの書き方を変えるか、`$TeamKitCheck` を `'warn'` にする（launcher README 付録 B に記載）。
  - （絞るのをやめたもの）チーム統制の `TEAM_OPTS` / `$TeamOpts` は、W42-F-05 の時点では対象外だった（判断 #6 の範囲が option-settings の値だけだったため）が、2026-10-27 の判断 J-3 で対象に加えた（上記）。
  - `[--add-dir=<パス>]` / `'--add-dir=<パス>'` のような「=」形のキーも見ない（テンプレで案内していない書き方。キーが `--add-dir` そのものの値だけを見る。option-settings・チーム統制とも）。
  - verify-kit は「ランチャー stdout / stderr の振り分け（スタブ）」の一時ツリーに UNC の `--add-dir` を置き、警告が stderr に 1 行・stdout は空であることを見る（fixture `scripts/verify-kit.d/launcher-streams.txt` の `opt` 行。当初は bash / pwsh 7 / 5.1 とも exit 0 で見ていた。B-5 以後の 2 回の実行は下の中断モードの箇条書き）。チーム統制の側は、同じ一時ツリーに複製したランチャーの `TEAM_OPTS` / `$TeamOpts` の定義の行の直後へ probe が `team` 行（別のホスト名の UNC）を差し込み、警告がもう 1 行（option-settings の行の後）出ることを見る（当初は 3 系統。2026-10-30 以後、bash 系統はこの項目ごと凍結中。J-3。実物のランチャーは書き換えない。定義の行〔`declare -A TEAM_OPTS=(` / `$TeamOpts = [ordered]@{`〕がちょうど 1 行でなければ差し込めないので FAIL にする）。断片は ASCII だけなので、出どころの表記（日本語）そのものは verify-kit では照合していない（スタブを使った 2026-10-27 の手元の実測で 3 系統の本文の一致を確認した）。
- ランチャー側の「載せていないオプション」の扱いは **2026-10-30 決定: キットの前提が黙って崩れるもの（区分 1）だけ警告**（2026-10-30 の作業指示者の決定）。対象は、option-settings（`OPTS` / `$Opts`）とチーム統制（`TEAM_OPTS` / `$TeamOpts`）のキーが `--restricted`・`--bare`・`--safe-mode`・`--system-prompt`・`--system-prompt-file` のどれかであるもの（launcher README 付録 A で載せない理由を示したもの。settings・hooks・CLAUDE.md / rules の一部が読まれないまま起動する）と、`--setting-sources` が設定されていて、その値をカンマで分け前後の空白を除いた要素に `project`（大文字小文字を区別した完全一致）が無いもの（キットの `.claude/settings.json` の permissions.deny・hooks と、`--add-dir` で足したディレクトリの skill 等が読まれない）。`--setting-sources` の未設定は既定で全ソースを読むので対象外。値は文字列にしてから見る（PS 版で `$true` を書くと `True` になり、`project` が無いので警告する）。1 件につき stderr に 1 行、UNC の警告と同じ前置き（`警告: `）と出どころの表記で出し、**起動は止めず、キーも捨てない**（そのまま `claude` へ渡す。2026-11-01 の B-5 で中断モードに改めた。下の中断モードの箇条書き）。出力順は UNC の警告の後に、出どころ順（option-settings → チーム統制）、各出どころの中は上の 5 キーの順、最後に `--setting-sources`。文は理由（README 付録 A・付録 B「--setting-sources の影響範囲」に揃える）を述べる（当初は「そのまま渡して起動する（止めない）」「チームで禁じるなら managed settings で固定する」も各行に含めたが、B-5 でモードに依存する部分をまとめ行へ移した）。範囲の決め方:
  - **出どころごとに独立に判定する**。option-settings とチーム統制を合成した実効値（`--setting-sources` はチーム値が後勝ち）は見ない。UNC 検査と同じ責任分界で、書いた場所ごとに直せるようにする（両方に書けば両方に出る）。2026-11-01 に維持と裁定（issue #4 の B-1）。中断モードの既定 `abort` では、option-settings に `user`、チーム統制に `project,user` と書くと、実効値は `project` を含むのに option-settings 側の検出で起動が止まるが、メッセージが出どころとキーを示すので 1 回の修正（option-settings から外す）で済み、チーム値に上書きされて効いていない設定の掃除にもなる。
  - **起動時引数と「=」形のキー（`'--bare=…'` 等）は見ない**（UNC 検査と同じ。§5.3）。判定はキーの綴りだけで、値の正しさは `claude` に任せる。PS 版のキーの照合は `[ordered]` の `Contains` なので大文字小文字を区別しない（`'--Bare'` も警告する。UNC 検査と同じ形。2026-11-01 に維持と裁定〔B-2〕。`claude` 自身が綴りの違うキーをエラーにするので、既定の `abort` でランチャーが先に止まるほうが早く気づける）。
  - ランチャーは統制の境界ではない。チームとして禁じるなら managed settings で固定する（ランチャーの統制には強制力が無い。launcher README §3-1・付録 A）。
  - **対象外にしたもの**: `--allowedTools` / `--disallowedTools`（権限の付け外しで、deny が allow に勝つのでキットの deny は崩れない。方針の話として settings 側で管理する）、`--desktop` / `--environment` / `--ref` とサブコマンド専用のオプション（`claude` 自身が、他の起動オプションとの併用やサブコマンドの外での使用を目に見える形で拒否する）。
  - verify-kit は「ランチャー stdout / stderr の振り分け（スタブ）」の fixture（`launcher-streams.txt`）に `opt` 行（`--restricted`・`--setting-sources user,local`）と `team` 行（`--bare`・警告しない対照の `--setting-sources project,user`）を足し、stderr の行数で対照の行も検証する（2026-10-30 時点は UNC の 2 行を含めて 8 行・exit 0。B-5 以後は下の中断モードの箇条書き）。bash 系統はこの項目を `scripts/verify-kit.d/frozen.txt` で凍結し、FROZEN として集計する（pwsh 7 と 5.1 の 2 系統で判定）。
  - **bash 版は凍結中で未追随**（`docs/launcher/sh-freeze-backlog.md` の SH-DEFER-01）。
- 区分 1 と UNC の `--add-dir` の検出の扱いは **2026-11-01 決定: 中断モード（チーム定数 `$TeamKitCheck`。既定 `abort`）**（作業指示者の裁定。GitHub issue #4 の B-5）。`start_claude_code.ps1` の `$TeamOpts` の直後に `$TeamKitCheck = 'abort'` を置く。UNC の検出と区分 1 の検出（上の 2 つの箇条書き。順も同じ）を配列に溜め、1 件以上あれば、`abort` では前置き `エラー: ` で各行（出どころ付きの理由。本文はモードで変えない）とまとめ 1 行（「エラー: キットの前提が崩れる起動オプションが N 件あるため起動を中止します。該当のキーを外すか、start_claude_code の TEAM_KIT_CHECK / $TeamKitCheck を 'warn' にすると警告だけで起動します。」）を出し、`claude` を起こさずに `exit 1`（既存のエラー終了と同じ終了コード）。`warn` では前置き `警告: ` で各行とまとめ 1 行（「警告: キットの前提が崩れる起動オプションが N 件あります。TEAM_KIT_CHECK / $TeamKitCheck が 'warn' のため、そのまま渡して起動します。」）を出し、キーを捨てずに起動する。粒度は全体の一括切り替え（キーごとの設定は見送り）。決め方:
  - **既定を `abort` にした根拠**: 警告はランチャーが stderr に書いた直後に `claude` の画面が始まるので、目を離すと見逃す。`warn` で見逃しを防ぐには起動前の入力待ちが要るが、`-p`・スクリプトからの起動・background セッションを壊す。中断なら入力待ちなしでメッセージがプロンプトと一緒に残る。多くの利用者は前提が崩れた状態で起動しても終了して設定を直すので、最初から止めたほうが時間を食わない。ただし全員がそう考えるとは限らず、確実な強制は managed settings の仕事なので、切り替えられるようにした。
  - **スイッチの置き場はランチャー本体のチーム定数**（`$TeamOpts` と同じく利用者は触らない。設計 v2 でチーム統制の置き場が外部ファイルに移るなら一緒に移る）。強制力は無く、起動時引数で渡した `--bare` 等は止まらない（§5.3 の責任分界。誤設定の防護柵であって強制ではない）。値が `abort` / `warn` 以外（序数比較。空・大文字小文字の違い・行を消した場合を含む）なら fail-closed で `abort` として扱い、検出の有無にかかわらず `エラー: ` でその旨を 1 行出す（チーム定数の誤りは毎回知らせる。検出が無ければ中止する理由も無いので起動する）。
  - **前置きの使い分け**: `abort` で出す行はログレベル ERROR に当たるので `エラー: `（`abort` はログレベルではないので出力のログレベルを ERROR にする、という作業指示者の補足の指示。別立てにすると「警告: 」で止まる状態が一度できるため B-5 に含めた）。`warn` は従来どおり `警告: `。setup-environment の警告と誤配置の option-settings の警告は、モードに関係なく `警告: ` のまま。stderr の順は setup-environment の警告 → 誤配置の option-settings の警告 →（`$TeamKitCheck` の不正値の 1 行）→ UNC の検出 → 区分 1 の検出 → まとめ行。
  - **読み込みの順序は変えない**: 環境変数の設定（1) setup-environment）→ option-settings の読み込み（3)）→ 検出 → 中止、の順のまま（option-settings の読み込みと検出を setup-environment より前に出せば環境変数の設定より前に止まるが、採らなかった）。理由: 中止は `claude` を起こす前なので、設定済みの環境変数が残っても `claude` の動作には関わらない。option-settings は実行される（dot-source する）スクリプトで、setup-environment が設定した環境変数を参照しうるため、前に出すと結果が変わりうる。setup-environment の警告が先に出る出力の順と節の構成も保てる。帰結: 対話セッションで `.\start_claude_code.ps1` と実行して中止した場合、setup-environment が設定した環境変数（`$env:`。プロセス単位）はそのセッションに残る。これは `claude` が終了した後と同じ状態で、中止で新たに生じる状態ではない（`-File` で起動したときや bash 版は子プロセスなので残らない）。フェーズ 3 で区分 1 の表を共有データにするときは、必須データの読み込みを副作用の前に済ませる方式（issue #4 の C-3）に合わせて順序を改めて検討する。→ §6.4 で整理した（2026-11-02。同日裁定）。
  - **既知の帰結**: UNC の判定は綴りだけなので、`\\wsl$\…`・`\\?\C:\…`・`\\.\…` のようなローカルのパスも既定では起動が止まる（上の UNC の箇条書き。launcher README 付録 B に、パスの書き方を変えるか `$TeamKitCheck` を `'warn'` にすると記載）。
  - verify-kit は「ランチャー stdout / stderr の振り分け（スタブ）」で、同じ一時ツリーのランチャーを 2 回実行する（項目キーは 1 つのまま。結果は節 `launcher-streams abort` / `launcher-streams warn` に分けて書く）。1 回目は複製のまま（既定の `abort`）で、終了コード 0 以外・`claude` スタブ未起動・stdout 空・stderr 9 行（前段の警告 3 行・検出 5 行・まとめ行）を見る。2 回目は probe が複製の `$TeamKitCheck = 'abort'` の行を `'warn'` に書き換えて（実物は書き換えない。定数の行がちょうど 1 行でなければ FAIL）、exit 0・`claude` スタブ起動・stdout 空・stderr 9 行を見る。fixture `launcher-streams.txt` の行頭タグは `stderr-abort` / `stderr-warn`（旧 `stderr` は廃止。断片は ASCII だけで、まとめ行は bash 版と共通にする断片 `TEAM_KIT_CHECK / $TeamKitCheck`。前置きの日本語は照合できないので、モードの違いは終了コードとスタブの起動で見る）。bash 系統は引き続き `frozen.txt` で凍結する（bash 版の probe は `TEAM_KIT_CHECK=abort` の行を `warn` に書き換える形で、その行が無い今は 2 回目が FAIL になる。凍結解除で移植されるまで FAIL になるのが正しい）。
  - **bash 版は凍結中で未追随**（`docs/launcher/sh-freeze-backlog.md` の SH-DEFER-02。bash 版は UNC の `--add-dir` を警告するだけで止めず、区分 1 は検出しない）。
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
| 区分 1 の表 | 必須（`$TeamKitCheck` のモードに依らない。C-6 (b)） | エラー 1 行 ＋ 起動中止（`warn` でも止める） | 暫定案「B-5 のモードに従う」は採らなかった。モードを決める `$TeamKitCheck` は 2) で定義され、1) の環境変数の設定より後にある。モードに従わせたうえで副作用の前に止めるには定数を 1) より前へ動かすことになる。パースだけを前に置き、中止か警告かの判断を 2) の後に回せば定数は動かさずに済む（`abort` の中止が環境変数の設定の後になるが、§5.4 が B-5 で許容している状態と同じで、C-3 (a) の「読み込みは副作用の前」は満たす）。常に必須にした理由は、データの欠落はキットの部品の欠落で、0) が setup-environment の欠落で止めるのと同じ扱いにできること |
| check-assets の U / M / E | 対象外（ランチャーは読まない） | check-assets が FAIL | 検査器自身の表が欠けた状態を PASS にしない（2-g の「未検査」の WARN は検査対象の一時的な読み取りの失敗で、ほかの検査は続く） |

- 出力は stderr に 1 行。必須のデータは `エラー: <ファイルのパス> を読めないため起動を中止します（<無い / 書式: N 行目 …>）。` の形で、`claude` を起こさずに終了コード 0 以外で終わる。任意のデータは無い（どのデータも必須か対象外のどちらか）。
- verify-kit は、一時ツリーのデータファイルを消す・壊す・版を変える probe で、終了コード・`claude` スタブが起動しないこと・stderr の行数とファイル名の断片を見る（bash 系統は凍結中なので `frozen.txt` に行を足す）。

### 6.4 §5.4 の「読み込みの順序は変えない」との関係（2026-11-02 決定）

- §5.4 の判断（setup-environment → option-settings → 検出 → 中止の順を変えない）は、共有データを足しても変えない。そのために「データを読む（パースと書式の検査）」と「検出（option-settings / `$TeamOpts` との照合）」を分け、必須のデータのパースは副作用の前に置き（ランチャーの表は 0) 実行要件の確認の続き、setup-environment の表は custom.env の行ループの前）、検出は従来どおり option-settings の読み込みの後に置く。
- §5.4 が順序を変えなかった理由（option-settings は dot-source して実行するスクリプトで、setup-environment が設定した環境変数を参照しうる）は、静的なデータファイルのパースには当たらない（データは実行されず、環境変数も参照しない）。順序を見直した結果、変えない。
- §5.4 の順序のまま凍結解除で bash 版へ移すときは、`start_claude_code.sh` が setup-environment を source する前に代入して後で読む変数（パースした表など）を内部変数名の一覧に入れる（今の `_ROOT_DIR` と同じ扱い。custom.env の行が export でその変数を書き換えないように）。

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
