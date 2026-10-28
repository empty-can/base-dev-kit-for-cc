# 起動ランチャーの部品（launcher/）

このフォルダは、環境変数と起動オプションを統制した状態で `claude` を起動するランチャーの部品である。ランチャー本体はリポジトリのルートにある `start_claude_code.sh`（bash 版）／`start_claude_code.ps1`（PowerShell 版）で、このフォルダのスクリプトを読み込む。利用者が値を書くのは、このフォルダのテンプレートからコピーして作るファイルだけである。

テンプレートのコメントには、キー / 変数ごとの意味・値・既定と短い注意だけを書いている。既定値の決まり方・背景・注意の詳細はこの README にまとめる。テンプレートのコメントにある「README §2-4」などは、このファイルの節を指す。

## 1. ファイルと置き場所

| テンプレート | コピー先（個人の実体） | 読み込むもの |
|---|---|---|
| `custom.env.template` | `.claude/custom.env` | `setup-environment.{sh,ps1}`（ランチャーが起動時に呼ぶ） |
| `option-settings.sh.template` | `.claude/option-settings.sh` | `start_claude_code.sh` |
| `option-settings.ps1.template` | `.claude/option-settings.ps1` | `start_claude_code.ps1` |

- **コピー先は `.claude/` 直下**（このフォルダの一つ上）であって、テンプレートの隣（`.claude/launcher/`）ではない。`.claude/launcher/` に置いたものは読み込まれず、ランチャーが起動時に警告する（警告文の例: 「… は読み込まれません。… は一つ上の .claude/ 直下に置いてください。」）。
- コピーしたファイルは `.gitignore` 済みで、コミットされない個人の実体になる。
- 使う行の先頭の `# ` を外して値を設定する。不要な行はコメントのままにする。変更は `claude` の再起動だけで反映される（OS の環境変数の再設定・再ログインは不要）。
- bash 版のランチャーを使うなら `option-settings.sh`、PowerShell 版なら `option-settings.ps1` を作る。
- `setup-environment.{sh,ps1}` はチームで揃える値を置くスクリプトで、利用者が値を書く場所ではない（§2-3）。

テンプレートのタイトルにある「分類D」は、値の置き場所を決める次の分類のことである。

| 分類 | 対象 | 置き場所 |
|---|---|---|
| A | 機微情報（API キー・認証トークン・パスワード・組織外秘の URL 等） | OS の環境変数だけ。ランチャーのどのファイルにも書かない（§2-2） |
| B | 組織単位で統制する値 | 組織の管理者が managed settings で固定する。それが始まるまでの暫定として、非機微のものだけ `setup-environment` に置く |
| C | チーム単位で統制する値 | 環境変数は `setup-environment`、起動オプションは `start_claude_code` の `TEAM_OPTS` / `$TeamOpts` |
| D | 統制不要・利用者が都度変える・非機微の値 | `custom.env` と `option-settings`（このフォルダのテンプレートから作る） |

## 2. custom.env（環境変数）

### 2-1. 書式の細則と理由

`setup-environment` は custom.env を実行（source）せず、1 行ずつ読む。CRLF の `\r` を落として bash 版と PowerShell 版を同じ結果に揃えるためと、書かれた任意のコードが実行されるのを防ぐためである。bash 版・PowerShell 版のどちらでも同じ結果になるよう、書ける形を絞っている。

