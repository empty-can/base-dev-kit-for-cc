# Claude Code ランチャースクリプトコンセプト・構成設計

> **【正本・IM-8】本書は設計書の正本**（実装と同一 PR で共進化する側）。
> research-by-cc 側の同名文書（`reports/04.資産インベントリ・統合/04.ランチャースクリプト実装/`）は
> 2026-07-05 時点の**スナップショット**であり、以後更新しない。差分が出たら本書が正。
> 根拠: Fable クロスレビュー統合 IM-8（2 リポ二重管理によるドリフトを実検出）。
>
> 実装の詳細・判定木・レビュー反映状況は `launcher-implementation-plan.md` を参照。

## 1. 構成ファイルと配置場所

1. `<repo-root>\start_claude_code.sh/.ps1`
2. `<repo-root>\.claude\launcher\setup-environment.sh/.ps1`
3. `<repo-root>\.claude\launcher\option-settings.sh/.ps1.template`
4. `<repo-root>\.claude\launcher\custom.env.template`
5. `<repo-root>\.claude\option-settings.sh/.ps1`
6. `<repo-root>\.claude\custom.env`

## 2. 構成ファイルの関係

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

## 3. 各ファイルの役割

1. `start_claude_code.sh/.ps1`
  - 機能的役割: 
    - 環境変数や起動時オプションを設定した他のファイルをロードし、それらが適用された状態で Claude Code を起動する
    - 必要があれば、Claude Code起動のために必要なロジック的な処理も実施する（ロードした起動時オプション群から起動コマンドを組み立てる処理、など）
  - 利用者向役割: ランチャースクリプトワンクリックで、適切な値が設定された環境変数や必要な起動時オプションが指定された状態でClaude Codeが起動される
    - しかも環境変数はローカルスコープなので、他のアプリケーションや**別途起動した** Claude Code プロセスには影響しない（例外: このランチャーで起動したセッションが最初に background service〔supervisor〕を起動した場合、service はその環境を継承し、後続の background セッション〔別の端末から dispatch したものを含む〕へ波及する ―― 2026-10-20 実測。ゲートウェイ変数は転送対象から外される。§5 参照）
  - Git 追跡対象？・・・yes（層1`basic_cc_project`リポジトリで配布する資産）
2. `setup-environment.sh/.ps1`
  - 機能的役割: 利用者が値を都度設定変更できる`custom.env`の読み込み + 利用者が値を変更不要or変更してはいけない（＝利用メンバー間で決まった値を使うルールになっている）環境変数の値を後勝ち設定で保証する。
  - 利用者向役割: 存在を意識する必要が無い。強いて言えば決まった値を使うルールになっている環境変数の設定に気を遣う必要性から解放される。
  - Git 追跡対象？・・・yes（層1`basic_dot_claude`リポジトリで配布する資産）
3. `option-settings.sh/.ps1.template`
  - 機能的役割: 利用者が実際に値を設定する`option-settings.sh/.ps1`の雛型。Claude Codeのバージョンアップでオプション項目が追加になったり廃止になったりした場合に更新される。
  - 利用者向役割: 
    - オプション項目が追加になったり廃止になったりした場合に更新されるので、その変更を知るきっかけになるとともに、差分だけ`option-settings.sh/.ps1`に反映するという最小限の手間でClaude Codeの仕様変更に追随できる。
    - 利用者が値を設定できる起動時オプションの全量が簡単なコメント付きで記載されており、公式ドキュメントを参照せずに利用できる
  - Git 追跡対象？・・・yes（層1`basic_dot_claude`リポジトリで配布する資産）
4. `custom.env.template`
  - 機能的役割: 
    - 利用者が実際に値を設定する`custom.env`の雛型。Claude Codeのバージョンアップで環境変数が追加になったり廃止になったりした場合に更新される。
  - 利用者向役割: 
    - 環境変数が追加になったり廃止になったりした場合に更新されるので、その変更を知るきっかけになるとともに、差分だけ`custom.env`に反映するという最小限の手間でClaude Codeの仕様変更に追随できる。
    - 利用者が値を設定できる環境変数の全量が簡単なコメント付きで記載されており、公式ドキュメントを参照せずに利用できる
    - 環境変数と異なり統制を取る必要があるようなものは少ないかもしれないが、公式が推奨しているデフォルト値の存在するような起動時オプションについては、その値に設定済み&有効化されるようになっている。
  - Git 追跡対象？・・・yes（層1`basic_dot_claude`リポジトリで配布する資産）
