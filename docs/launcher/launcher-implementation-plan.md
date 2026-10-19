# ランチャースクリプト実装計画（A タスク・実装前プレップ）

> **【正本・IM-8】本書は設計書の正本**（実装と同一 PR で共進化する側）。
> research-by-cc 側の同名文書（`reports/04.資産インベントリ・統合/04.ランチャースクリプト実装/`）は
> 2026-07-05 時点の**スナップショット**であり、以後更新しない。差分が出たら本書が正。
> 根拠: Fable クロスレビュー統合 IM-8（2 リポ二重管理によるドリフトを実検出）。

> `launcher-scripts-design.md`（確定設計・6ファイル構成）を実装に落とすための作業計画。
> 本書は休憩中の事前準備として作成。**コード生成は復帰後**。未確定点は §6 に集約。

## 1. ファイル構成（design §1 再掲）と配布・開発の対応

| # | ファイル | 配置 | Git 追跡 | 配布先（層1） | 開発元 |
|---|---|---|---|---|---|
| 1 | `start_claude_code.{sh,ps1}` | repo ルート | yes | **C-BCP**（`<Share>` 雛型ルート） | C-BDK |
| 2 | `.claude/launcher/setup-environment.{sh,ps1}` | `.claude/launcher/` | yes | **C-BDC**（`.claude` body） | C-BDK |
| 3 | `.claude/launcher/option-settings.{sh,ps1}.template` | 同上 | yes | C-BDC | C-BDK |
| 4 | `.claude/launcher/custom.env.template` | 同上 | yes | C-BDC | C-BDK |
| 5 | `.claude/option-settings.{sh,ps1}` | `.claude/` | **no**（利用者がコピー作成） | — | — |
| 6 | `.claude/custom.env` | `.claude/` | **no**（利用者がコピー作成） | — | — |

- 開発は **C-BDK（`<Dev>`）に一元集約**。ただし**配布レールは 2 本に分かれる**:
  - **payload レール**: `publish-share` は `.claude/` 配下だけを archive するため、`.claude/launcher/*` と `.claude/.gitignore` / `.claude/.gitattributes` が C-BDC へ乗る。
  - **ルート直コミットレール**: `start_claude_code.{sh,ps1}` は `.claude/` の外にあり **payload に乗らない**。C-BCP ルートへ直接コミットして配る（ルート用 `.gitattributes` も同様）。
- (5)(6) は **.gitignore 必須**。除外は配布先でも効く必要があるため、`.claude/.gitignore` に置いて payload で搬送する（C-BDK ルート `.gitignore` は配布されない）。
- **`custom.env` は機微情報の格納先ではない**（分類D＝統制不要・非機微の env 専用）。分類A（API キー / 認証トークン / パスワード / 組織外秘 URL）は **custom.env を含むいかなるランチャーファイルにも書かず**、OS の環境変数として設定する。`setup-environment` は分類A の既知キーを検出したら**読み込まずに警告**する。
  - この方針は §6-bis で確定したもの。秘匿を置かない以上、`permissions.deny` への追加も不要。

## 2. ロード関係（design §2 再掲）

```
start_claude_code ─┬─→ setup-environment ─→ custom.env（(4)からコピー）
                   └─→ option-settings（(3)からコピー）
```
- `option-settings`(5) をロードするのは **start_claude_code**(1)（起動コマンド組立用）。
- `setup-environment`(2) は env 専任で **custom.env**(6) のみロード＋チーム固定 env を後勝ち上書き。

## 3. 各ファイルの実装方針

### (1) start_claude_code.{sh,ps1}
- setup-environment を source/dot-source → option-settings を source → 連想配列の起動オプションから `claude` コマンドを組み立て → 起動。
- **env のローカルスコープ性**: ランチャープロセス内で設定した env は、子プロセスとして起動する `claude` にのみ継承され、OS env や他アプリに影響しない（bash の export / PS の `$env:` とも本質的にプロセスローカル）。⚠ **確実に届くのは foreground 起動の `claude` だけ**。background セッション（`/bg`・`←`・`claude --bg`・agent view からの dispatch）は supervisor 配下で新しいプロセスとして起動し直され、**ディレクトリの settings（`env` ブロック含む）＋引き継がれた構成フラグ**から構成を読む。dispatch 元シェルから届く env は `PATH`・プロバイダ選択（`CLAUDE_CODE_USE_BEDROCK` / `CLAUDE_CODE_USE_VERTEX`）・`ANTHROPIC_DEFAULT_*_MODEL`・`CLAUDE_CODE_EXTRA_BODY`（＋条件付きでゲートウェイ変数）に限られ、supervisor 自体は「最初に起動したシェル」の env を継承する（起動順次第で届くことはあるが確実ではない）。**custom.env / setup-environment の値は、この列挙に入るもの（プロバイダ選択等）を除いて確実には届かない**（公式: https://code.claude.com/docs/en/agent-view#settings-and-provider ）。
  - 帰結: `--add-dir <Share>` は background に引き継がれるが `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` は引き継がれないため、**background セッションでは `<Share>` の CLAUDE.md / rules がロードされないことがある**。必要なら **OS の環境変数**（永続的なユーザー環境変数）として設定する（supervisor は最初に起動したシェルの env を継承するので、どの端末から起動されても届く。既に動いている service には、それが起動した時点の env が使われる）。公式 memory は `~/.claude/settings.json` の `env` を勧めるが、キットは design §3(6) の方針によりこの経路を使わない（組織で固定する値だけ managed settings の `env`）。
  - background service ごと起動装置に通す公式経路 `CLAUDE_CODE_PROCESS_WRAPPER` は **Windows では無視される**ため本キットの解にならない（design §5-1）。
  - 冒頭コメント（`start_claude_code.*`）にも同旨とサブコマンド委譲の注意（design §5-2）を明記。経路別の到達表は design §5。