- 1 行 1 件の「KEY=VALUE」のみ。前後の空白は除かれ、空行と行頭 `#` のコメント行は無視される。`=` を含まない行も無視される。
- 値をクォートで囲まない（引用符は値の一部として残る）。`export ` を前置しない。
- 値の中で `$VAR` / `%VAR%` の展開はできない（文字どおりに扱われる）。
- 行末に `# コメント` を書かない（`#` 以降も値に含まれる）。
- 環境変数名として不正な名前（英字・数字・`_` 以外を含む、数字で始まる等）の行は、警告して読み飛ばす。
- ランチャーが内部で使う名前（例: `IFS`・`_SENSITIVE_KEYS`・`_ROOT_DIR`・`_line`）は書けない。書くと起動時に警告し、その行を読み込まない。bash 版では読み込み処理そのものを書き換えてしまうためで、PowerShell 版も結果を揃えるため同じ名前を読み飛ばす。一覧は同じフォルダの `setup-environment.{sh,ps1}` にある。
- 改行は LF。CRLF でもローダが `\r` を落とすので動く。
- 文字コードは UTF-8（BOM は付けても付けなくてもよい）。bash・pwsh 7・Windows PowerShell 5.1 のいずれも、ローダが UTF-8 として読むよう明示している（`setup-environment.ps1` は `-Encoding UTF8` で読み、BOM 付きも自動で除去される）ため、BOM 無し UTF-8 の日本語の値も 5.1 で正しく入る。ANSI / CP932 で保存すると非 ASCII の値が化ける。
- 空値（例: `NO_PROXY=`）は、bash / macOS / Linux では「空の変数」を作るが、Windows は空文字の環境変数を保持できないため、PowerShell 版では設定されず警告が出る（挙動が割れる）。
- on/off 型の変数は 1 / true / yes / on で有効、0 / false / no / off で無効が原則。ただし `DISABLE_TELEMETRY`・`DISABLE_ERROR_REPORTING`・`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` 等は「設定されていれば有効」で、0 と書いても有効になる。止めるには行を消す（コメントアウトする）。空値で止める方法は、上のとおり Windows では使えない。

### 2-2. 機微情報（分類A）を書かない

API キー・認証トークン・パスワード・組織外秘の URL などの機微情報は custom.env に書かない。OS の環境変数として設定する。`setup-environment` は次のものを custom.env に見つけると、起動時に警告してその行を読み込まない（「custom.env の … は読み込みません（分類A: 機微）」）。

- **既知のキー**: 例 `ANTHROPIC_API_KEY`・`ANTHROPIC_AUTH_TOKEN`・`CLAUDE_CODE_OAUTH_TOKEN`・`AWS_BEARER_TOKEN_BEDROCK`・`ANTHROPIC_FOUNDRY_API_KEY`・`ANTHROPIC_AWS_API_KEY`・`OTEL_EXPORTER_OTLP_HEADERS`・`ANTHROPIC_CUSTOM_HEADERS`。一覧は同じフォルダの `setup-environment.{sh,ps1}` にある。
- **資格情報らしい名前**（大文字小文字を区別しない）: `*_API_KEY` / `*_TOKEN` / `*_ACCESS_KEY` / `*_PRIVATE_KEY` / `*_SECRET` / `*_PASSWORD` 等と、`API_KEY` / `TOKEN` / `SECRET` のような名前全体・`SECRET_*`・`*_PASS` / `*_PASSWD` / `*_PWD` / `*_CONNECTION_STRING`。`MAX_THINKING_TOKENS` のような `*_TOKENS` は対象外。
- **資格情報入りの URL**: 値のどこかに `://user:pass@` や `://token@` を含むもの。http / https / ws / wss / ftp では、`//` を省いた `http:user:pass@host` や `\` を使った `https:\token@host` も claude は認証付き URL として使うので、同じ扱い（大文字小文字を区別しない）。

判定は名前と値の形で機械的に行うため、無害な値も止まることがある。その場合は OS の環境変数に置く。

- `ANTHROPIC_CUSTOM_HEADERS` は Authorization ヘッダを運ぶことが多いため、タグ付けだけの無害なヘッダでも読み込まれない。
- `user@` 形式（パスワード無し。`https://<token>@host`）の URL も機微として扱うため、`ssh://git@github.com/...` や `smtp://noreply@mail.example` のような無害な値も読み込まれない。

認証付きプロキシ（`http://user:pass@host:port` 形式。`//` を省いた `http:user:pass@host:port` も同じ）の URL も分類A。custom.env にも `setup-environment` にも書かず、OS の環境変数で設定する。

### 2-3. 優先順位とチームで揃える値