5. `option-settings.sh/.ps1`
  - 機能的役割: `start_claude_code.sh/.ps1`から読み込まれ、ここで定義した**起動時オプション**が`claude`コマンドの引数として組み立てられる（環境変数ではない）。
  - 利用者向役割: 
    - 起動時オプションについて使いたいと思ったらこのファイルを見れば良い、という存在なので、毎度同じような調べものをしたりClaude Codeに質問したりする必要が無くなる。
    - 本来なら`claude`コマンドに続くように記述する必要がある起動時オプションについて、スクリプトの連想配列形式で定義できる。不要なオプションは連想配列の該当行をコメントアウトするだけでよい。
  - Git 追跡対象？・・・no（利用者がテンプレートから手動でコピーして拡張子を変更し利用するファイル）
6. `custom.env`
  - 機能的役割: `setup-environment.sh/.ps1`から読み込まれ、設定された環境変数が反映される（ただし`setup-environment.sh/.ps1`内でハードコードされたユーザカスタマイズ不可の環境変数の値は後勝ちで上書き反映させない）
  - 利用者向役割: 
    - 特にリポジトリでの作業の切り替えに合わせて都度変更するような環境変数について、OSの環境変数を設定してプロンプトを再起動する手間を踏まなくて済むようにする（claudeの再起動だけで反映される）
    - `settings.json`系ファイルに`env`要素を設定しない習慣を根付かせる（うっかりcommit/pushしたり、`settings.local.json`に置いてClaude Codeから読めてしまう状態を作らない）。※ background セッションにも効かせたい値は、settings の `env` ではなく OS の環境変数（永続的なユーザー環境変数）で設定する（§5）。組織で固定する値だけは managed settings の `env`（管理者の経路）
  - **機微情報（分類A: APIキー / 認証トークン / パスワード / 組織外秘URL）はこのファイルにも書かない**。OSの環境変数として設定する。`setup-environment`は分類Aの既知キーを検出すると**読み込まずに警告**する（実装計画 §5 / §6-bis）
  - Git 追跡対象？・・・no（利用者がテンプレートから手動でコピーして拡張子を変更し利用するファイル）

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
| 実行ディレクトリの settings（`env` ブロック含む） | 届く | 公式は個人の `~/.claude/settings.json` の `env` を勧めるが、**キットは §3(6) の方針によりこの経路を利用者に使わせない**。組織で固定する分類B/C は managed settings の `env`（管理者の経路）。settings の `env` はシェルの export より優先される |
| 起動時の構成フラグ | 列挙されたものだけ | `--mcp-config` `--strict-mcp-config` `--settings` `--setting-sources`（v2.1.281〜） `--add-dir` `--plugin-dir` `--fallback-model` `--allow-dangerously-skip-permissions`。セッション中に `/add-dir` で足したディレクトリも届く |
| dispatch 元シェルの env | 列挙されたものだけ | `PATH`、`CLAUDE_CODE_USE_BEDROCK` / `CLAUDE_CODE_USE_VERTEX`、`ANTHROPIC_DEFAULT_*_MODEL`、`CLAUDE_CODE_EXTRA_BODY`。ゲートウェイ（`ANTHROPIC_BASE_URL` と一緒に export した `ANTHROPIC_CUSTOM_HEADERS`・資格情報、プロバイダのゲートウェイ URL と `CLAUDE_CODE_SKIP_*_AUTH` の組）は、supervisor 自身が同じゲートウェイを持つシェルから起動されていて、かつ自分のセッションの background 化・今いるディレクトリへの dispatch・wake・`claude respawn` のときに限る。別のフォルダから dispatch / wake したセッションには渡らず、`No LLM gateway` で失敗する（v2.1.302〜この表示） |
| supervisor を最初に起動したシェルの env | 継承される（起動順次第・2026-10-20 実測） | supervisor は全端末で共有され、それを立ち上げたプロセスの環境を継承する。上の行に無い env はこの経路で決まり、dispatch 元に同名の値があっても supervisor 側の値が使われる。ランチャー経由の `claude` が supervisor を立ち上げた場合に限り、以後は別の端末から dispatch したセッションにもランチャーの env が届く。素のシェル等が先に立ち上げていると、ランチャー経由の `claude --bg` でも届かない＝**確実ではない**。その env は supervisor が止まるまで使われ、auto-update による自己再起動でも変わらない（手順と結果は実装計画 §8-ter (1)） |
| `custom.env` / `setup-environment` の値 | **確実には届かない** | dispatch 元シェルの行に入るもの（`PATH`・プロバイダ選択等）だけは届く。それ以外は、ランチャー経由の `claude` が supervisor を立ち上げた場合だけ届く（上の行）。例: `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`（分類C）が欠け、`--add-dir <Share>` は引き継がれるのに `<Share>` の CLAUDE.md / rules がロードされない |
| system prompt 置換・`--tools` 許可リスト | 引き継がれない | これらで起動したセッションは `/fork` を拒否される |
| Desktop の `/resume` で開いた CLI セッション | ランチャーの env は無い | Windows の Desktop はユーザー／システム環境変数を継承し、PowerShell プロファイルは読まない |