### (2) setup-environment.{sh,ps1}
- custom.env をロード（KEY=VALUE 形式を export / `$env:` 設定）。
- その後で**チーム固定 env を後勝ちで上書き**（利用者が custom.env に書いても固定値を保証）。固定対象は §6-2 で確定。
- 秘匿値はハードコードしない（固定 env は非秘匿のものだけ）。**機微（分類A）は custom.env にも書かない** ―― OS の環境変数で供給する（§6-bis の判定木で確定）。`setup-environment` は分類A の既知キーを custom.env 内に見つけたら**読み込まずに警告**する。2026-10-18 以降は既知キーの完全一致に加え、資格情報らしい名前（`*_API_KEY` / `*_TOKEN` / `*_ACCESS_KEY` / `*_PRIVATE_KEY` / `*_SECRET` / `*_SECRET_*` / `*_PASSWORD` / `*_PASSPHRASE` の接尾辞、`OTEL_EXPORTER_OTLP*_HEADERS`。2026-10-19 以降は同じ語の名前全体（`API_KEY` / `TOKEN` / `SECRET` 等そのもの）と `SECRET_*`、略記の `*_PASS` / `*_PASSWD` / `*_PWD`、`://` を含まない接続文字列（Azure の `AccountKey=…` 等）の `*_CONNECTION_STRING` も。`PWD` 単独はシェルのカレントディレクトリなので対象外、`*_KEY` や `*SECRET*` のような広い形も加えない）と認証情報入り URL（値のどこかに `://<userinfo>@` を含むもの。`https://token@host` のようなコロン無し・引用符付き・`jdbc:postgresql://u:p@h` も対象。パスやクエリ内の `@` は対象外。2026-10-19 以降は `//` の抜けた形も対象: special scheme（`http` / `https` / `ws` / `wss` / `ftp`。大文字小文字を区別しない）の直後の `:` に `/` か `\` が 0 個以上と userinfo（`/` `\` `@` `?` `#` 空白を含まない 1 文字以上。両版とも空白は ASCII のスペースとタブだけで、U+3000 や NBSP は userinfo の一部とみなす ―― bash の `[:space:]` はロケール次第、.NET の `\s` は常にそれらに一致して判定が割れたため。`://` の形も同じ）・`@` が続くもの（`http:u:p@h`・`HTTPS:\u:p@h`・`ws:token@h`）。WHATWG URL 規格がこれらのスキームで `//` の欠落と `\` を補うため、claude 2.1.303 で `HTTPS_PROXY=http:u:p@host:port` が認証付きプロキシとして使われる（`Proxy-Authorization` が送られる）ことを実測した。スキームの前は値の先頭か英数字と `+` `.` `-` 以外の文字に限り（`xhttp:u@h` は対象外）、補われないスキーム（`mailto:user@example.com`・`socks5:u@h`）と userinfo を持たない `file` も対象外。両版とも大文字小文字は文字クラスで書き分け、PS 版は `-cmatch` で比べる）も対象とし、名前は大文字小文字を区別せず比較する（Windows の環境変数名は大文字小文字を区別しないため。bash / PowerShell 両版で同じ判定）。`*_TOKEN` は `MAX_THINKING_TOKENS` 等の `*_TOKENS` には一致しない。`*_CREDENTIALS` は対象にしない（`GOOGLE_APPLICATION_CREDENTIALS` は鍵ファイルのパスで、custom.env に書く正当な用途がある）。既知キーには 2026-10-19 に `ANTHROPIC_CUSTOM_HEADERS`（`Authorization: Bearer …` を運ぶことが多い）を加えた。タグ付けだけの無害なヘッダでも止まるため、その場合は OS の環境変数に置く（調査レポート B-07 は「名前一致で塞ぐのは過剰」として見送っていたが、値検査（URL の userinfo）では `Authorization` ヘッダを拾えないため名前で塞ぐ側に倒した）。
- custom.env の行のうち、**ランチャーの内部変数名**（`IFS` / `_SENSITIVE_KEYS` / `_CUSTOM_ENV` / `_LAUNCHER_DIR` / `_line` / `_key` / `_val` / `_ukey` / `_skip` / `_s` / `_first` / `_url_re` と、`start_claude_code.sh` の `_ROOT_DIR` / `_SETUP_ENV`、シェルの読み取り専用変数 `BASHOPTS` / `BASH_VERSINFO` / `EUID` / `PPID` / `SHELLOPTS` / `UID`）に一致するものは警告して読み飛ばす（2026-10-19。読み取り専用変数は同日追加: bash 版で `export` が失敗し、`set -e` の下でランチャーの起動ごと止まるため。一覧は非対話の bash の `readonly -p` / `declare -r` から取った。bash 版は一覧に無い読み取り専用変数でも止まらないよう、`export` の間だけ errexit を外して失敗を警告にする（`set -e` の下では `if` や `||` の中でも `export` の失敗がシェルを終了させるため。bash 固有の安全網で PS 版には無い））。bash 版は `export` でシェル変数そのものを書き換えるため、`_SENSITIVE_KEYS=x` や `IFS=,` の行があると以後の行で既知キーの完全一致判定が外れ（`AWS_ACCESS_KEY_ID` のように接尾辞で拾えないキーが通る）、`IFS` はランチャー本体の単語分割、`_ROOT_DIR` は source する `option-settings.sh` の場所まで変える。PowerShell 版（`Set-Item Env:`）は影響を受けないが、同じ custom.env が OS で違う結果にならないよう同じ名前集合・同じ警告で読み飛ばす。比較は大文字小文字を区別する（bash の変数名は区別する）。`_` で始まる名前を一律には拒否しない（`_JAVA_OPTIONS` 等の正当な用途がある）。
- 「後勝ち固定」が効くのはランチャー内（custom.env に対して）だけ。settings.json（user / project / local）の `env` に同じ変数があるとそちらが勝つ（`/setup-bedrock`・`/setup-vertex` も user settings の `env` へ書き込む）。利用者側で覆せない固定が必要なら managed settings の `env` へ移す。

### (3) option-settings.{sh,ps1}.template
- 連想配列（bash: `declare -A OPTS=( [--model]=... )` / PS: `$Opts = @{ '--model' = ... }`）で起動オプションを列挙。不要行はコメントアウトで無効化。
- 公式デフォルト推奨値はコメントで明示。CLI フラグ候補は §4。

### (4) custom.env.template
- `KEY=VALUE` 列挙＋コメント。利用者が値設定する env の全量（curated）。候補は §5。
- 公式推奨デフォルトを持つものは設定済み＆有効化。

## 4. CLI 起動オプション インベントリ（option-settings.template 候補・docs 2026-10-18 / v2.1.302 時点）

**ランチャーで露出する有力候補（curated）**:
`--model` / `--fallback-model` / `--add-dir` / `--settings` / `--setting-sources` / `--mcp-config` / `--strict-mcp-config` / `--permission-mode` / `--agents` / `--agent` / `--append-system-prompt-file` / `--effort` / `--autocompact` / `--worktree` / `--debug` / `--ide` / `--verbose`