- `setup-environment` は custom.env を読み込んだ後に、チーム（分類C）・組織（分類B）で揃える環境変数を設定する。同じ変数を custom.env に書いても、最終的に `setup-environment` の値で上書きされる（後勝ち）。
- この後勝ちが効くのはランチャーの中（custom.env に対して）だけ。settings.json（user / project / local）の `env` に同じ変数があると、そちらが勝つ（`/setup-bedrock`・`/setup-vertex` も user settings の `env` へ書き込む）。利用者が覆せない固定が要る値は、組織の管理者が managed settings の `env` に置く。
- 個人の値は custom.env か OS の環境変数に置く。settings 系ファイルの `env` には置かない（誤って commit / push する、Claude から読める場所に値が残る、を避けるため）。
- チームで揃えたい値は、環境変数なら `setup-environment.{sh,ps1}`、起動オプションなら `start_claude_code.{sh,ps1}` の `TEAM_OPTS` / `$TeamOpts` に置く。テンプレートで「チームで揃えるなら」としているのは次の値:
  - コンテキスト・キャッシュの節の変数（コストに影響する）
  - `CLAUDE_CODE_USE_POWERSHELL_TOOL`
  - 企業プロキシ前提のチームのプロキシ設定（`HTTP_PROXY` 等。認証付きのものは §2-2 のとおり OS の環境変数）

### 2-4. 項目ごとの補足

#### サブエージェントのモデル（CLAUDE_CODE_SUBAGENT_MODEL）

- v2.1.251 以降は既定値扱いで、agent 定義の `model:` と呼び出し時の指定が優先される。定義側の指定も無視して全サブエージェントへ強制したい場合だけ `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`（v2.1.257 以降）を併用する。
- キットの `code-reviewer` は `model: sonnet` 固定のため影響しない。

#### effort と思考予算（CLAUDE_CODE_EFFORT_LEVEL・MAX_THINKING_TOKENS）

- 現行モデル（Opus 4.7 以降 / Sonnet 5 以降 / Haiku 5.5 / Fable 系）は adaptive reasoning 専用で、思考の量は effort で決まる。
- `CLAUDE_CODE_EFFORT_LEVEL` を設定すると、`--effort` やセッション内の `/effort` より優先され、起動中に変えられなくなる。都度変えたいなら設定せず `/effort` を使う。max を毎回効かせたい場合は、この環境変数が唯一の手段。
- `MAX_THINKING_TOKENS` は旧方式の固定思考予算。上記の現行モデルでは正の値は無視される。効くのは Opus 4.6 / Sonnet 4.6 で、adaptive reasoning を止める `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` を 1 にして併用した場合だけ。

#### 自動圧縮ウィンドウ（--autocompact・CLAUDE_CODE_AUTO_COMPACT_WINDOW）