**帰結**: §3 (6) の「`settings.json` 系に `env` を置かない習慣」は background でも例外にしない。background にも効かせたい値は **OS の環境変数**（永続的なユーザー環境変数。Windows はユーザー環境変数、macOS / Linux はログインシェルの profile）で設定する。supervisor は最初に起動したシェルの env を継承するので、OS の環境変数ならどの端末から起動されても届く（既に動いている service には、それが起動した時点の env が使われ、auto-update による自己再起動でも変わらない ―― 2026-10-20 実測）。分類A（機微）も同じく OS 環境変数で供給し、settings には書かない。組織で固定する値だけは managed settings の `env`（管理者の経路）。

**起動環境からしか読まれない変数**もある（公式: [settings-reference「Variables Claude Code ignores in `env`」](https://code.claude.com/docs/en/settings-reference#variables-claude-code-ignores-in-env)）。`CLAUDE_CODE_RESTRICTED`・`CLAUDE_CODE_DISABLE_POWERSHELL_CMD_RM_DENY`・`CLAUDE_CODE_DISABLE_{DANGEROUS_RM_TIMEOUT,SUBSTITUTION_RM_PROMPT,INLINE_SHELL_RM_PROMPT,MOUNTED_DRIVE_RM_PROMPT}`・`CLAUDE_CODE_WARN_{DISK,MEMORY}_FREE_GIB`（v2.1.304〜）などは、managed を含む**どの settings ファイルの `env` でも無視される**。これらは custom.env / setup-environment（foreground のみ）か OS の環境変数（background を含む）でしか効かず、将来 managed settings の `env` へ移す対象にもならない。`CLAUDE_AX_SCREEN_READER` と `CLAUDE_AX_*` は project / local の settings でだけ無視される（v2.1.305〜。user / managed / `--settings` では効く）。

### 5-1. 企業ランチャー（`CLAUDE_CODE_PROCESS_WRAPPER`）との関係

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
| 起動前に端末**にも標準出力にも**書かない（**標準出力は `claude -p` の結果を読むプログラムにも届く**） | 警告・エラーを出しうる。**出力先はすべて stderr**（§5-4） | 端末への表示は役割上残す。stdout には書かない（PS 版は 2026-10-24 に修正） |
| 引数の綴り（`--flag value` / `--flag=value`）に依存しない | `--` の補完は「`-` で始まるか」だけで判定する（§5-3） | 満たす |
| 起動したディレクトリから `exec` する | `cd` しない（ルートの解決はサブシェル／`$PSScriptRoot`） | 満たす |
| **標準入力を読まない**（読む命令は `/dev/null` から与える） | 読まない（custom.env はファイルとして読む） | 満たす。**`claude` の標準入力を `/dev/null` へ向けることはしない**（対話起動は標準入力が端末でないと Windows では exit 1 で終わり、`… \| start_claude_code -p` の入力も失う） |
| **他のプログラムは絶対パスで呼ぶ**（シェルのプロファイルが足す `PATH` が無い状態で起動されうる） | `claude` を `PATH` から探す（利用者のシェルの `PATH` で起動されるため。見つからなければ案内して終了） | 不適用 |

### 5-2. サブコマンドの委譲

ランチャーは組み立てたオプションを利用者の追加引数（`"$@"` / `@args`）の前に置く。`remote-control` / `agents` を追加引数で渡すと verb の前に `--settings` 等が付き、remote-control は起動を拒否し、agents は `--add-dir` / `--mcp-config` が前にあると `--json` が失敗する。サブコマンドは `claude` を直接使う（フラグ形式の `claude --bg "<prompt>"` は問題ない）。

### 5-3. 位置引数（プロンプト）の取り込みと `--` の補完（2026-10-19 実測・v2.1.302）

ランチャーは `claude <OPTS> <TEAM_OPTS> <追加引数>` の順に組み立てる。`claude --help`（2.1.302）で値を複数取る（`<x...>`）フラグと値を省略できる（`[x]`）フラグは、直後の非フラグ引数を値として取り込む。組み立てたオプションの最後がこの型だと、追加引数の先頭にあるプロンプトが消える。

- 値を複数取る: `--add-dir` / `--mcp-config` / `--tools` / `--betas` / `--allowedTools` / `--disallowedTools` / `--file`
- 値を省略できる: `--debug` / `--resume` / `--from-pr` / `--worktree` / `--cloud` / `--prompt-suggestions` / `--remote-control` / `--teleport`

実測（`-p`・無効な API キー・空の `CLAUDE_CONFIG_DIR`・一時 cwd・`timeout 60`。ログは報告 `.claude/reports/2026-10-19_cc-update_F_launcher-positional-args.md`。gitignore 対象）:

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
- `--` はサブコマンドの dispatch を止めない。`-p`（`--print`）なしの構成では、プロンプトが 1 語でサブコマンド名（`mcp` / `doctor` / `update` 等）と一致すると、素の claude と同じくサブコマンドとして実行される（サブコマンドは §5-2 のとおり `claude` を直接使う）。前にオプションがあっても同じ（`claude --add-dir <dir> -- mcp` で実測）。旧ランチャーでは、最後が可変長フラグの構成だとこの 1 語がフラグの値として黙って取り込まれていた。新版ではサブコマンドとして動く（素の claude に近づいた）。
- `-p` を含む構成（OPTS に `--print` を置く等）では、その 1 語はサブコマンドとして dispatch されず、プロンプトとして送られる（`claude -p --add-dir <dir> -- mcp`・`claude -p -- mcp`・`claude -p mcp` で実測。`--` の有無に関係せず、素の claude と同じ）。
- 判定は「`-` で始まるか」だけで、claude 側のフラグ型を見ない。そのためフラグが増えても追随は不要だが、利用者自身が並べた引数（`--add-dir X "prompt"` を追加引数で渡す等）は守らない。

補足（v2.1.310 の docs で確認）: `--bg` / `--background` は裸の `--` より前でだけフラグとして読まれ、`--` の後ろでは文字列になる（v2.1.299〜。[agent view](https://code.claude.com/docs/en/agent-view) の「Prompts that contain `--bg`」）。ランチャーが `--` を補うのは起動時引数に `-` で始まるものが 1 つも無いときだけなので、`start_claude_code --bg "<prompt>"` の `--bg` は従来どおりフラグとして届く。

### 5-4. ランチャーの出力と Claude Code の起動時警告（v2.1.305〜）

- ランチャー（`start_claude_code.*`・`setup-environment.*`）自身の警告・エラーは **stderr にだけ**書き、stdout は `claude` の出力だけにする。`start_claude_code -p "…" > out.txt` のように結果を読むスクリプトへ警告が混ざらないようにするため（§5-1 表の「標準出力に書かない」と同じ理由）。bash 版は当初からすべて `>&2`。PS 版は `Write-Warning` が別のプログラムから起動されたとき stdout に出ていた（pwsh 7.x・Windows PowerShell 5.1 とも 2026-10-24 に実測。pwsh 7 では色付けのエスケープ列ごと出る）ため、`start_claude_code.ps1` が `setup-environment.ps1` を dot-source するパイプラインで warning ストリームを受け、`[Console]::Error` へ「警告: 」付きで書き直すようにした。`setup-environment.ps1` 単体は `Write-Warning` のまま（verify-kit が warning ストリームで受けて bash 版と比べている）。
- Claude Code 自身の起動時警告は、**v2.1.305 以降の対話起動ではデバッグログにしか出ない**（それまでは stderr。権限ルールの一部の警告だけはバナー下の行に出る）。デバッグログはデバッグモードのときだけ残るので、読むには起動時引数に `--debug-file <path>` を足す（option-settings テンプレにも 2026-10-27 に `--debug-file` のキーを足した。W42-F-01）。`-p`（text 出力・background でない）では従来どおり stderr に出る。
- 帰結: `--add-dir` に UNC（`\\server\share`）などのネットワークパスを渡すと、Claude Code はそのディレクトリを外して起動し、対話起動では画面に何も出さない。`<Share>` を UNC で指定すると**キット（CLAUDE.md・rules・skills）が読まれないまま黙って起動する**。Windows ではドライブ文字に割り当ててから渡す（`net use Z: \\server\share` の後に `--add-dir Z:\`）。option-settings テンプレの `--add-dir` の注記にも同旨がある。
- ランチャー側の事前検出は **2026-10-27 決定: 最小範囲で警告**（W42-C-08 の判断。反映は W42-F-05）。option-settings（`OPTS` / `$Opts`）の `--add-dir` の値を見て、`\\` または `//` で始まれば stderr に 1 行警告し、起動は止めない。**同日のレビューで派生した判断 J-3（2026-10-27。反映は K-01）で、チーム統制の `TEAM_OPTS` / `$TeamOpts` の `--add-dir` も同じ判定で見るように広げた**（チームが `<Share>` を固定するのはそこで、UNC を書くと全員がキット無しで黙って起動するため）。警告文の先頭で値の出どころを示す（`option-settings の --add-dir …` / `start_claude_code のチーム統制（TEAM_OPTS / $TeamOpts） の --add-dir …`。出どころの表記も両版同じ）。両方に UNC があれば option-settings → チーム統制の順に 1 行ずつ出る。文言は両版で同じ（前置きは bash 版が `⚠ `、PS 版が `警告: `。§5-4 冒頭の出力の約束どおり stderr）。ランチャーの警告は v2.1.305 以降も起動前に画面に出るので、デバッグログを開かなくても気づける（`--debug-file` を付けていない利用者には唯一の警告点になる）。範囲を絞った理由:
  - **起動時引数の `--add-dir` は見ない**。利用者が並べた引数は守らない（§5-3 の責任分界と同じ）。
  - **判定は綴りだけ**。シンボリックリンク・ジャンクション経由のネットワークパスや `/net/<host>` は検出しない。解決するとランチャー自身がネットワークへ触れてしまう（Claude Code もそれを避けるために見ないで拒否している）。逆に `\\wsl$` は Claude Code ではネットワークパスとみなされない（errors の同節）が、綴りが `\\` 始まりなので警告が出る（止めないので害は小さい）。ローカルの長いパスやデバイスのパス（`\\?\C:\…`・`\\.\…`）も同じく `\\` 始まりなので警告が出る（2026-10-27 のレビューで確認。ローカルのパスなので警告文の「黙って外して起動します」は当たらないと考えられるが、docs に `\\?\` / `\\.\` の扱いの記載は無く、未実測）。
  - （絞るのをやめたもの）チーム統制の `TEAM_OPTS` / `$TeamOpts` は、W42-F-05 の時点では対象外だった（判断 #6 の範囲が option-settings の値だけだったため）が、2026-10-27 の判断 J-3 で対象に加えた（上記）。
  - `[--add-dir=<パス>]` / `'--add-dir=<パス>'` のような「=」形のキーも見ない（テンプレで案内していない書き方。キーが `--add-dir` そのものの値だけを見る。option-settings・チーム統制とも）。
  - verify-kit は「ランチャー stdout / stderr の振り分け（スタブ）」の一時ツリーに UNC の `--add-dir` を置き、bash / pwsh 7 / 5.1 とも警告が stderr に 1 行・stdout は空・exit 0 であることを見る（fixture `scripts/verify-kit.d/launcher-streams.txt` の `opt` 行）。チーム統制の側は、同じ一時ツリーに複製したランチャーの `TEAM_OPTS` / `$TeamOpts` の定義の行の直後へ probe が `team` 行（別のホスト名の UNC）を差し込み、警告がもう 1 行（option-settings の行の後）出ることを 3 系統で見る（J-3。実物のランチャーは書き換えない。定義の行〔`declare -A TEAM_OPTS=(` / `$TeamOpts = [ordered]@{`〕がちょうど 1 行でなければ差し込めないので FAIL にする）。断片は ASCII だけなので、出どころの表記（日本語）そのものは verify-kit では照合していない（スタブを使った手元の実測で 3 系統の本文の一致を確認した。K 報告書）。
- ランチャー側の「載せていないオプション」の扱いは **2026-10-30 決定: キットの前提が黙って崩れるもの（区分 1）だけ警告**（作業指示者の決定。スクリプト追加改善の計画書 00 §3 フェーズ 2）。対象は、option-settings（`OPTS` / `$Opts`）とチーム統制（`TEAM_OPTS` / `$TeamOpts`）のキーが `--restricted`・`--bare`・`--safe-mode`・`--system-prompt`・`--system-prompt-file` のどれかであるもの（launcher README 付録 A で載せない理由を示したもの。settings・hooks・CLAUDE.md / rules の一部が読まれないまま起動する）と、`--setting-sources` が設定されていて、その値をカンマで分け前後の空白を除いた要素に `project`（大文字小文字を区別した完全一致）が無いもの（キットの `.claude/settings.json` の permissions.deny・hooks と、`--add-dir` で足したディレクトリの skill 等が読まれない）。`--setting-sources` の未設定は既定で全ソースを読むので対象外。値は文字列にしてから見る（PS 版で `$true` を書くと `True` になり、`project` が無いので警告する）。1 件につき stderr に 1 行、UNC の警告と同じ前置き（`警告: `）と出どころの表記で出し、**起動は止めず、キーも捨てない**（そのまま `claude` へ渡す）。出力順は UNC の警告の後に、出どころ順（option-settings → チーム統制）、各出どころの中は上の 5 キーの順、最後に `--setting-sources`。警告文は理由（README 付録 A・付録 B「--setting-sources の影響範囲」に揃える）と「そのまま渡して起動する（止めない）」「チームで禁じるなら managed settings で固定する」を 1 行に含める。範囲の決め方:
  - **出どころごとに独立に判定する**。option-settings とチーム統制を合成した実効値（`--setting-sources` はチーム値が後勝ち）は見ない。UNC 検査と同じ責任分界で、書いた場所ごとに直せるようにする（両方に書けば両方に出る）。
  - **起動時引数と「=」形のキー（`'--bare=…'` 等）は見ない**（UNC 検査と同じ。§5-3）。判定はキーの綴りだけで、値の正しさは `claude` に任せる。PS 版のキーの照合は `[ordered]` の `Contains` なので大文字小文字を区別しない（`'--Bare'` も警告する。UNC 検査と同じ形）。
  - ランチャーは統制の境界ではない。チームとして禁じるなら managed settings で固定する（ランチャーの統制には強制力が無い。launcher README §3-1・付録 A）。
  - **対象外にしたもの**: `--allowedTools` / `--disallowedTools`（権限の付け外しで、deny が allow に勝つのでキットの deny は崩れない。方針の話として settings 側で管理する）、`--desktop` / `--environment` / `--ref` とサブコマンド専用のオプション（`claude` 自身が、他の起動オプションとの併用やサブコマンドの外での使用を目に見える形で拒否する）。
  - verify-kit は「ランチャー stdout / stderr の振り分け（スタブ）」の fixture（`launcher-streams.txt`）に `opt` 行（`--restricted`・`--setting-sources user,local`）と `team` 行（`--bare`・警告しない対照の `--setting-sources project,user`）を足し、stderr が UNC の 2 行を含めて 8 行であることを見る（対照の行は行数の一致で検証される）。bash 系統はこの項目を `scripts/verify-kit.d/frozen.txt` で凍結し、FROZEN として集計する（pwsh 7 と 5.1 の 2 系統で判定）。
  - **bash 版は凍結中で未追随**（`docs/launcher/sh-freeze-backlog.md` の SH-DEFER-01）。
- 参照: https://code.claude.com/docs/en/errors#configuration-warnings 、https://code.claude.com/docs/en/errors#working-directory-is-a-network-path

---
変更履歴: 初版（2026-07-05）。／**2026-10-30**: §5-4 に、ランチャーが option-settings / チーム統制にあるキットの前提が黙って崩れる起動オプション（区分 1: `--restricted`・`--bare`・`--safe-mode`・`--system-prompt`・`--system-prompt-file` と、`project` を含まない `--setting-sources`）を出どころ付きで stderr に警告する決定（作業指示者。止めない・捨てない。PowerShell 版のみで、bash 版は凍結中の SH-DEFER-01）と、対象・挙動・責任分界・対象外にしたもの・verify-kit の検査を記した。／**2026-10-27**: §5-4 の「未決」だった `<Share>` の UNC の事前検出を、作業指示者の判断（最小範囲で警告）に従って決定済みにし、範囲を絞った理由と verify-kit の検査を記した（W42-F-05）。option-settings テンプレに `--debug-file` のキーを足したことを §5-4 に注記（W42-F-01）。同日のレビュー（/code-review）で、§5-4 の「判定は綴りだけ」に `\\?\C:\…`・`\\.\…` でも警告が出ること（docs に扱いの記載が無く未実測）を、範囲を絞った理由に「=」形のキーを見ないことを補った。同日、レビューで派生した要判断 J-3 の作業指示者の判断（(b) 広げる）に従い、§5-4 の UNC の事前検出の対象にチーム統制の `TEAM_OPTS` / `$TeamOpts` の `--add-dir` を加え（警告文の先頭で出どころを示す）、verify-kit の検査（probe が一時ツリーのランチャーに `team` 行を差し込む）を記した（K-01）。／**2026-10-24**: Claude Code v2.1.310 までの docs 差分を反映 ―― §5-1 で本ランチャーが `CLAUDE_CODE_PROCESS_WRAPPER` に登録するものではないことを明記し、v2.1.310 時点の契約（標準入力を読まない・標準出力にも書かない・他プログラムは絶対パス・background セッションは最大 3 回続けて呼ぶ・ランチャー自身の引数は `shift` で除く）と本ランチャーの関係を表にした。値の書式（`'a b'` は 2 トークン、settings 内の JSON 配列のエスケープ）を「別スクリプトを作るとき」の注記に追加。§5-4 を新設し、ランチャーの出力は stderr だけにすること（PS 版の `Write-Warning` が stdout に出ていたのを実測して修正）と、v2.1.305 以降は対話起動の起動時警告がデバッグログにしか出ないこと・`--add-dir` の UNC が黙って外れることを記した。§5 に起動環境からしか読まれない変数（managed を含む全 settings の `env` で無視）と、ゲートウェイが background へ渡る条件（同じディレクトリ・`claude respawn`。別フォルダは `No LLM gateway`）を追記。§5 の到達表・引き継がれる構成フラグは v2.1.310 の docs でも変わっていないことを確認した。§5-3 に `--bg` と `--` の関係（v2.1.299〜）を補足。／**2026-10-20（追補）**: §5 表の「supervisor を最初に起動したシェルの env」行と「`custom.env` / `setup-environment` の値」行、§3 1. の例外注記を実測で確定した（実装計画 §8-ter (1)）。推定どおり起動順次第で、ランチャー経由の `claude` が supervisor を立ち上げると、別の端末から dispatch したセッションにも値が波及し、dispatch 元の同名の値より優先される。素のシェルが先に立ち上げていると、ランチャー経由の `claude --bg` でも届かない。／**2026-10-19（追補）**: §5-3 の「前にオプションがあってもサブコマンドは dispatch される」という推定を実測で確かめた。`-p` なしでは推定どおりだったが、`-p` があると `--` の有無に関係なく dispatch されずプロンプトになるため、限界の記述を分けた。／**2026-10-19**: §5-3 を新設 ―― 値を複数取る／省略できるフラグが位置引数のプロンプトを取り込むことを実測し、ランチャーに `--` の補完（追加引数が全部非フラグのときだけ）と bash 版の組立順ソートを入れた。／**2026-10-18**: Claude Code v2.1.302 までの実行モデル変更を反映 ―― §5「background セッションとランチャーの関係」を新設（経路別の到達表・引き継がれる構成フラグ・supervisor の env 継承）、§5-1 で `CLAUDE_CODE_PROCESS_WRAPPER` が Windows では無視されることを明記、§5-2 でサブコマンド委譲の注意を追加。§3 (1) の「他の Claude Code プロセスに全く影響しない」と §3 (6) の「settings に env を置かない習慣」に background 前提の注記を追加。／**2026-07-12**: 本書を設計書の正本として規定（IM-8）。§3 の誤字（「Gi追跡」「層1?」）と (5) の複写ミス（option-settings を「環境変数が反映」と誤記）を清書（S-3）。(6) `custom.env` を「センシティブな値の受け皿」とする記述を撤回し、分類A は OS 環境変数で供給する方針へ統一（IM-1）。§4「配布レール」を新設し publish 経路を明記（IM-2 / CR-1）。