> `--permission-mode` の注記（2026-10-18）: 組み込み既定は **auto**（対話起動。v2.1.283〜全プラン・全プロバイダ。ネイティブ Windows は v2.1.233〜）。`-p` は changelog 2.1.302 で `default` に戻った。project の `.claude/settings.json` の `permissions.defaultMode` に `auto` / `bypassPermissions` を書いても効かない（`default` / `plan` / `acceptEdits` 等は効く）。チームで Manual を既定に揃えたいなら TEAM_OPTS の `--permission-mode default` か project settings の `"defaultMode": "default"`、強制したいなら managed settings の `disableAutoMode`。`restricted` は `--permission-mode` の値ではなく独立フラグ `--restricted`。

**全フラグ（参考・cli-reference の CLI flags 表より。別名は省略）**:
`--add-dir --advisor --agent --agents --allow-dangerously-skip-permissions --allowedTools --append-subagent-system-prompt(-file) --append-system-prompt(-file) --autocompact --ax-screen-reader --bare --betas --bg --channels --chrome --cloud --continue --dangerously-load-development-channels --dangerously-skip-permissions --debug --desktop --disable-slash-commands --disallowedTools --effort --environment --exclude-dynamic-system-prompt-sections --exec --fallback-model --fork-session --forward-subagent-text --from-pr --ide --include-hook-events --include-partial-messages --init --init-only --input-format --json-schema --maintenance --max-budget-usd --max-turns --mcp-config --model --name --no-chrome --no-session-persistence --output-format --permission-mode --permission-prompt-tool --permission-prompts --plugin-dir --plugin-url --print --prompt-suggestions --ref --remote-control --remote-control-session-name-prefix --replay-user-messages --restricted --resume --safe-mode --session-id --setting-sources --settings --strict-mcp-config --system-prompt(-file) --system-prompt-snapshot --teammate-mode --teleport --tmux --tools --verbose --version --worktree`
（`--remote` は `--cloud` の非推奨の別名、`--enable-auto-mode` は v2.1.111 で削除。`--sso` はトップレベルのフラグではなく `claude auth login` のオプション。`--post` / `--no-post`〔ultrareview〕と `--discard-unpushed` / `--force-remove-worktree`〔rm〕はサブコマンドのオプション。`--dangerously-*` 系は既定で露出しない方針を推奨）

**2026-10-18 追補（v2.1.214→v2.1.302）**: base にあって head で消えたフラグは 0。head で増えたトップレベルのフラグは `--append-subagent-system-prompt-file --autocompact --desktop --environment --permission-prompts --ref --restricted --system-prompt-snapshot`。テンプレには `--autocompact` / `--system-prompt-snapshot`（対話向け）と `--permission-prompts` / `--append-subagent-system-prompt-file`（print 節）を追加し、`--restricted` / `--bare` / `--safe-mode` / `--desktop` / `--environment` / `--ref` は「意図的に載せていないもの」へ回した。
- `--restricted` は managed settings と `--settings` しか読まないため、**キットの `.claude/settings.json`（`.bat` の deny・hooks）が載らない**。露出するなら「`--settings <Share>/.claude/settings.json` と併用」を注記する。
- `--bg` 系の background 起動では、引き継がれるのは構成フラグだけ（design §5）。
- `--debug` のカテゴリ絞り込みは `=` 形でしか効かないため、テンプレではキー側に `--debug=mcp,startup` と書く方式を採った（組立ロジックは不変）。
- `--max-budget-usd` / `--max-turns` / `--include-partial-messages` / `--permission-prompt-tool` は print 専用（base 時点からの不整合）。テンプレでは print 節へ移した。

## 5. 環境変数 インベントリ（custom.env.template / 固定 env 候補・docs env-vars より）

> **⚠ 本節の分類は §6-bis の判定木で置き換わっている**。下記の「多くは秘匿＝custom.env」という
> 初期案は**撤回済み**。機微（分類A）は custom.env に書かず OS 環境変数で供給する。
> 以下はインベントリ（どんな env があるか）としてのみ読むこと。

カテゴリ分類（フル一覧は docs `ja/env-vars.md`。ここでは launcher 関連を抜粋）:

- **プロバイダ/認証（大半が分類A＝機微。custom.env ではなく OS 環境変数で供給）**: `ANTHROPIC_API_KEY` `ANTHROPIC_AUTH_TOKEN` `ANTHROPIC_BASE_URL` `ANTHROPIC_MODEL` `ANTHROPIC_SMALL_FAST_MODEL`（DEPRECATED・後継は `ANTHROPIC_DEFAULT_HAIKU_MODEL`）/ Bedrock: `CLAUDE_CODE_USE_BEDROCK` `AWS_BEARER_TOKEN_BEDROCK` `ANTHROPIC_BEDROCK_BASE_URL` / Vertex: `CLAUDE_CODE_USE_VERTEX` `ANTHROPIC_VERTEX_PROJECT_ID` `CLAUDE_CODE_SKIP_VERTEX_AUTH` / OAuth(SSO・**今回不使用**): `CLAUDE_CODE_OAUTH_TOKEN` `CLAUDE_CODE_OAUTH_REFRESH_TOKEN`
  - ※ bearer ゲートウェイトークンには専用 helper が無い（[[reference_cc_credential_handling_mechanisms]] の gap）。**だからといって custom.env に置いてよいわけではない**（当初はそう書いていたが §6-bis で撤回）。helper が無い以上、供給手段は **OS の環境変数**となる。`setup-environment` は `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `AWS_BEARER_TOKEN_BEDROCK` 等を custom.env 内に見つけたら、**読み込まずに警告**する（規律を機構で担保）。[[user_env_secret_handling_stance]] と整合。
  - ※ プロバイダ選択（Bedrock / Claude Platform on AWS / Vertex / Foundry）を有効化すると **Advisor / Fast mode / Channels / Server-managed settings / Analytics が使えなくなる**（公式 docs「Feature availability」。2026-10-18 再確認で head も同じ。加えて 3P では Web search が Bedrock ✗・Agent Platform は条件付き、Auto mode は対応モデル限定、cross-session messaging は同一マシン内に限る）。server-managed settings は 1P でも、Team/Enterprise・api.anthropic.com 直結・OAuth ログイン／`CLAUDE_CODE_OAUTH_TOKEN`／直接設定の API キーの場合にしか届かない（apiKeyHelper・WIF・非既定の `ANTHROPIC_BASE_URL` では届かず、Console の API キーは Console 組織の設定を取りに行く）。分類B の出口は原則 endpoint-managed（MDM / ファイル配布の managed-settings.json。Windows は `C:\Program Files\ClaudeCode\managed-settings.json` または `HKLM\SOFTWARE\Policies\ClaudeCode` の `Settings` 値）。3P は Claude apps gateway が server-managed 相当。managed の `env` は管理ソース間で変数単位にマージされる（v2.1.223+）。プロバイダの統制は `allowedProviders`（v2.1.285+）で行える。
- **挙動・チーム統制候補（固定 env になりうる＝非秘匿）**: `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`（キットが依存）/ `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`（自前 git skill 採用時）/ `MAX_THINKING_TOKENS`（現行モデルでは正の値が無視される。effort は `CLAUDE_CODE_EFFORT_LEVEL`）/ `CLAUDE_CODE_SUBAGENT_MODEL`（v2.1.251 以降は既定値扱い。強制は `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`）/ `BASH_DEFAULT_TIMEOUT_MS` `BASH_MAX_TIMEOUT_MS` / `MCP_TIMEOUT` `MCP_TOOL_TIMEOUT`
- **プロキシ/テレメトリ（環境依存・任意）**: `HTTP_PROXY` `HTTPS_PROXY` `NO_PROXY` / `CLAUDE_CODE_ENABLE_TELEMETRY` `OTEL_*` / `DISABLE_TELEMETRY` `DISABLE_ERROR_REPORTING`
- **2026-10-18 追補（v2.1.214→v2.1.302 で増えた・意味が変わったもの）**: `ANTHROPIC_DEFAULT_MODEL`（D・v2.1.236〜。`/model` の保存選択に譲る既定）/ `CLAUDE_CODE_EFFORT_LEVEL`（D。`--effort` / `/effort` より優先）/ `CLAUDE_CODE_FORK_SUBAGENT`（D・fork mode は v2.1.232〜対話セッションで既定オン）/ `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`・`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`（D）/ `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS`・`CLAUDE_CODE_PROMPT_CACHE_TTL`（D・コスト影響）/ `API_TIMEOUT_MS`（D）/ `CLAUDE_CODE_USE_POWERSHELL_TOOL`・`CLAUDE_CODE_GIT_BASH_PATH`・`CLAUDE_CODE_BS_AS_CTRL_BACKSPACE`（Windows・D）/ `CLAUDE_CODE_USE_FOUNDRY`・`ANTHROPIC_FOUNDRY_RESOURCE`・`CLAUDE_CODE_USE_ANTHROPIC_AWS`・`ANTHROPIC_AWS_WORKSPACE_ID`・`AWS_REGION`・`CLOUD_ML_REGION`・`ANTHROPIC_DEFAULT_*_MODEL`（3P の版固定）（B）/ `CLAUDE_CODE_RESTRICTED`（settings の `env` では無視される。キットの project settings が載らないため不採用）/ `CLAUDE_CODE_PROCESS_WRAPPER`（B・Windows では無視・user/managed settings のみ）/ `CLAUDE_CODE_PLUGIN_DIRS`（`--plugin-dir` 相当。ランチャーはフラグで渡せるため不採用）/ `CLAUDE_CODE_AUTO_MODE_MODEL`（changelog 2.1.302 のみ。docs 掲載後に再評価）。いずれもランチャーで設定すると foreground にしか確実には効かない（design §5）。env-vars ページから消えた `AWS_REGION` `GOOGLE_APPLICATION_CREDENTIALS` `GOOGLE_CLOUD_PROJECT` はプロバイダページへ移動（存続）、`CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT` は内部変数の文書化をやめたもの（キット未使用）。

## 6. 復帰後に確認したい未確定点（要・作業指示者判断）

1. **開発→配布の経路**: 開発は C-BDK 一元、publish-share で `.claude/launcher/*`→C-BDC・`start_claude_code.*`→C-BCP ルート、で合っているか（start_claude_code はルート配置のため publish 対象の指定が必要）。→ **§6-bis #1 の記述は誤りだったため訂正済み。正は §1 の「配布レールは 2 本」を参照**（publish-share は `.claude/` しか運ばない）。
2. **env のチーム固定 vs 利用者可変の線引き**: §5 の「固定 env 候補」のうち実際に setup-environment で後勝ち固定するものはどれか（例: `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` は固定で良いか）。~~秘匿系は全て custom.env でよいか。~~ → **§6-bis の判定木で確定（分類A の機微は custom.env にも書かず OS 環境変数で供給する）。本設問は撤回済み。**
3. **option-settings.template の露出範囲**: §4 の curated 候補でよいか（exhaustive にするか）。`--dangerously-*` は除外で良いか。
4. **`.ps1` の文字コード**: 利用者環境の Windows PowerShell 5.1 を想定するなら、日本語コメントを含む `.ps1` は **CP932/CRLF（win-file-encoding skill 適用）** か、**UTF-8 BOM/CRLF**（5.1/7 両対応）か。`.sh` は UTF-8/LF で確定。→ 編集時に win-file-encoding rule が `.ps1` で自動発火する。
5. **SSO 不使用の最終確認**: `--sso`/`CLAUDE_CODE_OAUTH_*` は露出せず、認証は custom.env のトークン供給に一本化、で確定か（design・CLAUDE.local.md は「SSO 不要」）。→ **後半（custom.env に一本化）は §6-bis で撤回済み。認証情報は OS の環境変数で供給する**。

## 6-bis. 確定事項・追加タスク（2026-07-05 復帰セッションで作業指示者判断を反映）

**確定した点**:
- #1 配布経路: **確定**（開発は C-BDK 一元）。ただし当初ここに「publish-share で `start_claude_code.*`→C-BCP ルート」と書いていたのは**誤り**。`publish-share` は `.claude/` 配下しか archive しないため、ルート直下の `start_claude_code.*` は payload に乗らない。正しくは**配布レールが 2 本**（§1 参照）:
  - payload レール（publish-share）: `.claude/launcher/*` ＋ `.claude/.gitignore` ＋ `.claude/.gitattributes` → C-BDC
  - ルート直コミットレール: `start_claude_code.{sh,ps1}` ＋ ルート用 `.gitattributes` → C-BCP
- #3 option-settings 露出範囲: **exhaustive（全フラグ）で確定**。ただし可読性懸念があるため → 下記【追加タスク C】でテンプレの書き方を設計する。
- #4 .ps1 文字コード: **UTF-8 BOM + CRLF** を採用。加えて **`.gitattributes` に `*.ps1 text eol=crlf` を追加**して Git 改行正規化リスクを封じる（BDK・配布先双方）。`.sh` は UTF-8/LF 確定。BOM が 5.1 日本語コメント文字化け回避の本質、CRLF は Windows ネイティブ編集親和のための付加。
- #5 SSO 不使用: **確定**（`--sso`/`CLAUDE_CODE_OAUTH_*` は露出しない）。ただし当初ここに書いた「認証は **custom.env** のトークン供給に一本化」は**誤りで撤回**する ―― 認証トークンは分類A（機微）であり、**custom.env を含むいかなるランチャーファイルにも書かない**。OS の環境変数で供給する（下記【追加タスク B】の判定木が正）。`setup-environment` は `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `AWS_BEARER_TOKEN_BEDROCK` 等を custom.env 内に見つけたら**読み込まずに警告**する（規律を機構で担保）。
- 本セッションの未コミット物（pre-compact skill / cc-docs agents 4件）: 現ブランチ主題外につき**一旦保留**（破壊的操作なし）。

**【追加タスク B】env・起動オプションの配置分類設計**（#2 を格上げ・作業指示者判定木を正とする）:

判定木（env・起動オプション共通。作業指示者確定・2026-07-05）:

| 分類 | 判定 | env の配置先 | 起動オプションの配置先 |
|---|---|---|---|
| **A** 機微情報か？ | Y | **どのファイルにも書かない**（OS 環境変数＝システム手順で設定） | （同左・該当稀） |
| **B** 組織単位で統制？ | Y | 原則どのファイルにも書かない（将来 managed スコープ統制）。**managed 開始まで暫定 C 扱い** | 同左（暫定 C） |
| **C** チーム単位で統制？ Y | Y | `setup-environment.{sh,ps1}`（ユーザ非カスタム） | `start_claude_code.{sh,ps1}`（ユーザ非カスタム） |
| **D** チーム統制不要 | N | `custom.env`（ユーザカスタム） | `option-settings.{sh,ps1}` 連想配列（ユーザカスタム） |

- 機微（分類A）= API キー/トークン/パスワード等の認証情報・組織外秘の環境情報。**ファイルに書かず OS env**。→ `custom.env` は機微の受け皿ではない（旧 §1/§5 の「custom.env が bearer 供給手段」を**撤回**）。
- 分類B は「暫定 C」として当面 `setup-environment` / `start_claude_code` に置くが、**将来 managed スコープへ移設予定**である旨をコメントで明記する。移設の動機は統制の強制力に加えて **background セッションへの到達**: ランチャーの env は background（`/bg`・`claude --bg`・agent view）に確実には届かないが、managed settings の `env` は届く（design §5）。3P（Bedrock / Vertex 等）では server-managed settings が使えず、1P でも取得条件が限られるため、出口は endpoint-managed（MDM 配布のローカル managed settings。Windows: `C:\Program Files\ClaudeCode\managed-settings.json` または `HKLM\SOFTWARE\Policies\ClaudeCode` の `Settings` 値）となる（§5 の注記も参照）。OTel の有効化・送信先系の env は project / local settings では無視される（v2.1.282+）ため、settings へ移すときも user か managed に置く。
- 起動オプションの拡張子: `option-settings` は**コメントアウト容易性から .sh/.ps1 連想配列形式で確定**（作業指示者選好）。

§5 env 再マップ:

| env | 分類 | 配置 | 備考 |
|---|---|---|---|
| `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `AWS_BEARER_TOKEN_BEDROCK` | **A** | OS env（不記述） | 機微。bearer は OS env で供給 |
| `ANTHROPIC_BASE_URL` / `ANTHROPIC_BEDROCK_BASE_URL` | A または B | 機微なら OS env / 非秘匿なら setup-environment（暫定） | 組織外秘の内部 GW URL なら A、非秘匿なら B |
| `CLAUDE_CODE_USE_BEDROCK` / `USE_VERTEX` / `CLAUDE_CODE_SKIP_VERTEX_AUTH` / `ANTHROPIC_VERTEX_PROJECT_ID` | **B** | setup-environment（暫定 C） | プロバイダ/組織インフラ選択。managed 候補 |
| `CLAUDE_CODE_ENABLE_TELEMETRY` / `OTEL_*` / `DISABLE_TELEMETRY` / `DISABLE_ERROR_REPORTING` | **B** | setup-environment（暫定 C） | データガバナンス・SIEM。managed 筆頭候補 |
| `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | **D**（既定）／必要時 B | 既定 custom.env、企業プロキシ前提チームは setup-environment | 作業指示者 Q1 確定＝既定可変・昇格可 |
| `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` | **C** | setup-environment（`=1`） | キット動作依存 |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` | **C**（条件付き） | setup-environment | 自前 git skill 採用時のみ |
| `ANTHROPIC_DEFAULT_MODEL` / `ANTHROPIC_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL` | **D** | custom.env（※ `--model` と重複＝原則 option-settings 側） | `ANTHROPIC_MODEL` は /model の保存選択より毎回優先。`ANTHROPIC_SMALL_FAST_MODEL` は DEPRECATED |
| `CLAUDE_CODE_SUBAGENT_MODEL`（v2.1.251 以降は既定値）/ `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` / `CLAUDE_CODE_EFFORT_LEVEL` | **D** | custom.env | 個人選好。`MAX_THINKING_TOKENS` は現行モデルで無効（旧モデル用） |
| `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` / `MCP_TIMEOUT` / `MCP_TOOL_TIMEOUT` / `API_TIMEOUT_MS` | **D** | custom.env | 環境依存 |
| `CLAUDE_CODE_OAUTH_TOKEN` / `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` / `ANTHROPIC_FOUNDRY_API_KEY` / `ANTHROPIC_FOUNDRY_AUTH_TOKEN` / `ANTHROPIC_AWS_API_KEY` / `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` / `MCP_CLIENT_SECRET` / `CLAUDE_CODE_CLIENT_KEY_PASSPHRASE` / `OTEL_EXPORTER_OTLP_*HEADERS` / `ANTHROPIC_CUSTOM_HEADERS` | **A** | OS env（不記述） | 2026-10-18 追補（`ANTHROPIC_CUSTOM_HEADERS` は 2026-10-19）。setup-environment の検知リストにも追加（名前の接尾辞・URL 埋め込み資格情報も検知） |
| `CLAUDE_CODE_USE_FOUNDRY` / `ANTHROPIC_FOUNDRY_RESOURCE` / `CLAUDE_CODE_USE_ANTHROPIC_AWS` / `ANTHROPIC_AWS_WORKSPACE_ID` / `AWS_REGION` / `CLOUD_ML_REGION` / `ANTHROPIC_DEFAULT_*_MODEL`（3P の版固定） | **B** | setup-environment（暫定 C） | managed では `allowedProviders`（v2.1.285+）でプロバイダ自体も制限できる |
| `ANTHROPIC_VERTEX_BASE_URL` / `ANTHROPIC_FOUNDRY_BASE_URL` / `ANTHROPIC_AWS_BASE_URL` ＋ 各 `CLAUDE_CODE_SKIP_*_AUTH` | A または B | 機微なら OS env / 非秘匿なら setup-environment（暫定） | `ANTHROPIC_BEDROCK_BASE_URL` 行と同じ扱い |
| `CLAUDE_CODE_GIT_BASH_PATH` / `CLAUDE_CODE_BS_AS_CTRL_BACKSPACE` / `CLAUDE_CODE_USE_POWERSHELL_TOOL` | **D** | custom.env | Windows 系は「Windows 環境」分節。`USE_POWERSHELL_TOOL` はチーム判断で C にしうる |
| `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS` / `CLAUDE_CODE_PROMPT_CACHE_TTL` / `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` / `CLAUDE_CODE_FORK_SUBAGENT` | **D** | custom.env | コストに影響するものはチームで揃えるなら setup-environment へ |

**設計上の帰結（実装時に反映）**:
1. `setup-environment` は分類B（暫定）＋C のみを後勝ち設定。機微は一切書かない。
2. `start_claude_code` はアセンブラに加え**チーム統制の起動オプション（C）を保持**する（design §2/§3 の役割を拡張）。ユーザ可変オプションは `option-settings`。
3. `custom.env` は非機微のみ＝**秘匿保護目的の `permissions.deny` 追加は不要**（habit 目的で足すかは任意判断・旧 §1/§7 の必須指定を緩和）。

**【追加タスク C】exhaustive option-settings.template の可読性設計**:
- 全フラグ露出方針の下で可読性を保つテンプレの書き方を設計する（カテゴリ分節・見出しコメント・既定でコメントアウト・公式デフォルト明記・`--dangerously-*` の隔離表現 等）。
- 成果物: テンプレ構造規約＋雛型スケルトン。

## 7. 実装ビルド順（確定後）

**実作業リポ**: `C:\cc-workspace\base-dev-kit-for-cc`（branch `chore/groom-as-share`）＝ C-BDK `<Dev>`。

1. C-BDK に `.claude/launcher/` を作成。`.sh` 群・`custom.env.template` を UTF-8/LF で作成。
2. `.ps1` 群は UTF-8/LF で作成 → **BOM 付与＋LF→CRLF 変換**で UTF-8 BOM/CRLF 化（§6-4）。
   - ⚠ **win-file-encoding skill は使わない**（同スキルは CP932/CRLF 用。今回の目標は UTF-8 BOM/CRLF）。BOM+CRLF は Python/iconv で直接付与する。
   - ルートに `.gitattributes` を追加: `*.ps1 text eol=crlf`（CRLF を Git 正規化から保護）。
3. `.gitignore`: `option-settings.{sh,ps1}` / `*.env`（custom.env 実体）は **既に整備済み（e233907）** → 追加不要・確認のみ。`custom.env` は非機微のため `permissions.deny` 追加は**任意**（§6-bis 帰結3）。
4. ローカルで起動スモークテスト（最小オプションで `claude --version` 相当を組み立て起動できるか）。`.sh` は bash で、`.ps1` は PowerShell で確認。
5. コミット候補提示 → 承認後コミット。publish は別途（remote push のため明示確認）。

## 8. 実装完了状況（2026-07-05）

C-BDK（`C:\cc-workspace\base-dev-kit-for-cc`・branch `feat/launcher-scripts`）に実装 8 ファイル＋設計書 2 点を作成・検証済み:

- [x] `.claude/launcher/` 作成
- [x] `.sh` 群（`start_claude_code.sh` / `setup-environment.sh` / `option-settings.sh.template` / `custom.env.template`）を UTF-8/LF で作成
- [x] `.ps1` 群（`start_claude_code.ps1` / `setup-environment.ps1` / `option-settings.ps1.template`）を UTF-8 BOM+CRLF で作成（python で BOM 付与・win-file-encoding は不使用）
- [x] `.gitattributes` を**ランチャーパス限定**で作成（既存 `scripts/*.ps1` 汚染回避）。`check-attr` で .ps1=crlf / .sh=lf 確認済み
- [x] `.gitignore`: launcher 個人実体除外（`.claude/option-settings.{sh,ps1}` / `*.env`）を**本ブランチに追加**。⚠ `develop` 起点で切ったため安全網コミット `e233907`（`chore/groom-as-share` のみに存在）が履歴に含まれず一旦**欠落**していた（F1 として検出）→ 本 PR で同等の除外を再追加。grep で実体除外・テンプレ（`*.template`）追跡を再確認
- [x] スモークテスト: bash・PowerShell 両版で「C 後勝ち固定（`ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` が custom.env 値を上書き）／custom.env の D ロード／`--flag value` と値なしフラグの組立／追加引数の claude 委譲」を確認
- [x] コミット・push・PR作成（C-BDK・branch `feat/launcher-scripts`・base `develop`）
- [ ] publish。**2 レールに分かれる**（remote push のため別途明示確認）:
  - payload レール: `.claude/launcher/*` ＋ `.claude/.gitignore` ＋ `.claude/.gitattributes` → publish-share → C-BDC
  - ルート直コミットレール: `start_claude_code.{sh,ps1}` ＋ ルート用 `.gitattributes` → C-BCP

### 8-bis. Fable クロスレビュー指摘の反映（2026-07-07 レビュー → 2026-07-12 実装）

3 観点クロスレビューの CRITICAL 2 / IMPORTANT 13 / SUGGESTION 6 を反映（レーンB）:

- [x] **CR-1** 配布先セーフティネットの payload 搬送: `.claude/.gitignore`（個人実体除外）と `.claude/.gitattributes`（launcher の改行固定）を新設。C-BDK ルートの同名ファイルは `.claude/` 外のため**配布されない**ことが根因。`check-ignore` / `check-attr` で実効を確認済み
- [x] **IM-1** §1/§5 の「custom.env＝秘匿情報の格納先」（§6-bis で撤回済み）を判定木準拠へ書き換え
- [x] **IM-2** §1/§6/§6-bis/§8 の publish 経路誤記（publish-share が `start_claude_code.*` を運ぶ）を「2 レール」へ訂正
- [x] **IM-3** `custom.env.template` のコピー先案内（「同じ .claude/ 直下」）を「一つ上の `.claude/` 直下」へ修正。加えて `launcher/custom.env` 誤配置時に警告するガードを追加
- [x] **IM-4** `setup-environment.sh` を `source` から**行パーサ**へ変更。CRLF の `\r` を除去し PowerShell 版と結果を一致させる（旧実装は CRLF の custom.env で `set -euo pipefail` 下に即死）。書式契約（素の `KEY=VALUE` のみ）をテンプレに明記
- [x] **IM-5** `start_claude_code.sh` に **bash 4.4+ の版数ガード**を追加（macOS 同梱 3.2 では `declare -A` / `local -n` が動かず即死するため）
- [x] **IM-6** `bypassPermissions` を通常の権限モード候補から外し、`--dangerously-skip-permissions` と同じ隔離節へ移動（sh/ps1 両テンプレ）
- [x] **IM-7** `--add-dir` 等の「複数指定は空白区切り」を撤回（連想配列はキー重複不可＝反復フラグを表現できない）。「1 値のみ。複数は起動時引数で」へ訂正し sh/ps1 を対称化
- [x] **IM-11** 分類B（Bedrock/Vertex）有効化時に **Advisor / Fast mode / Channels / Server-managed settings が無効**になる旨を注記。分類B の出口（将来 managed へ移設）が 3P では塞がれている事実も明記
- [x] **IM-12** TEAM_OPTS の「チーム値が優先」を精緻化（起動時引数で上書き可・反復フラグは累積＝強制力はない）
- [x] **IM-13** submodule 未初期化ガード（`setup-environment` 不在時に復旧手順を提示）と `claude` コマンド存在チェックを両ランチャーへ追加
- [x] **S-2** custom.env ローダに分類A 既知キーの検知ガード。**警告して読み飛ばす**（ファイルに書いた機微値が実際に効くと規律が機構ごと破れるため）
- [x] **S-4** 網羅方針に意図的除外（`--system-prompt(-file)` / `--allowedTools` / `--disallowedTools`）を明記
- [x] **S-5** `start_claude_code.ps1` に `exit $LASTEXITCODE` を追加（ヘッドレス/CI で失敗が沈黙するのを防ぐ）
- [x] **CR-2** publish ゲート強化（`.claude/reports/` 混入で FAIL・`.claude/CLAUDE.md` 不在で FAIL・個人実体で FAIL）。当初「PR#1 マージ後に実装」としていたが、**PR#1（`chore/groom-as-share`）側で先行実装済み**（`ab6436c` / `0df64e7` / `debb531`）。未 grooming な ref の payload が FAIL で publish 遮断されることを実測確認済み
- [ ] **IM-9/IM-10（Round 1）** root `CLAUDE.md` の役割確定（案X＝開発リポ専用文書に純化）と §ディレクトリ構造の改訂。**PR#1 マージ後**に実施（PR#1 が root `CLAUDE.md` を `CLAUDE.md.example` へリネームするため、先に入れるとコンフリクトする）

> **指摘 ID は巡回ごとに振り直されている**（例: 「IM-8」は Round 1 では「設計書の正本規定」、Round 2 では「clean-test-env の env 残存」）。他文書から参照する際は `R2-IM-8` のように巡回を明示すること。

**残タスク**: 【追加タスク C】exhaustive テンプレの可読性は本実装で構造規約を適用済み（カテゴリ分節・既定コメントアウト・危険フラグ隔離）＝実質達成。§6-bis 帰結の permissions.deny は非機微につき見送り。

### 8-ter. Claude Code v2.1.302 追随（2026-10-18 調査・反映）

v1.0.1（2026-07-20）以降の公式 docs 差分（LLMs リポ `c7a24cb`→`df8be8b`、changelog 2.1.215〜2.1.302）を SubAgent 4 本で調査し、反映した。調査報告は `.claude/reports/2026-10-18_cc-update_*.md`（gitignore 対象）。

- [x] **実行モデル**: background セッションへの env 到達の記述を是正（`start_claude_code.*` 冒頭・§3(1)・design §5 新設）。`CLAUDE_CODE_PROCESS_WRAPPER` は Windows で無視される旨を design §5-1 に、サブコマンド（`remote-control` / `agents`）委譲の注意を冒頭コメントと design §5-2 に明記
- [x] **option-settings テンプレ（sh/ps1 対称・44 キー）**: `--model` の既定説明とモデル ID（エイリアス `opus` / `sonnet,haiku`、フルネームは `claude-opus-5-5` 等）、`--permission-mode` の値集合（`auto` / `dontAsk` / `manual` 追加）と既定 auto、`--agents` のファイル指定が `--print` 専用、`--debug` の `=` 形、print 専用フラグの print 節への移動、`--from-pr` の説明修正、`--effort` の `ultracode`、新規 `--autocompact` / `--system-prompt-snapshot` / `--advisor` / `--name` / `--tmux` / `--permission-prompts` / `--append-subagent-system-prompt-file` / `--allow-dangerously-skip-permissions`、隔離節の `--permission-mode` 重複キー（PS で構文エラー）の除去、`--restricted` / `--bare` / `--safe-mode` 等の意図的除外を明記
- [x] **custom.env.template**: `ANTHROPIC_SMALL_FAST_MODEL`（DEPRECATED）→ `ANTHROPIC_DEFAULT_HAIKU_MODEL`、`MAX_THINKING_TOKENS` 中心の「思考予算」を `CLAUDE_CODE_EFFORT_LEVEL` 中心の「推論の深さ」へ、`ANTHROPIC_DEFAULT_MODEL` / `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` / `API_TIMEOUT_MS` / コンテキスト・キャッシュ / サブエージェント / Windows 環境の各分節を追加、`MCP_TOOL_TIMEOUT` の例示値修正、存在判定型 on/off env と認証付きプロキシ URL の注記
- [x] **setup-environment（sh/ps1）**: 分類A 検知を 17 キー＋接尾辞・URL 埋め込みのパターン検知・大文字小文字非区別へ拡張（両版の判定を実機で一致確認）。分類B ブロックを再構成（Foundry / Claude Platform on AWS の有効化行、`AWS_REGION` / `CLOUD_ML_REGION`、3P のモデル版固定、4 プロバイダのゲートウェイ行と `SKIP_*_AUTH`、OTel の project/local 無視、`DISABLE_TELEMETRY` の副作用、managed 出口の取得条件）。分類C に `--add-dir` 先の読み込み対象と background 到達の注記、「後勝ち」の効力範囲（settings の `env` に負ける）を追記
- [x] **TEAM_OPTS コメント**: append 系の併用例外と、project settings の `defaultMode` で `auto` / `bypassPermissions` が効かない旨を補足
- [x] **§4 / §5 / §6-bis 表**: インベントリと再マップを v2.1.302 時点へ更新（本節上部）
- [x] **既存項目の再確認**: IM-5（bash 4.4 ガード）/ IM-11（3P 機能制限。head でも同じ）/ IM-13（submodule・`claude` 存在チェック）/ S-5（`exit $LASTEXITCODE`）は v2.1.302 でも有効・変更不要。`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` の意味は不変（`--add-dir` 先の `AGENTS.md` は読まれない旨が追記されたのみ）
- **要実測（docs に記載が無い）**:
  - [ ] (1) ランチャーから起動したセッションが supervisor を立ち上げた場合に、後続の background セッションへ custom.env の値が波及するか（design §3(1) 注記）
  - [x] (2) 値を複数取るフラグ（`--add-dir` / `--mcp-config` / `--tools` / `--betas`）や値省略可のフラグ（`--resume` / `--worktree` / `--from-pr` / `--debug`）が OPTS の最後に並んだとき、`"$@"` 先頭のプロンプト文字列を値として取り込まないか（bash の連想配列は列挙順が不定） → **2026-10-19 実測: 取り込む**（`--worktree` 以外の 7 種で確認。`--` を挟めば防げる）。追加引数が全部非フラグのときだけ `--` を補う処理と bash 版の組立順ソートを `start_claude_code.{sh,ps1}` に実装（design §5-3）
  - [x] (3) Windows PowerShell 5.1 から `--agents` のインライン JSON を渡したとき `"` が保たれるか → **2026-10-19 実測: 5.1 は保たない**（ランチャー経由・直接とも全 `"` が落ち `{reviewer:{description:Reviews code,...}}` になる。`\"` でエスケープしても空白で引数が分割される）。pwsh 7.4 は保たれる。ネイティブ exe を引数記録用に作って測定。回避は pwsh 7 で起動（`option-settings.ps1.template` に注記）

---
変更履歴: 初版（実装前プレップ・2026-06-30）。design 確定版＋docs（cli-reference/env-vars v2.1 系）インベントリ反映。／2026-07-05 復帰セッションで §6-bis（判定木・再マップ・確定事項）追記、§7 を実リポ・UTF-8 BOM 方針・既存 .gitignore 実態に更新、§8 実装完了状況を追記。／同日追補: 判定木の分類ラベルを **分類C-Y→分類C、分類C-N→分類D** に改称（本文・実装スクリプト・メモリとも全置換、動作は不変）。／同日: research-by-cc（gitignore済みworkspace）からC-BDK `.claude/launcher/`へ本設計書2点をコピーし、branch `feat/launcher-scripts`（base develop）としてPR化。／同日 F1 修正: `develop` 起点でブランチを切った副作用で `.gitignore` の launcher 安全網（e233907・chore/groom-as-share のみ）が欠落していたため、同等の除外行を本ブランチへ再追加し §8 の記述を訂正。／同日 F2 修正: 本 doc と `launcher-scripts-design.md` を `.claude/launcher/` → `docs/launcher/` へ移設。`publish-share` が `.claude/` を丸ごと archive して C-BDC/C-BCP へ配布する仕様上、内部設計 doc が全消費者へ漏れるのを構造的に防ぐため（`docs/` は配布対象外・C-BDK 内では追跡継続）。／**2026-07-12（レーンB）**: Fable 5 × 3 観点クロスレビュー（2026-07-07）の指摘を実装反映。本書を**設計書の正本**として規定（IM-8）。CR-1（配布先セーフティネットの payload 搬送）・IM-1（撤回済み「custom.env＝秘匿格納」の残存）・IM-2（publish 経路誤記＝2 レール）を訂正し、§8-bis に反映状況を追加。CR-2 / IM-9 / IM-10 は PR#1（`chore/groom-as-share`）マージ後に実施する旨を明記。／**2026-07-12（Round 3 レビュー反映）**: (1) §8-bis の CR-2 を**完了**へ更新 ―― 「PR#1 マージ後に実装」としていたが PR#1 側で先行実装済みであり、**正本が存在しないタスクを指していた**（R3-H）。(2) §6 #2 に残っていた撤回済み前提の設問「秘匿系は全て custom.env でよいか」に撤回注記を追加（R3-S-3）。(3) 指摘 ID が巡回ごとに振り直される旨を注記（Round 1 の「IM-8」と Round 2 の「IM-8」は別物）。／**2026-07-12（マージ前セルフレビュー）**: 本変更履歴に Round 3 の反映が未記録だった点を補正（横断セルフレビュー F7）。／**2026-10-19**: §8-ter の要実測を 3 項目に分け、(2)（位置引数のプロンプトの取り込み）を実測して完了（design §5-3・ランチャーの `--` 補完と bash 版の組立順ソート）。／**2026-10-19（セキュリティレビュー参考所見）**: §3 (2) に、custom.env のランチャー内部変数名の読み飛ばし（bash 版だけで分類A の完全一致判定が無効化できた）と、分類A の名前パターン追加（`ANTHROPIC_CUSTOM_HEADERS`・名前全体・`SECRET_*`・`*_PASS` / `*_PASSWD` / `*_PWD` / `*_CONNECTION_STRING`）を追記。§6-bis 表に `ANTHROPIC_CUSTOM_HEADERS` を追加。