- `--autocompact` はこのセッションだけに効き、保存済みの設定は変えない。値は auto（モデルの既定）かトークン数（200000 / 500k / 1M / 100〜1000〔千単位〕）。範囲は 100K〜1M（v2.1.221 以降）。
- 環境変数 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` を設定すると、`--autocompact`・`/autocompact`・autoCompactWindow 設定より優先され、`/autocompact` では変えられなくなる（使えない値のときだけ無視され、フラグが効く）。原則は `--autocompact` か `/autocompact` を使う。
- 書き方が違う。環境変数では接尾辞なしの数値はトークン数そのもので、200 は 200 トークン扱い（下限の 100K に丸められる）。`--autocompact 200` なら 200,000。環境変数の k / M 接尾辞（200k / 1M）は v2.1.304 以降で、それ未満では 200k も 200 と読まれる。範囲外・使えない値は警告が出る。

#### fork モード（CLAUDE_CODE_FORK_SUBAGENT）

- 既定で有効。v2.1.302 以降は `claude -p` / Agent SDK を含む全セッション、それ未満は対話セッションのみ。
- 有効な間、対話セッションでは Claude がサブエージェントの完了を待てない（すべて background で動く）。0 で無効にすると、頼めば待つ。すべてのサブエージェントを待たせるなら `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` を 1 にする（Bash / PowerShell の background 実行なども止まる。テンプレートのコメントを参照）。

#### API リクエストのタイムアウト（API_TIMEOUT_MS）

- 各試行がレスポンスヘッダを受け取るまでの待ち時間で、ヘッダ受信後の streaming 応答の長さは制限しない。非 streaming の試行は、全体がこの時間内に終わる必要がある。
- 0 で無制限（v2.1.305 以降）。ただし 0 でも、ローカルの非 streaming 試行は 300 秒で切れる。

#### 空き容量の警告（CLAUDE_CODE_WARN_DISK_FREE_GIB）

- settings の `env` では無視される変数なので、起動環境（custom.env か OS の環境変数）で設定する。

#### プロキシ

- SOCKS プロキシは非対応。NTLM / Kerberos が要るなら LLM ゲートウェイを検討する。
- 認証付きプロキシの URL は書かない（§2-2）。チームで揃えるなら §2-3。

## 3. option-settings（起動オプション）

### 3-1. 組み立て順とチーム統制

ランチャーは次の順で `claude` の引数を組み立てる。

```
claude <OPTS> <TEAM_OPTS> [--] <起動時引数>
```

- `OPTS`（PowerShell 版は `$Opts`）が option-settings、`TEAM_OPTS`（PowerShell 版は `$TeamOpts`）が `start_claude_code` の中にあるチーム統制の起動オプション（分類C）。
- 同じフラグを両方に書いた場合、値を 1 つだけ取るフラグは、後に置かれる `TEAM_OPTS` の値が採用される（後勝ち）。`--add-dir` のような繰り返して指定できるフラグは上書きされず、両方の値が渡る（累積する）。`--append-system-prompt` とその -file 版も、上書きではなく両方が使われる（v2.1.283 以降）。
- これは既定値をチームで揃える仕組みであって、強制力は無い。起動時引数はさらに後ろに付くので、値を 1 つだけ取るフラグは利用者が起動時引数で明示指定すれば上書きできる。強制したい統制は settings.json / managed settings 側で行う。
- 並び順: bash 版は各配列をキーの辞書順（C ロケール）で並べる（書いた順ではない）。PowerShell 版は書いた順。
- プロンプトを起動時引数で渡すなら、フラグはすべてプロンプトより前に置く。値を複数取るフラグ（`--add-dir` / `--mcp-config` / `--tools` 等）や値を省略できるフラグ（`--debug` / `--resume` 等）は、直後のプロンプトを値として取り込む。ランチャーは起動時引数が全部 `-` で始まらない（＝プロンプトだけ）ときに限り、組み立てたオプションとの間に `--` を補う。

### 3-2. 複数の値を渡すフラグ

option-settings は bash 版が連想配列、PowerShell 版が順序付きハッシュで、**同じキーを 2 回書けない**。そのため `--add-dir` / `--plugin-dir` / `--mcp-config` 等の繰り返して指定するフラグは、ここには 1 値しか書けない。2 個目以降は起動時引数で渡す。

```bash
./start_claude_code.sh --add-dir <パスA> --add-dir <パスB>
```

```powershell
.\start_claude_code.ps1 --add-dir <パスA> --add-dir <パスB>
```

1 つの値で複数を渡せるもの・代わりの手段:

- `--plugin-dir` は、プラグインを並べたフォルダを 1 つ渡せば中の各プラグインを読む（v2.1.265 以降）。
- `--plugin-url` は、空白区切りの複数 URL を 1 値で渡せる。
- 複数の plugin ディレクトリは、環境変数 `CLAUDE_CODE_PLUGIN_DIRS`（custom.env に書ける。Windows は `;` 区切り・絶対パス必須・v2.1.280 以降）でも渡せる。

同じキーを 2 回書いたときの挙動は bash 版と PowerShell 版で割れる。bash 版は後に書いた値が黙って採用され、PowerShell 版は構文エラーで起動しない（付録 B「bypassPermissions を隔離している理由」）。

### 3-3. ランチャーの実行例

起動時引数は、option-settings と custom.env を反映したうえで、組み立てたオプションの後ろにそのまま付けて `claude` へ渡される（§3-1）。毎回同じ値は custom.env か option-settings に書き、起動ごとに変える値を引数で渡す。

```bash
./start_claude_code.sh                                 # option-settings と custom.env だけで起動する
./start_claude_code.sh --continue                      # 直前のセッションを再開する
./start_claude_code.sh --resume                        # セッションを選んで再開する（--resume <ID か名前> で直接指定）
./start_claude_code.sh --permission-mode plan          # 計画モードで開始する
./start_claude_code.sh --model 'opus[1m]' --effort max # この回だけモデルと effort を変える（/model・/effort は使えるまま）
./start_claude_code.sh --worktree <名前>               # 隔離した worktree で作業する
./start_claude_code.sh --add-dir <パス>                # option-settings の --add-dir に加えて 2 つ目を渡す
./start_claude_code.sh -p --output-format json "<プロンプト>"   # 非対話で実行する（stdout は claude の出力だけ）
./start_claude_code.sh --debug-file <パス>             # 起動時の警告を一度だけ読む（付録 B）
```

```powershell
.\start_claude_code.ps1                                # option-settings と custom.env だけで起動する
.\start_claude_code.ps1 --continue                     # 直前のセッションを再開する
.\start_claude_code.ps1 --resume                       # セッションを選んで再開する（--resume <ID か名前> で直接指定）
.\start_claude_code.ps1 --permission-mode plan         # 計画モードで開始する
.\start_claude_code.ps1 --model 'opus[1m]' --effort max # この回だけモデルと effort を変える（/model・/effort は使えるまま）
.\start_claude_code.ps1 --worktree <名前>              # 隔離した worktree で作業する
.\start_claude_code.ps1 --add-dir <パス>               # option-settings の --add-dir に加えて 2 つ目を渡す
.\start_claude_code.ps1 -p --output-format json "<プロンプト>"   # 非対話で実行する（stdout は claude の出力だけ）
.\start_claude_code.ps1 --debug-file <パス>            # 起動時の警告を一度だけ読む（付録 B）
```

- プロンプトを起動時引数で渡すなら、フラグはすべてプロンプトより前に置く。起動時引数がプロンプトだけのときは、ランチャーが組み立てたオプションとの間に `--` を補う（§3-1）。
- `--effort` と `--autocompact` は、環境変数 `CLAUDE_CODE_EFFORT_LEVEL` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` が custom.env などで設定されていると、そちらが優先されて効かない（§4）。

