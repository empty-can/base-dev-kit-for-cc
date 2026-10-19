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
    - しかも環境変数はローカルスコープなので、他のアプリケーションや**別途起動した** Claude Code プロセスには影響しない（例外の可能性: このランチャーで起動したセッションが最初に background service〔supervisor〕を起動した場合、service はその環境を継承する。ゲートウェイ変数は転送対象から外されるが、他の変数が後続の background セッションに波及するかは公式に記載がない ―― 要実測。§5 参照）
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

## 5. background セッションとランチャーの関係（Claude Code v2.1.302 時点）

ランチャーが効くのは**自分が起動した foreground の `claude` プロセス**まで。background セッション（`/bg`・`←`・`/fork`・`claude --bg`・agent view からの dispatch）は background service（supervisor）配下の別プロセスとして起動し直され、構成を次の経路から読む（公式: [agent view「Settings and provider」](https://code.claude.com/docs/en/agent-view#settings-and-provider)、[network-config「Apply network settings to background agents」](https://code.claude.com/docs/en/network-config)）。

| 経路 | background に届くか | 備考 |
|---|---|---|
| 実行ディレクトリの settings（`env` ブロック含む） | 届く | 公式は個人の `~/.claude/settings.json` の `env` を勧めるが、**キットは §3(6) の方針によりこの経路を利用者に使わせない**。組織で固定する分類B/C は managed settings の `env`（管理者の経路）。settings の `env` はシェルの export より優先される |
| 起動時の構成フラグ | 列挙されたものだけ | `--mcp-config` `--strict-mcp-config` `--settings` `--setting-sources`（v2.1.281〜） `--add-dir` `--plugin-dir` `--fallback-model` `--allow-dangerously-skip-permissions`。セッション中に `/add-dir` で足したディレクトリも届く |
| dispatch 元シェルの env | 列挙されたものだけ | `PATH`、`CLAUDE_CODE_USE_BEDROCK` / `CLAUDE_CODE_USE_VERTEX`、`ANTHROPIC_DEFAULT_*_MODEL`、`CLAUDE_CODE_EXTRA_BODY`。ゲートウェイ（`ANTHROPIC_BASE_URL` 等）は supervisor 自身が同じゲートウェイを持つシェルから起動された場合などに限る |
| supervisor を最初に起動したシェルの env | 継承される（起動順次第） | supervisor は全端末で共有され、最初に起動したシェルの環境を継承する。ランチャー経由の `claude` が supervisor を立ち上げた場合に限りランチャーの env が届く＝**確実ではない** |
| `custom.env` / `setup-environment` の値 | **確実には届かない** | 上の行に入るもの（`PATH`・プロバイダ選択等）だけは届く。例: `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`（分類C）が欠け、`--add-dir <Share>` は引き継がれるのに `<Share>` の CLAUDE.md / rules がロードされない |
| system prompt 置換・`--tools` 許可リスト | 引き継がれない | これらで起動したセッションは `/fork` を拒否される |
| Desktop の `/resume` で開いた CLI セッション | ランチャーの env は無い | Windows の Desktop はユーザー／システム環境変数を継承し、PowerShell プロファイルは読まない |

**帰結**: §3 (6) の「`settings.json` 系に `env` を置かない習慣」は background でも例外にしない。background にも効かせたい値は **OS の環境変数**（永続的なユーザー環境変数。Windows はユーザー環境変数、macOS / Linux はログインシェルの profile）で設定する。supervisor は最初に起動したシェルの env を継承するので、OS の環境変数ならどの端末から起動されても届く（既に動いている service には、それが起動した時点の env が使われる）。分類A（機微）も同じく OS 環境変数で供給し、settings には書かない。組織で固定する値だけは managed settings の `env`（管理者の経路）。

### 5-1. 企業ランチャー（`CLAUDE_CODE_PROCESS_WRAPPER`）との関係

background service と agent view の全セッションを起動装置に通す公式経路は `CLAUDE_CODE_PROCESS_WRAPPER`（v2.1.208〜。同等の `processWrapper` 設定は v2.1.210〜）だが、**本ランチャーの代替にも、本ランチャーをそこへ差し込む用途にも使えない**:

- **Windows では無視される**（`exec` 前提の契約のため。設定してもデバッグログに警告が出るだけで、全プロセスがラップされずに動く）。Windows を主とする本キットでは効かない
- user / managed settings の `env`（または `processWrapper` キー）でしか設定できない。project / local settings の値は無視される
- 契約（`exec "$@"` で終わる・引数を並べ替え/先頭追加しない・`exec` の前に端末へ書かない・約 3 秒以内に `exec`）を `start_claude_code.*` は満たさない（OPTS / TEAM_OPTS を先頭に足す、警告を表示する、PS 版は `exec` しない）
- macOS / Linux で必要になったら、本ランチャーとは**別の**薄いスクリプトとして作る
- 参照: https://code.claude.com/docs/en/corporate-launcher

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

---
変更履歴: 初版（2026-07-05）。／**2026-10-19（追補）**: §5-3 の「前にオプションがあってもサブコマンドは dispatch される」という推定を実測で確かめた。`-p` なしでは推定どおりだったが、`-p` があると `--` の有無に関係なく dispatch されずプロンプトになるため、限界の記述を分けた。／**2026-10-19**: §5-3 を新設 ―― 値を複数取る／省略できるフラグが位置引数のプロンプトを取り込むことを実測し、ランチャーに `--` の補完（追加引数が全部非フラグのときだけ）と bash 版の組立順ソートを入れた。／**2026-10-18**: Claude Code v2.1.302 までの実行モデル変更を反映 ―― §5「background セッションとランチャーの関係」を新設（経路別の到達表・引き継がれる構成フラグ・supervisor の env 継承）、§5-1 で `CLAUDE_CODE_PROCESS_WRAPPER` が Windows では無視されることを明記、§5-2 でサブコマンド委譲の注意を追加。§3 (1) の「他の Claude Code プロセスに全く影響しない」と §3 (6) の「settings に env を置かない習慣」に background 前提の注記を追加。／**2026-07-12**: 本書を設計書の正本として規定（IM-8）。§3 の誤字（「Gi追跡」「層1?」）と (5) の複写ミス（option-settings を「環境変数が反映」と誤記）を清書（S-3）。(6) `custom.env` を「センシティブな値の受け皿」とする記述を撤回し、分類A は OS 環境変数で供給する方針へ統一（IM-1）。§4「配布レール」を新設し publish 経路を明記（IM-2 / CR-1）。