## 4. 起動オプションと環境変数で重なる設定

起動オプションと環境変数の両方で指定できる設定は、原則として option-settings か起動時引数で指定し、環境変数（custom.env）は毎回同じ値に固定したいときだけ使う。とくに `--effort` と `--autocompact` は、環境変数（`CLAUDE_CODE_EFFORT_LEVEL` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW`）を設定するとそちらが優先され、`/effort` / `/autocompact` でも変えられなくなるため、起動ごとに変えたいなら custom.env には書かず、option-settings か起動時引数で指定する。`--model` も同様で、`ANTHROPIC_MODEL` は起動のたびにモデルを強制し、`/model` で保存した選択より優先される。

テンプレートのコメントに記した関係をまとめる。

| 起動オプション（option-settings） | 環境変数（custom.env） | 関係 |
|---|---|---|
| `--model` | `ANTHROPIC_MODEL`・`ANTHROPIC_DEFAULT_MODEL` | 役割が重なる。原則 option-settings 側で指定し、環境変数での上書きが必要なときだけ使う。`--model` を指定しないときの決まり方は付録 B |
| `--effort` | `CLAUDE_CODE_EFFORT_LEVEL` | 環境変数が設定されていると、そちらが優先されフラグは効かない（§2-4） |
| `--autocompact` | `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | 環境変数が優先（使えない値のときだけ無視され、フラグが効く）。数値の書き方が違う（§2-4） |
| `--debug-file` | `CLAUDE_CODE_DEBUG_LOGS_DIR` | `--debug-file` が優先 |
| `--plugin-dir` | `CLAUDE_CODE_PLUGIN_DIRS` | 複数の plugin ディレクトリを渡す代わりの手段（§3-2） |

## 5. background セッションに届く値

- custom.env と `setup-environment` の値が確実に届くのは、ランチャーが起動した foreground の `claude` だけ。background セッション（`/bg`・`claude --bg`・agent view）には届かないことがある。
- background にも効かせたい値は、OS の環境変数（永続的なユーザー環境変数。Windows はユーザー環境変数、macOS / Linux はログインシェルの profile）で設定する。
- 起動オプションのうち background へ引き継がれるのは、構成フラグ（`--settings` / `--setting-sources` / `--add-dir` / `--plugin-dir` / `--mcp-config` / `--strict-mcp-config` / `--fallback-model` / `--allow-dangerously-skip-permissions`）だけ。
- 詳細はリポジトリのルートにある `start_claude_code.{sh,ps1}` の冒頭の注記を参照。

## 付録 A. 収録範囲と、意図的に載せていないオプション

テンプレートは、対話起動で使う Claude Code の起動オプションをほぼ全量載せ、公式の既定値を記している（公式 docs v2.1.310 時点）。次のものは意図的に載せていない。

| オプション | 載せない理由 |
|---|---|
| `--system-prompt` / `--system-prompt-file` | 既定のシステムプロンプトを丸ごと置き換える。キットの前提（CLAUDE.md / rules のロード）が崩れる |
| `--allowedTools` / `--disallowedTools` | 権限統制に直結するため settings.json 側で管理する |
| `--restricted` | user・project・local の settings を読まずに起動する（キットの permissions.deny も hooks も効かない）。キットの前提が崩れる |
| `--bare` / `--safe-mode` | settings は読むが hooks・CLAUDE.md・skills を読まない（.bat 保護の hook が効かない）。キットの前提が崩れる |
| `--desktop` / `--environment` / `--ref` | 端末セッションを始めずに Desktop を開く、またはクラウドセッションを作って終了する。他の起動オプションと併用できない（ランチャーの用途外） |
| `--post` / `--no-post` / `--trust-workspace`（`claude ultrareview`）、`--discard-unpushed` / `--force-remove-worktree`（`claude rm`） | サブコマンド専用のオプション |

全オプションの説明は公式 docs の CLI reference（https://code.claude.com/docs/en/cli-reference）を参照。

ランチャーは option-settings と `TEAM_OPTS`（PowerShell 版は `$TeamOpts`）のキーを検査せず、書かれたキーをすべてそのまま `claude` へ渡す。そのため、テンプレートに載せていないオプション（上の表のものを含む）も書けば効き、キットの前提が崩れるものでもランチャーは警告しない。キーの綴りを誤ると `claude` 自身がエラーにする。チームとして禁じたいオプションがあるなら、managed settings で固定する（ランチャーの統制には強制力が無い。§3-1）。

## 付録 B. option-settings の項目ごとの補足

### --model の既定とエイリアス

- 起動時の対話選択は無い。`--model` を指定しないときは、次の順に最初に見つかったものが使われる: 環境変数 `ANTHROPIC_MODEL` → settings の `model`（`/model` の保存先）→ 組織の既定モデル → 環境変数 `ANTHROPIC_DEFAULT_MODEL` → アカウント種別の既定（Pro / Max / Team / Enterprise / API・Bedrock・Agent Platform は Opus 5.5、Foundry は Sonnet 4.5）。
- エイリアス（`opus` / `sonnet` / `haiku` 等）の指す先は版とプロバイダで変わる（Bedrock 等では `sonnet` / `haiku` が旧版）。版を固定するならフルモデル名を書く。

### --add-dir とネットワークパス

- UNC（`\\server\share`）などのネットワークパスは拒否される（v2.1.257 以降）。Windows では、共有フォルダをネットワークドライブとしてドライブ文字に割り当て、そのドライブ文字から始まるパスを書く。
- 起動時に渡したネットワークパスは、Claude Code がそのディレクトリを外して起動する。v2.1.305 以降の対話起動では、その警告がデバッグログにしか出ない（読み方は下の「起動時の警告を読む」）。
- option-settings（とチーム統制の `TEAM_OPTS`）の `--add-dir` の値が `\\` か `//` で始まると、ランチャーが起動前に stderr へ警告する（起動は止めない）。起動時引数の `--add-dir` は検査しない。
- 追加したディレクトリの `.claude/skills/` も読み込まれる。既存の skill と同名のものは `/<フォルダ名>:<skill 名>` で呼ぶ（v2.1.309 以降。それ以前は呼べなかった）。

### --setting-sources の影響範囲

- `project` を外すと、キットの `.claude/settings.json`（permissions.deny・hooks。.bat 保護を含む）が読まれない。
- `--add-dir` で足したディレクトリの skill・コマンド・サブエージェントも読まれなくなる。
- この値は、このセッションから起動するチームメイト・`/bg`・`claude agents` のセッションにも引き継がれる。

### --permission-mode の既定

- 未指定時、対話起動は `auto`（v2.1.283 以降。ネイティブ Windows は v2.1.233 未満だと Manual）。auto が使えない場合（モデル非対応・設定で無効化など）は Manual で起動する。
- `-p` 実行は `default`（v2.1.302 以降。それ以前はサードパーティプロバイダやテレメトリ無効の環境で auto になりえた）。`-p` の Manual では、確認が要る操作は allow ルール・hook・`--permission-prompt-tool` で承認しない限り拒否される。
- `default` を指定すると、auto をやめて従来の Manual（操作ごとに確認）で起動する。
- `dontAsk` は確認が要る操作をすべて自動で拒否する（CI 向け。インストールした mod は一部を承認しうる）。
- ここで固定すると、`--continue` / `--resume` で再開したときに終了時のモード（plan 等）が復元されず、この値になる。
- `bypassPermissions` はここに書かない（下の「bypassPermissions を隔離している理由」）。

### --tools と MCP ツールの読み込み

- `--tools` はビルトインツールだけを限定し、MCP ツールには効かない。
- 列挙に `ToolSearch` を含めないと、MCP ツールは遅延読み込みされず、最初から全部読み込まれる。

### --worktree の開き直しと終了時の削除

- 既存の worktree 名を指定すると開き直す。既定では、未コミットの変更が無く作成時のブランチのままで、独自のコミットが無い（または PR がマージ済みで remote ブランチが消えている）ときは、既定ブランチの最新から開き直す。
- 終了時、変更も新しいコミットも無い worktree は、名前（`--name` / `/rename`）を付けていないセッションなら確認なしでブランチごと削除される。作業が残っている・別ブランチに切り替えてあるときは確認が出る。
- v2.1.304 未満は、別ブランチや detached HEAD のときも確認なしで消し、コミットを失うことがあった。

### エージェントチーム（--teammate-mode）

- エージェントチームは実験的機能で、環境変数 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` が無いとチーム自体が作られない。
- `tmux` / `iterm2` は分割ペイン表示。分割ペインのチームメイトは、起動時引数の `--tools` / `--disallowedTools` を引き継ぐ（v2.1.309 以降）が、`--allowedTools` は引き継がない。

### 起動時の警告を読む（--debug-file）

- v2.1.305 以降、対話起動での Claude Code の起動時警告（`--add-dir` のネットワークパスを外した警告を含む）は画面に出ず、デバッグログにしか出ない。一部の権限ルールの警告だけはバナーの下の行に出る。
- 読むには `--debug-file` を付けて起動し、そのファイルを開く。`--debug` だけなら `~/.claude/debug/<セッション ID>.txt` に書かれる。
- `--debug-file` はデバッグモードも有効にし、環境変数 `CLAUDE_CODE_DEBUG_LOGS_DIR` より優先される。
- 作業ツリーの中を指定すると誤ってコミットしうるので、リポジトリの外のパスにする。

### bypassPermissions を隔離している理由

- `--dangerously-skip-permissions` は `--permission-mode bypassPermissions` と同等。同じ効果を「権限」節の `--permission-mode` に書くとキーが重複し、bash 版は後に書いた値が黙って採用され、PowerShell 版は構文エラーで起動しない。そのため「非推奨・破壊的」節に分けて置き、`--permission-mode` には書かない。
- `--allow-dangerously-skip-permissions` は bypassPermissions を Shift+Tab の切り替え候補に加える。これを付けた対話セッションでは plan モードでも編集・コマンドが確認なしで実行されうるため、`--dangerously-skip-permissions` と同じ扱いにする。

## 付録 C. Windows PowerShell 5.1 の注意

- Windows PowerShell 5.1 は、ネイティブ exe（claude.exe）へ渡す引数の中の `"` をすべて落とす（実測）。`--agents` のインライン JSON は `{reviewer:{description:Reviews code,...}}` のように壊れるため、5.1 では使えない。pwsh 7 で起動する（7.3 以降は `"` が保たれる）。
- 5.1 で値の `"` を `\"` にエスケープしても、値に空白があると引数が空白で分割されて直らない。
- `option-settings.ps1` は UTF-8（BOM 付き）・CRLF のまま保存する。BOM が無いと 5.1 が日本語を読み違える。
