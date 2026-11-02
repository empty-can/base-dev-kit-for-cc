# ランチャースクリプト実装計画（A タスク・実装前プレップ）

> **【正本・IM-8】本書は設計書の正本**（実装と同一 PR で共進化する側）。
> research-by-cc 側の同名文書（`reports/04.資産インベントリ・統合/04.ランチャースクリプト実装/`）は
> 2026-07-05 時点の**スナップショット**であり、以後更新しない。差分が出たら本書が正。
> 根拠: Fable クロスレビュー統合 IM-8（2 リポ二重管理によるドリフトを実検出）。

> `launcher-scripts-design.md`（確定設計・6ファイル構成）を実装に落とすための作業計画。
> 本書は休憩中の事前準備として作成。**コード生成は復帰後**。未確定点は §6 に集約。

> Claude Code の仕様変更の取り込み手順（週次追随）は `docs/launcher/claude-code-intake.md`。

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
- **env のローカルスコープ性**: ランチャープロセス内で設定した env は、子プロセスとして起動する `claude` にのみ継承され、OS env や他アプリに影響しない（bash の export / PS の `$env:` とも本質的にプロセスローカル）。⚠ **確実に届くのは foreground 起動の `claude` だけ**。background セッション（`/bg`・`←`・`claude --bg`・agent view からの dispatch）は supervisor 配下で新しいプロセスとして起動し直され、**ディレクトリの settings（`env` ブロック含む）＋引き継がれた構成フラグ**から構成を読む。dispatch 元シェルから届く env は `PATH`・プロバイダ選択（`CLAUDE_CODE_USE_BEDROCK` / `CLAUDE_CODE_USE_VERTEX`）・`ANTHROPIC_DEFAULT_*_MODEL`・`CLAUDE_CODE_EXTRA_BODY`（＋条件付きでゲートウェイ変数）に限られ、supervisor 自体は「最初に起動したシェル」の env を継承し、列挙外の env はこの経路で決まる（起動順次第で届くことはあるが確実ではない。§8-ter (1) で実測）。**custom.env / setup-environment の値は、この列挙に入るもの（プロバイダ選択等）を除いて確実には届かない**（公式: https://code.claude.com/docs/en/agent-view#settings-and-provider ）。
  - 帰結: `--add-dir <Share>` は background に引き継がれるが `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` は dispatch 元からは引き継がれない（ランチャー経由の `claude` が supervisor を立ち上げた場合だけ届く。§8-ter (1)）ため、**background セッションでは `<Share>` の CLAUDE.md / rules がロードされないことがある**。必要なら **OS の環境変数**（永続的なユーザー環境変数）として設定する（supervisor は最初に起動したシェルの env を継承するので、どの端末から起動されても届く。既に動いている service には、それが起動した時点の env が使われる）。公式 memory は `~/.claude/settings.json` の `env` を勧めるが、キットは design §3(6) の方針によりこの経路を使わない（組織で固定する値だけ managed settings の `env`）。
  - background service ごと起動装置に通す公式経路 `CLAUDE_CODE_PROCESS_WRAPPER` は **Windows では無視される**ため本キットの解にならない（design §5.2）。本ランチャー自体も利用者が端末から起動するもので、そこへ登録するランチャーではない（契約を満たさない。2026-10-24 に v2.1.310 の docs で再判定し、2026-11-03 に v2.1.316 の docs で再確認した。契約との対照表は design §5.2）。
  - 冒頭コメント（`start_claude_code.*`）にも同旨とサブコマンド委譲の注意（design §5.3）を明記。経路別の到達表は design §5.1.3。
  - ランチャー自身の警告・エラーは stderr にだけ書き、stdout は `claude` の出力だけにする（design §5.5。2026-10-24、PS 版の `Write-Warning` が別のプログラムから起動されたとき stdout に出ていたのを修正）。

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
- 公式推奨デフォルトを持つものは設定済み＆有効化。※ 実装では採っていない（2026-11-02 確認: テンプレ 3 本とも全行コメントアウトで、公式の既定値はコメントに記す。設計書 §3.3.2 / §3.4.2）。

## 4. CLI 起動オプション インベントリ（option-settings.template 候補）

基準: docs の cli-reference「CLI flags」の表（https://code.claude.com/docs/en/cli-reference ）、v2.1.316 時点（2026-11-03 確認。表は v2.1.310 から差分なし）。経緯は §8-ter 以降の追随記録。

### 現行の一覧

cli-reference の表のトップレベルのフラグ 80（別名は同じ行。「System prompt flags」の表の再掲は数えない）と、キットでの扱い。「テンプレ」は option-settings テンプレ（sh / ps1 は同じ 45 キー）に載せているか、「付録 A の理由」は `.claude/launcher/README.md` 付録 A に載せない理由があるか（「表」= 付録 A の表に個別の理由、「種類」= 付録 A の本文が挙げる「載せていない種類」に当たる〔個別には挙げていない〕、「—」= どちらも無い）。テンプレにも付録 A の表にも無い 25 の扱いは issue #4 の I-1 で裁定中で、裁定前は「未（I-1 の裁定後）」とする（種類の当てはめは docs の表の説明による）。

| フラグ（別名） | テンプレ | 付録 A の理由 | 備考 |
|---|---|---|---|
| `--add-dir` | ○ | — | 1 値だけ（2 個目以降は起動時引数）。background へ引き継がれる構成フラグ。ネットワークパスはランチャーが起動前に検出する（design §5.5） |
| `--advisor` | ○ | — | サードパーティプロバイダでは使えない |
| `--agent` | ○ | — | |
| `--agents` | ○ | — | ファイル指定は `--print` 併用時だけ。Windows PowerShell 5.1 ではインライン JSON が壊れる（README 付録 C） |
| `--allow-dangerously-skip-permissions` | ○（非推奨・破壊的の節） | — | background へ引き継がれる構成フラグ |
| `--allowedTools`, `--allowed-tools` | — | 表 | 権限統制は settings.json 側で管理する |
| `--append-subagent-system-prompt` | — | 種類（print / stream 専用） | docs では `-p` のときだけ効く。未（I-1 の裁定後） |
| `--append-subagent-system-prompt-file` | ○（print 節） | — | `-p` のときだけ効く |
| `--append-system-prompt` | ○ | — | |
| `--append-system-prompt-file` | ○ | — | |
| `--autocompact` | ○ | — | |
| `--ax-screen-reader` | — | — | 未（I-1 の裁定後） |
| `--bare` | — | 表 | 区分 1（design §5.5.3） |
| `--betas` | ○ | — | API キー利用者のみ |
| `--bg`, `--background` | — | 種類（別のモード） | background セッションを始めてすぐ戻る。未（I-1 の裁定後） |
| `--channels` | — | — | research preview。未（I-1 の裁定後） |
| `--chrome` | — | — | 未（I-1 の裁定後） |
| `--cloud` | — | 種類（別のモード） | クラウドセッションを作る。未（I-1 の裁定後） |
| `--continue`, `-c` | ○ | — | |
| `--dangerously-load-development-channels` | — | — | 未（I-1 の裁定後） |
| `--dangerously-skip-permissions` | ○（非推奨・破壊的の節） | — | `--permission-mode bypassPermissions` と同等（README 付録 B） |
| `--debug` | ○ | — | カテゴリの絞り込みは `=` 形でキーに書く |
| `--debug-file` | ○ | — | 2026-10-27 に追加（W42-F-01） |
| `--desktop` | — | 表 | |
| `--disable-slash-commands` | ○ | — | |
| `--disallowedTools`, `--disallowed-tools` | — | 表 | 権限統制は settings.json 側で管理する |
| `--effort` | ○ | — | 環境変数 `CLAUDE_CODE_EFFORT_LEVEL` が優先する |
| `--enable-auto-mode` | — | 種類（非推奨・削除済み） | 既存の判断: v2.1.111 で削除（docs の表に「Removed」として残る） |
| `--environment` | — | 表 | |
| `--exclude-dynamic-system-prompt-sections` | — | — | docs は `-p` との併用を例示（`-p` 専用とは書いていない）。未（I-1 の裁定後） |
| `--exec` | — | 種類（別のモード） | Claude のセッションを始めず、シェルのコマンドを background のジョブとして動かす。未（I-1 の裁定後） |
| `--fallback-model` | ○ | — | background へ引き継がれる構成フラグ |
| `--fork-session` | ○ | — | |
| `--forward-subagent-text` | — | 種類（print / stream 専用） | 出力ストリームへの出力。未（I-1 の裁定後） |
| `--from-pr` | ○ | — | |
| `--ide` | ○ | — | |
| `--init` | — | 種類（print / stream 専用） | print mode only。未（I-1 の裁定後） |
| `--init-only` | — | 種類（別のモード） | hook を動かして会話を始めずに終了する。未（I-1 の裁定後） |
| `--include-hook-events` | — | 種類（print / stream 専用） | 出力ストリームへの出力。未（I-1 の裁定後） |
| `--include-partial-messages` | ○（print 節） | — | |
| `--input-format` | ○（print 節） | — | |
| `--json-schema` | — | 種類（print / stream 専用） | print mode only。未（I-1 の裁定後） |
| `--maintenance` | — | 種類（print / stream 専用） | print mode only。未（I-1 の裁定後） |
| `--max-budget-usd` | ○（print 節） | — | |
| `--max-turns` | ○（print 節） | — | |
| `--mcp-config` | ○ | — | background へ引き継がれる構成フラグ |
| `--model` | ○ | — | |
| `--name`, `-n` | ○ | — | |
| `--no-chrome` | — | — | 未（I-1 の裁定後） |
| `--no-session-persistence` | — | 種類（print / stream 専用） | print mode only。未（I-1 の裁定後） |
| `--output-format` | ○（print 節） | — | |
| `--permission-mode` | ○ | — | `bypassPermissions` は書かない（README 付録 B）。過去の注記は下の記録 |
| `--permission-prompt-tool` | ○（print 節） | — | |
| `--permission-prompts` | ○（print 節） | — | |
| `--plugin-dir` | ○ | — | background へ引き継がれる構成フラグ |
| `--plugin-url` | ○ | — | |
| `--print`, `-p` | ○（print 節） | — | |
| `--prompt-suggestions` | — | 種類（print / stream 専用） | `--print`・`--output-format stream-json`・`--verbose` が要る。未（I-1 の裁定後） |
| `--ref` | — | 表 | |
| `--remote` | — | 種類（非推奨・削除済み） | 既存の判断: `--cloud` の非推奨の別名 |
| `--remote-control`, `--rc` | — | — | 未（I-1 の裁定後） |
| `--remote-control-session-name-prefix` | — | — | 未（I-1 の裁定後） |
| `--replay-user-messages` | — | 種類（print / stream 専用） | stream-json の入出力が要る。未（I-1 の裁定後） |
| `--restricted` | — | 表 | 区分 1（design §5.5.3） |
| `--resume`, `-r` | ○ | — | |
| `--safe-mode` | — | 表 | 区分 1（design §5.5.3） |
| `--session-id` | ○ | — | |
| `--setting-sources` | ○ | — | `project` を含まない値は区分 1 として検出する。background へ引き継がれる構成フラグ |
| `--settings` | ○ | — | background へ引き継がれる構成フラグ |
| `--strict-mcp-config` | ○ | — | background へ引き継がれる構成フラグ |
| `--system-prompt` | — | 表 | 区分 1（design §5.5.3） |
| `--system-prompt-file` | — | 表 | 区分 1（design §5.5.3） |
| `--system-prompt-snapshot` | ○ | — | |
| `--teleport` | — | 種類（別のモード） | クラウドセッションを端末で再開する。未（I-1 の裁定後） |
| `--teammate-mode` | ○ | — | |
| `--tmux` | ○ | — | |
| `--tools` | ○ | — | |
| `--verbose` | ○ | — | |
| `--version`, `-v` | — | 種類（別のモード） | 版を表示して終了する。未（I-1 の裁定後） |
| `--worktree`, `-w` | ○ | — | |

集計: テンプレ 45（うち print 節 9・非推奨・破壊的の節 2）、付録 A の表 10、どちらにも無い 25（種類に当たるもの: print / stream 専用 9・別のモード 6・非推奨・削除済み 2、種類に当たらないもの 8）。トップレベルのフラグではないもの: `--sso`（`claude auth login` のオプション）、`--post` / `--no-post` / `--trust-workspace`（`claude ultrareview`）、`--discard-unpushed` / `--force-remove-worktree`（`claude rm`）。後の 2 組は付録 A の表に「サブコマンド専用」として載せている。

### 過去の追補（記録。原文のまま）

以下は v2.1.302 時点（2026-10-18）の一覧と、その後の追補・注記の原文。現行の扱いは上の表による。

**ランチャーで露出する有力候補（curated）**:
`--model` / `--fallback-model` / `--add-dir` / `--settings` / `--setting-sources` / `--mcp-config` / `--strict-mcp-config` / `--permission-mode` / `--agents` / `--agent` / `--append-system-prompt-file` / `--effort` / `--autocompact` / `--worktree` / `--debug` / `--ide` / `--verbose`

> `--permission-mode` の注記（2026-10-18）: 組み込み既定は **auto**（対話起動。v2.1.283〜全プラン・全プロバイダ。ネイティブ Windows は v2.1.233〜）。`-p` は changelog 2.1.302 で `default` に戻った（2026-10-24 追補: v2.1.310 の docs〔permission-modes「Which mode a session starts in」の表・「Tool calls denied in `claude -p` and Agent SDK runs」〕にも載った。`-p` で承認の要る呼び出しは、allow ルール・hook・`--permission-prompt-tool` のどれかが承認しないと拒否される。3P プロバイダや `DISABLE_TELEMETRY` でも v2.1.302 以降は `default`。ランチャーで `-p` を使う構成では `--allowedTools` か `--permission-mode` を明示する）。project の `.claude/settings.json` の `permissions.defaultMode` に `auto` / `bypassPermissions` を書いても効かない（`default` / `plan` / `acceptEdits` 等は効く）。チームで Manual を既定に揃えたいなら TEAM_OPTS の `--permission-mode default` か project settings の `"defaultMode": "default"`、強制したいなら managed settings の `disableAutoMode`。`restricted` は `--permission-mode` の値ではなく独立フラグ `--restricted`。

**全フラグ（参考・cli-reference の CLI flags 表より。別名は省略）**:
`--add-dir --advisor --agent --agents --allow-dangerously-skip-permissions --allowedTools --append-subagent-system-prompt(-file) --append-system-prompt(-file) --autocompact --ax-screen-reader --bare --betas --bg --channels --chrome --cloud --continue --dangerously-load-development-channels --dangerously-skip-permissions --debug --desktop --disable-slash-commands --disallowedTools --effort --environment --exclude-dynamic-system-prompt-sections --exec --fallback-model --fork-session --forward-subagent-text --from-pr --ide --include-hook-events --include-partial-messages --init --init-only --input-format --json-schema --maintenance --max-budget-usd --max-turns --mcp-config --model --name --no-chrome --no-session-persistence --output-format --permission-mode --permission-prompt-tool --permission-prompts --plugin-dir --plugin-url --print --prompt-suggestions --ref --remote-control --remote-control-session-name-prefix --replay-user-messages --restricted --resume --safe-mode --session-id --setting-sources --settings --strict-mcp-config --system-prompt(-file) --system-prompt-snapshot --teammate-mode --teleport --tmux --tools --verbose --version --worktree`
（`--remote` は `--cloud` の非推奨の別名、`--enable-auto-mode` は v2.1.111 で削除。`--sso` はトップレベルのフラグではなく `claude auth login` のオプション。`--post` / `--no-post`〔ultrareview〕と `--discard-unpushed` / `--force-remove-worktree`〔rm〕はサブコマンドのオプション。`--dangerously-*` 系は既定で露出しない方針を推奨）

**2026-10-18 追補（v2.1.214→v2.1.302）**: base にあって head で消えたフラグは 0。head で増えたトップレベルのフラグは `--append-subagent-system-prompt-file --autocompact --desktop --environment --permission-prompts --ref --restricted --system-prompt-snapshot`。テンプレには `--autocompact` / `--system-prompt-snapshot`（対話向け）と `--permission-prompts` / `--append-subagent-system-prompt-file`（print 節）を追加し、`--restricted` / `--bare` / `--safe-mode` / `--desktop` / `--environment` / `--ref` は「意図的に載せていないもの」へ回した。
- `--restricted` は managed settings と `--settings` しか読まないため、**キットの `.claude/settings.json`（`.bat` の deny・hooks）が載らない**。露出するなら「`--settings <Share>/.claude/settings.json` と併用」を注記する。
- `--bg` 系の background 起動では、引き継がれるのは構成フラグだけ（design §5.1.3）。
- `--debug` のカテゴリ絞り込みは `=` 形でしか効かないため、テンプレではキー側に `--debug=mcp,startup` と書く方式を採った（組立ロジックは不変）。
- `--max-budget-usd` / `--max-turns` / `--include-partial-messages` / `--permission-prompt-tool` は print 専用（base 時点からの不整合）。テンプレでは print 節へ移した。

## 5. 環境変数 インベントリ（custom.env.template / 固定 env 候補）

基準: docs の env-vars「Variables」（https://code.claude.com/docs/en/env-vars ）、v2.1.316 時点（2026-11-03 確認）。経緯は §8-ter 以降の追随記録。

### 現行の一覧

`custom.env.template` の全キー（26）と `setup-environment` の固定 env の候補（34。両方にあるものは 1 行にまとめた）に、v2.1.302 以降に env-vars に行が増えた変数のうちランチャーに関わりうるものを加えた表。分類は §6-bis の判定木（A〜D）。分類A の機微なキー（`ANTHROPIC_API_KEY` 等）は §6-bis の表にあり、ここには載せない。収録の基準は issue #4 の I-3 で裁定中で、裁定前の新しい変数は分類を「未（I-3 の裁定後）」とする。「docs の行」は env-vars の表に行があるか（無いものは載っているページを書く）。

| 変数 | 分類 | 置き場 | docs の行 | 備考 |
|---|---|---|---|---|
| `ANTHROPIC_DEFAULT_MODEL` | D | custom.env | ○ | `--model` と役割が重なる（原則 option-settings） |
| `ANTHROPIC_MODEL` | D | custom.env | ○ | 同上。`/model` の保存選択より毎回優先される |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | D（3P の版固定では B） | custom.env／setup-environment（3P のモデル版固定） | ○ | 旧名 `ANTHROPIC_SMALL_FAST_MODEL` は DEPRECATED |
| `CLAUDE_CODE_SUBAGENT_MODEL` / `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` | D | custom.env | ○ | 前者は v2.1.251 以降は既定値扱い |
| `CLAUDE_CODE_EFFORT_LEVEL` | D | custom.env | ○ | `--effort`・`/effort` より優先。`auto` / `unset` は effort を送らず API の既定に任せる（W44-B-01） |
| `MAX_THINKING_TOKENS` | D | custom.env | ○ | 現行モデルでは正の値が無視される |
| `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS` / `CLAUDE_CODE_PROMPT_CACHE_TTL` | D | custom.env | ○ | コストに影響する（チームで揃えるなら setup-environment） |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | D | custom.env | ○ | `--autocompact` より優先 |
| `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | D | custom.env | ○ | |
| `CLAUDE_CODE_FORK_SUBAGENT` | D | custom.env | ○ | v2.1.302 以降は全セッションで既定オン |
| `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | D | custom.env | ○ | background セッションは止めない（止めるのは `CLAUDE_CODE_DISABLE_AGENT_VIEW`。W44-B-02） |
| `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` / `MCP_TIMEOUT` / `MCP_TOOL_TIMEOUT` / `API_TIMEOUT_MS` | D | custom.env | ○ | 環境依存 |
| `CLAUDE_CODE_WARN_DISK_FREE_GIB` / `CLAUDE_CODE_WARN_MEMORY_FREE_GIB` | D | custom.env | ○ | 起動環境からしか読まれない（settings の `env` では無視。design §5.1.3） |
| `CLAUDE_CODE_GIT_BASH_PATH` / `CLAUDE_CODE_BS_AS_CTRL_BACKSPACE` / `CLAUDE_CODE_USE_POWERSHELL_TOOL` | D | custom.env | ○ | Windows。`CLAUDE_CODE_USE_POWERSHELL_TOOL` はチーム判断で C にしうる |
| `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | D（既定）／B | custom.env／setup-environment（企業プロキシ前提のチーム） | ○ | 認証情報入りの URL は A |
| `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` | C | setup-environment（`=1`。有効） | ○ | キットの動作が依存する |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` | C（条件付き） | setup-environment（コメントアウト） | ○ | 自前の git skill を採用したときだけ |
| `CLAUDE_CODE_USE_BEDROCK` / `CLAUDE_CODE_USE_ANTHROPIC_AWS` / `CLAUDE_CODE_USE_VERTEX` / `CLAUDE_CODE_USE_FOUNDRY` | B | setup-environment（暫定 C。コメントアウト） | ○ | 1 つだけ有効にする |
| `ANTHROPIC_AWS_WORKSPACE_ID` / `ANTHROPIC_VERTEX_PROJECT_ID` / `ANTHROPIC_FOUNDRY_RESOURCE` | B | 同上 | ○ | 識別子（資格情報ではない） |
| `AWS_REGION` / `CLOUD_ML_REGION` | B | 同上 | 行なし（amazon-bedrock・claude-platform-on-aws／google-vertex-ai のページ） | |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_SONNET_MODEL`（と上の `ANTHROPIC_DEFAULT_HAIKU_MODEL`） | B | 同上 | ○ | 3P のモデル版固定 |
| `ANTHROPIC_BASE_URL` | A または B | 機微なら OS env／非秘匿なら setup-environment | ○ | ゲートウェイの認証は A |
| `ENABLE_TOOL_SEARCH` | B | setup-environment（暫定 C） | ○ | ゲートウェイが転送できないときだけ `false` |
| `ANTHROPIC_BEDROCK_BASE_URL` / `ANTHROPIC_AWS_BASE_URL` / `ANTHROPIC_VERTEX_BASE_URL` / `ANTHROPIC_FOUNDRY_BASE_URL` と対の `CLAUDE_CODE_SKIP_BEDROCK_AUTH` / `CLAUDE_CODE_SKIP_ANTHROPIC_AWS_AUTH` / `CLAUDE_CODE_SKIP_VERTEX_AUTH` / `CLAUDE_CODE_SKIP_FOUNDRY_AUTH` | A または B | 機微なら OS env／非秘匿なら setup-environment | ○ | プロバイダ形式のゲートウェイ |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | B | setup-environment（暫定 C） | ○ | project / local の settings では無視される |
| `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_METRICS_EXPORTER` / `OTEL_LOGS_EXPORTER` / `OTEL_EXPORTER_OTLP_PROTOCOL` | B | 同上 | 行なし（monitoring-usage のページ） | `OTEL_EXPORTER_OTLP_*HEADERS` は A |
| `DISABLE_TELEMETRY` / `DISABLE_ERROR_REPORTING` | B | 同上 | ○ | `DISABLE_TELEMETRY` は feature flag の取得も止める |
| `CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS` | 未（I-3 の裁定後） | — | ○（v2.1.311 以降） | 起動環境からしか読まれない（check-assets の E）。docs では、Bash / Edit / Read を対象にする deny / ask ルールがあると効かず（キットの project settings にある）、background セッションはこの変数を持たずに始まる |
| `CLAUDE_CODE_RESUME_SHOWS_CUT_OFF_CALLS` | 未（I-3 の裁定後） | — | ○（v2.1.309 以降） | |
| `CLAUDE_CODE_DISABLE_MOUNTED_DRIVE_RM_PROMPT` | 未（I-3 の裁定後） | — | ○（v2.1.304 以降） | 起動環境からしか読まれない（check-assets の E） |
| `CLAUDE_CODE_DISABLE_MCP_TASK_BACKGROUND` | 未（I-3 の裁定後） | — | ○（v2.1.304 以降） | |
| `CLAUDE_CODE_DISABLE_ULTRAREVIEW_TRUST_CHECK` | 未（I-3 の裁定後） | — | ○（v2.1.309 以降） | docs は起動環境で設定するよう書く（settings-reference の無視の一覧には無い） |
| `CLAUDE_CODE_ENABLE_SHARE_BUNDLE` | 未（I-3 の裁定後） | — | ○（v2.1.299 以降） | |
| `CLAUDE_CODE_RETRY_WATCHDOG_USAGE_LIMIT_RECHECK_MS` | 未（I-3 の裁定後） | — | ○ | |
| `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` / `CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK` | 未（I-3 の裁定後。分類B の例示に載せるか） | — | ○（既存の行） | changelog 2.1.312 で、3P の Claude Code が知らないモデル名にも効くようになった |
| `CLAUDE_CODE_AUTO_MODE_MODEL` | —（採用しない） | — | ○ | 2026-10-24 に閉じた（W42-B-11。下の過去の追補） |

表に無い変数の過去の判断（`CLAUDE_CODE_RESTRICTED`・`CLAUDE_CODE_PLUGIN_DIRS` の不採用、`CLAUDE_CODE_PROCESS_WRAPPER` は Windows で無視、`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` を D とした等）は、下の過去の追補と §6-bis にある。

### 過去の追補（記録。原文のまま）

以下は v2.1.302 時点（2026-10-18）の一覧と、その後の追補の原文。現行の扱いは上の表と §6-bis による。

> **⚠ 本節の分類は §6-bis の判定木で置き換わっている**。下記の「多くは秘匿＝custom.env」という
> 初期案は**撤回済み**。機微（分類A）は custom.env に書かず OS 環境変数で供給する。
> 以下はインベントリ（どんな env があるか）としてのみ読むこと。

カテゴリ分類（フル一覧は docs の env-vars のページ〔上の URL〕。ここでは launcher 関連を抜粋）:

- **プロバイダ/認証（大半が分類A＝機微。custom.env ではなく OS 環境変数で供給）**: `ANTHROPIC_API_KEY` `ANTHROPIC_AUTH_TOKEN` `ANTHROPIC_BASE_URL` `ANTHROPIC_MODEL` `ANTHROPIC_SMALL_FAST_MODEL`（DEPRECATED・後継は `ANTHROPIC_DEFAULT_HAIKU_MODEL`）/ Bedrock: `CLAUDE_CODE_USE_BEDROCK` `AWS_BEARER_TOKEN_BEDROCK` `ANTHROPIC_BEDROCK_BASE_URL` / Vertex: `CLAUDE_CODE_USE_VERTEX` `ANTHROPIC_VERTEX_PROJECT_ID` `CLAUDE_CODE_SKIP_VERTEX_AUTH` / OAuth(SSO・**今回不使用**): `CLAUDE_CODE_OAUTH_TOKEN` `CLAUDE_CODE_OAUTH_REFRESH_TOKEN`
  - ※ bearer ゲートウェイトークンには専用 helper が無い。**だからといって custom.env に置いてよいわけではない**（当初はそう書いていたが §6-bis で撤回）。helper が無い以上、供給手段は **OS の環境変数**となる。`setup-environment` は `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `AWS_BEARER_TOKEN_BEDROCK` 等を custom.env 内に見つけたら、**読み込まずに警告**する（規律を機構で担保）。機微な値はどのファイルにも書かず OS の環境変数で供給する、という作業指示者の方針（§6-bis の判定木の分類A。2026-07-05 確定）と整合。
  - ※ プロバイダ選択（Bedrock / Claude Platform on AWS / Vertex / Foundry）を有効化すると **Advisor / Fast mode / Channels / Server-managed settings / Analytics が使えなくなる**（公式 docs「Feature availability」。2026-10-18 再確認で head も同じ。加えて 3P では Web search が Bedrock ✗・Agent Platform は条件付き、Auto mode は対応モデル限定、cross-session messaging は同一マシン内に限る）。server-managed settings は 1P でも、Team/Enterprise・api.anthropic.com 直結・OAuth ログイン／`CLAUDE_CODE_OAUTH_TOKEN`／直接設定の API キーの場合にしか届かない（apiKeyHelper・WIF・非既定の `ANTHROPIC_BASE_URL` では届かず、Console の API キーは Console 組織の設定を取りに行く）。分類B の出口は原則 endpoint-managed（MDM / ファイル配布の managed-settings.json。Windows は `C:\Program Files\ClaudeCode\managed-settings.json` または `HKLM\SOFTWARE\Policies\ClaudeCode` の `Settings` 値）。3P は Claude apps gateway が server-managed 相当。managed の `env` は管理ソース間で変数単位にマージされる（v2.1.223+）。プロバイダの統制は `allowedProviders`（v2.1.285+）で行える。
- **挙動・チーム統制候補（固定 env になりうる＝非秘匿）**: `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`（キットが依存）/ `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`（自前 git skill 採用時）/ `MAX_THINKING_TOKENS`（現行モデルでは正の値が無視される。effort は `CLAUDE_CODE_EFFORT_LEVEL`）/ `CLAUDE_CODE_SUBAGENT_MODEL`（v2.1.251 以降は既定値扱い。強制は `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`）/ `BASH_DEFAULT_TIMEOUT_MS` `BASH_MAX_TIMEOUT_MS` / `MCP_TIMEOUT` `MCP_TOOL_TIMEOUT`
- **プロキシ/テレメトリ（環境依存・任意）**: `HTTP_PROXY` `HTTPS_PROXY` `NO_PROXY` / `CLAUDE_CODE_ENABLE_TELEMETRY` `OTEL_*` / `DISABLE_TELEMETRY` `DISABLE_ERROR_REPORTING`
- **2026-10-18 追補（v2.1.214→v2.1.302 で増えた・意味が変わったもの）**: `ANTHROPIC_DEFAULT_MODEL`（D・v2.1.236〜。`/model` の保存選択に譲る既定）/ `CLAUDE_CODE_EFFORT_LEVEL`（D。`--effort` / `/effort` より優先）/ `CLAUDE_CODE_FORK_SUBAGENT`（D・fork mode は v2.1.232〜対話セッションで既定オン。2026-10-24 追補: v2.1.302〜は `-p` / Agent SDK を含む全セッションで既定オン。オンの間、対話セッションでは Claude がサブエージェントの完了を待てない）/ `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`・`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`（D）/ `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS`・`CLAUDE_CODE_PROMPT_CACHE_TTL`（D・コスト影響）/ `API_TIMEOUT_MS`（D）/ `CLAUDE_CODE_USE_POWERSHELL_TOOL`・`CLAUDE_CODE_GIT_BASH_PATH`・`CLAUDE_CODE_BS_AS_CTRL_BACKSPACE`（Windows・D）/ `CLAUDE_CODE_USE_FOUNDRY`・`ANTHROPIC_FOUNDRY_RESOURCE`・`CLAUDE_CODE_USE_ANTHROPIC_AWS`・`ANTHROPIC_AWS_WORKSPACE_ID`・`AWS_REGION`・`CLOUD_ML_REGION`・`ANTHROPIC_DEFAULT_*_MODEL`（3P の版固定）（B）/ `CLAUDE_CODE_RESTRICTED`（settings の `env` では無視される。キットの project settings が載らないため不採用）/ `CLAUDE_CODE_PROCESS_WRAPPER`（B・Windows では無視・user/managed settings のみ）/ `CLAUDE_CODE_PLUGIN_DIRS`（`--plugin-dir` 相当。ランチャーはフラグで渡せるため不採用）/ `CLAUDE_CODE_AUTO_MODE_MODEL`（changelog 2.1.302 のみ。docs 掲載後に再評価 → 2026-10-24: v2.1.310 の docs〔env-vars・permission-modes「Choose the classifier model」〕に載ったので再評価し、**採用しない**で閉じた。auto mode の分類器のモデルを変える用途に限られ、モデルの allowlist の下では無視される。Week 42 レール B の W42-B-11）。いずれもランチャーで設定すると foreground にしか確実には効かない（design §5.1.3）。env-vars ページから消えた `AWS_REGION` `GOOGLE_APPLICATION_CREDENTIALS` `GOOGLE_CLOUD_PROJECT` はプロバイダページへ移動（存続）、`CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT` は内部変数の文書化をやめたもの（キット未使用）。

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
- 分類B は「暫定 C」として当面 `setup-environment` / `start_claude_code` に置くが、**将来 managed スコープへ移設予定**である旨をコメントで明記する。移設の動機は統制の強制力に加えて **background セッションへの到達**: ランチャーの env は background（`/bg`・`claude --bg`・agent view）に確実には届かないが、managed settings の `env` は届く（design §5.1.3）。3P（Bedrock / Vertex 等）では server-managed settings が使えず、1P でも取得条件が限られるため、出口は endpoint-managed（MDM 配布のローカル managed settings。Windows: `C:\Program Files\ClaudeCode\managed-settings.json` または `HKLM\SOFTWARE\Policies\ClaudeCode` の `Settings` 値）となる（§5 の注記も参照）。OTel の有効化・送信先系の env は project / local settings では無視される（v2.1.282+）ため、settings へ移すときも user か managed に置く。起動環境からしか読まれない変数（`CLAUDE_CODE_RESTRICTED`・`CLAUDE_CODE_DISABLE_*_RM_*`・`CLAUDE_CODE_WARN_*_FREE_GIB` 等。design §5.1.3）は managed の `env` でも無視されるため、managed へ移せない（2026-10-24 追補）。
- 起動オプションの拡張子: `option-settings` は**コメントアウト容易性から .sh/.ps1 連想配列形式で確定**（作業指示者選好）。

§5 env 再マップ:

| env | 分類 | 配置 | 備考 |
|---|---|---|---|
| `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `AWS_BEARER_TOKEN_BEDROCK` | **A** | OS env（不記述） | 機微。bearer は OS env で供給 |
| `ANTHROPIC_BASE_URL` / `ANTHROPIC_BEDROCK_BASE_URL` | A または B | 機微なら OS env / 非秘匿なら setup-environment（暫定） | 組織外秘の内部 GW URL なら A、非秘匿なら B。2026-10-27: setup-environment のゲートウェイ節に `ANTHROPIC_BASE_URL`（Anthropic Messages 形式。LiteLLM 等）の例を追加（W42-F-02）。ゲートウェイの認証（`ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY`）は A のまま（custom.env を含むどの `.env` にも書かない）。`ANTHROPIC_CUSTOM_HEADERS` は値次第で、認証情報・個人情報を載せるなら A（2026-10-27 のレビューで作業指示者の方針に合わせて文面を改めた。検知は名前で行うので、載せないヘッダでも custom.env では読み飛ばされる） |
| `ENABLE_TOOL_SEARCH`（ゲートウェイ配下） | **B** | setup-environment（暫定 C） | 2026-10-27 追加（W42-F-02）。custom の `ANTHROPIC_BASE_URL` の下では tool search が既定 on（v2.1.304〜）で、拒否（400 / 422）されると自動で再試行される（v2.1.305〜）。`false` はゲートウェイが `defer_loading` / `tool_reference` を転送できない場合だけ。ゲートウェイの能力で決まるので組織で揃える |
| `CLAUDE_CODE_USE_BEDROCK` / `USE_VERTEX` / `CLAUDE_CODE_SKIP_VERTEX_AUTH` / `ANTHROPIC_VERTEX_PROJECT_ID` | **B** | setup-environment（暫定 C） | プロバイダ/組織インフラ選択。managed 候補 |
| `CLAUDE_CODE_ENABLE_TELEMETRY` / `OTEL_*` / `DISABLE_TELEMETRY` / `DISABLE_ERROR_REPORTING` | **B** | setup-environment（暫定 C） | データガバナンス・SIEM。managed 筆頭候補 |
| `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | **D**（既定）／必要時 B | 既定 custom.env、企業プロキシ前提チームは setup-environment | 作業指示者 Q1 確定＝既定可変・昇格可 |
| `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` | **C** | setup-environment（`=1`） | キット動作依存 |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` | **C**（条件付き） | setup-environment | 自前 git skill 採用時のみ |
| `ANTHROPIC_DEFAULT_MODEL` / `ANTHROPIC_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL` | **D** | custom.env（※ `--model` と重複＝原則 option-settings 側） | `ANTHROPIC_MODEL` は /model の保存選択より毎回優先。`ANTHROPIC_SMALL_FAST_MODEL` は DEPRECATED |
| `CLAUDE_CODE_SUBAGENT_MODEL`（v2.1.251 以降は既定値）/ `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` / `CLAUDE_CODE_EFFORT_LEVEL` | **D** | custom.env | 個人選好。`MAX_THINKING_TOKENS` は現行モデルで無効（旧モデル用） |
| `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` / `MCP_TIMEOUT` / `MCP_TOOL_TIMEOUT` / `API_TIMEOUT_MS` | **D** | custom.env | 環境依存 |
| `CLAUDE_CODE_OAUTH_TOKEN` / `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` / `ANTHROPIC_FOUNDRY_API_KEY` / `ANTHROPIC_FOUNDRY_AUTH_TOKEN` / `ANTHROPIC_AWS_API_KEY` / `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` / `MCP_CLIENT_SECRET` / `CLAUDE_CODE_CLIENT_KEY_PASSPHRASE` / `OTEL_EXPORTER_OTLP_*HEADERS` / `ANTHROPIC_CUSTOM_HEADERS` | **A** | OS env（不記述） | 2026-10-18 追補（`ANTHROPIC_CUSTOM_HEADERS` は 2026-10-19。分類は値次第〔認証情報・個人情報を載せるなら A〕だが、検知は名前で行い値によらず読み飛ばす）。setup-environment の検知リストにも追加（名前の接尾辞・URL 埋め込み資格情報も検知） |
| `CLAUDE_CODE_USE_FOUNDRY` / `ANTHROPIC_FOUNDRY_RESOURCE` / `CLAUDE_CODE_USE_ANTHROPIC_AWS` / `ANTHROPIC_AWS_WORKSPACE_ID` / `AWS_REGION` / `CLOUD_ML_REGION` / `ANTHROPIC_DEFAULT_*_MODEL`（3P の版固定） | **B** | setup-environment（暫定 C） | managed では `allowedProviders`（v2.1.285+）でプロバイダ自体も制限できる |
| `ANTHROPIC_VERTEX_BASE_URL` / `ANTHROPIC_FOUNDRY_BASE_URL` / `ANTHROPIC_AWS_BASE_URL` ＋ 各 `CLAUDE_CODE_SKIP_*_AUTH` | A または B | 機微なら OS env / 非秘匿なら setup-environment（暫定） | `ANTHROPIC_BEDROCK_BASE_URL` 行と同じ扱い |
| `CLAUDE_CODE_GIT_BASH_PATH` / `CLAUDE_CODE_BS_AS_CTRL_BACKSPACE` / `CLAUDE_CODE_USE_POWERSHELL_TOOL` | **D** | custom.env | Windows 系は「Windows 環境」分節。`USE_POWERSHELL_TOOL` はチーム判断で C にしうる |
| `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS` / `CLAUDE_CODE_PROMPT_CACHE_TTL` / `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` / `CLAUDE_CODE_FORK_SUBAGENT` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` / `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | **D** | custom.env | コストに影響するものはチームで揃えるなら setup-environment へ。`CLAUDE_CODE_AUTO_COMPACT_WINDOW` と `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` は 2026-10-24 追加（前者は接尾辞なしの数値がトークン数そのもの。`k` / `M` は v2.1.304〜） |
| `CLAUDE_CODE_WARN_DISK_FREE_GIB` / `CLAUDE_CODE_WARN_MEMORY_FREE_GIB` | **D** | custom.env | 2026-10-24 追加（v2.1.304〜）。起動環境からしか読まれず、どの settings の `env` でも無視される（design §5.1.3）ので、custom.env か OS の環境変数で設定する |

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

> Claude Code の仕様変更の取り込み手順（週次追随）は `docs/launcher/claude-code-intake.md`。

> **追随記録の型**: Claude Code の追随の記録は §8 の下に小節として足す。次の記録から、見出しに版を入れず通し番号にする（例「8-quinquies. Claude Code 追随の記録」。§8-ter・§8-quater の見出しは変えない）。本文 1 行目に範囲（changelog の版 2.1.X〜2.1.Y、LLMs リポ〔公式 docs の複製〕の base → head の SHA、日付）を書き、続けて、レール A〜E ごとの反映（項目 ID 付き）／差分なしを確かめたページと節／要実測／未決（作業指示者の判断待ち。issue 番号）／changelog にあって docs に無いもの（docs 掲載後に再評価）を書く。設計書の本文を変えたら別紙（`docs/launcher/【別紙】launcher-scripts-design変更履歴.md`）にも項を足す。手順書の 7. と同じ内容。

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

コミット 9404a86（2026-07-20。旧タグ v1.0.1）以降の公式 docs 差分（LLMs リポ `c7a24cb`→`df8be8b`、changelog 2.1.215〜2.1.302）を SubAgent 4 本で調査し、反映した（2026-10-18。結論は本節に書き写してある）。

- [x] **実行モデル**: background セッションへの env 到達の記述を是正（`start_claude_code.*` 冒頭・§3(1)・design §5 新設）。`CLAUDE_CODE_PROCESS_WRAPPER` は Windows で無視される旨を design §5.2 に、サブコマンド（`remote-control` / `agents`）委譲の注意を冒頭コメントと design §5.3 に明記
- [x] **option-settings テンプレ（sh/ps1 対称・44 キー。2026-10-27 に `--debug-file` を加えて 45 キー〔§8-quater〕）**: `--model` の既定説明とモデル ID（エイリアス `opus` / `sonnet,haiku`、フルネームは `claude-opus-5-5` 等）、`--permission-mode` の値集合（`auto` / `dontAsk` / `manual` 追加）と既定 auto、`--agents` のファイル指定が `--print` 専用、`--debug` の `=` 形、print 専用フラグの print 節への移動、`--from-pr` の説明修正、`--effort` の `ultracode`、新規 `--autocompact` / `--system-prompt-snapshot` / `--advisor` / `--name` / `--tmux` / `--permission-prompts` / `--append-subagent-system-prompt-file` / `--allow-dangerously-skip-permissions`、隔離節の `--permission-mode` 重複キー（PS で構文エラー）の除去、`--restricted` / `--bare` / `--safe-mode` 等の意図的除外を明記
- [x] **custom.env.template**: `ANTHROPIC_SMALL_FAST_MODEL`（DEPRECATED）→ `ANTHROPIC_DEFAULT_HAIKU_MODEL`、`MAX_THINKING_TOKENS` 中心の「思考予算」を `CLAUDE_CODE_EFFORT_LEVEL` 中心の「推論の深さ」へ、`ANTHROPIC_DEFAULT_MODEL` / `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` / `API_TIMEOUT_MS` / コンテキスト・キャッシュ / サブエージェント / Windows 環境の各分節を追加、`MCP_TOOL_TIMEOUT` の例示値修正、存在判定型 on/off env と認証付きプロキシ URL の注記
- [x] **setup-environment（sh/ps1）**: 分類A 検知を 17 キー＋接尾辞・URL 埋め込みのパターン検知・大文字小文字非区別へ拡張（両版の判定を実機で一致確認）。分類B ブロックを再構成（Foundry / Claude Platform on AWS の有効化行、`AWS_REGION` / `CLOUD_ML_REGION`、3P のモデル版固定、4 プロバイダのゲートウェイ行と `SKIP_*_AUTH`、OTel の project/local 無視、`DISABLE_TELEMETRY` の副作用、managed 出口の取得条件）。分類C に `--add-dir` 先の読み込み対象と background 到達の注記、「後勝ち」の効力範囲（settings の `env` に負ける）を追記
- [x] **TEAM_OPTS コメント**: append 系の併用例外と、project settings の `defaultMode` で `auto` / `bypassPermissions` が効かない旨を補足
- [x] **§4 / §5 / §6-bis 表**: インベントリと再マップを v2.1.302 時点へ更新（本節上部）
- [x] **既存項目の再確認**: IM-5（bash 4.4 ガード）/ IM-11（3P 機能制限。head でも同じ）/ IM-13（submodule・`claude` 存在チェック）/ S-5（`exit $LASTEXITCODE`）は v2.1.302 でも有効・変更不要。`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` の意味は不変（`--add-dir` 先の `AGENTS.md` は読まれない旨が追記されたのみ）
- **要実測（docs に記載が無い）**:
  - [x] (1) ランチャーから起動したセッションが supervisor を立ち上げた場合に、後続の background セッションへ custom.env の値が波及するか（design §3(1) 注記） → **2026-10-20 実測: 波及する**（Windows・PS 版ランチャー・v2.1.303。測定中に auto-update で 2.1.304 になった。custom.env に `VERIFY_KIT_PROBE=from-launcher` を置き、一時プロジェクトの SessionStart hook で env を記録）。ランチャー経由の `claude --bg` が supervisor を立ち上げると、そのセッションにも、続けて素のシェルから同じディレクトリへ dispatch したセッションにも `from-launcher` と `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` が届き、dispatch 元に `VERIFY_KIT_PROBE=from-shell` を置いても `from-launcher` が使われた。逆に素のシェルが supervisor を立ち上げた後は、ランチャー経由の `claude --bg` でも両方とも未設定だった（列挙外の env は dispatch 元からは届かない）。auto-update による supervisor の自己再起動の後も env は変わらなかった。推定（起動順次第）どおりで、記述を実測に改め、波及の向きと優先を追記（`start_claude_code.*` 冒頭・`setup-environment.*`・§3 (1)・design §3 1.・§5 表）
  - [x] (2) 値を複数取るフラグ（`--add-dir` / `--mcp-config` / `--tools` / `--betas`）や値省略可のフラグ（`--resume` / `--worktree` / `--from-pr` / `--debug`）が OPTS の最後に並んだとき、`"$@"` 先頭のプロンプト文字列を値として取り込まないか（bash の連想配列は列挙順が不定） → **2026-10-19 実測: 取り込む**（`--worktree` 以外の 7 種で確認。`--` を挟めば防げる）。追加引数が全部非フラグのときだけ `--` を補う処理と bash 版の組立順ソートを `start_claude_code.{sh,ps1}` に実装（design §5.4）
  - [x] (3) Windows PowerShell 5.1 から `--agents` のインライン JSON を渡したとき `"` が保たれるか → **2026-10-19 実測: 5.1 は保たない**（ランチャー経由・直接とも全 `"` が落ち `{reviewer:{description:Reviews code,...}}` になる。`\"` でエスケープしても空白で引数が分割される）。pwsh 7.4 は保たれる。ネイティブ exe を引数記録用に作って測定。回避は pwsh 7 で起動（`option-settings.ps1.template` に注記）
  - [x] (4) hooks の `if: "Edit(...)"` が Write ツールの呼び出しにも一致するか（権限ルールの `Edit(...)` は Write も含めて照合されるが、hook の `if` については docs に明記が無い） → **2026-10-20 実測: 一致しない**（v2.1.303。PostToolUse・matcher `Edit|Write` に `if: "Edit(**/*.txt)"`・`if: "Write(**/*.txt)"`・`if` なしの 3 つを置き、Write で `.txt` を新規作成すると `Write(...)` と `if` なしだけが、Edit で書き換えると `Edit(...)` と `if` なしだけが動いた）。hook の `if` はツール名で区別されるため、`.claude/settings.json` が `Edit(...)` と `Write(...)` を別々に並べているのは必要（片方に寄せると、もう片方のツールの後の検査が動かない）

### 8-quater. Claude Code v2.1.310 追随（2026-10-24 調査・反映）

公式 docs 差分（LLMs リポ `df8be8b`→`049e3f4`、changelog 2.1.303〜2.1.310）をレール A〜E の SubAgent で調査・反映し、作業指示者の判断（2026-10-27）をレール F〜H で反映し、同日にレビュー工程（I = /code-review、J = /security-review）を行った（結論は本節と設計書に書き写してある）。

- [x] **実行モデル（レール C）**: 本ランチャーが `CLAUDE_CODE_PROCESS_WRAPPER` に登録するものではないことを再判定し、v2.1.310 時点の契約との対照表を design §5.2 に置いた（標準入力・絶対パス・3 回連続起動・ランチャー自身の引数は不適用か既に満たす）。**PS 版ランチャーの警告が stdout に出ていた**（PowerShell は別のプログラムから起動されると warning ストリームを stdout に書く。pwsh 7・5.1 とも実測）のを、`start_claude_code.ps1` が `setup-environment.ps1` の warning ストリームを stderr へ回す形で直した（bash 版は当初から stderr。design §5.5）。`start_claude_code.*` 冒頭に出力の約束と「`CLAUDE_CODE_PROCESS_WRAPPER` に登録しない」を、`setup-environment.*` 冒頭に同旨を追記。design §5 に起動環境からしか読まれない変数・ゲートウェイが background へ渡る条件、§5.5 に v2.1.305 以降の起動時警告（対話起動はデバッグログのみ）と `--add-dir` の UNC が黙って外れることを追記
- [x] **option-settings テンプレ（レール A。sh/ps1 対称・44 キーのまま。2026-10-27 の判断で `--debug-file` を加えて 45 キー〔W42-F-01〕）**: コメントのみの修正 12 件（基準版を v2.1.310 へ、`--autocompact` の使えない値の扱い、`--permission-mode` の `-p` 既定の根拠を docs に、`--permission-prompt-tool` の完全名、`--add-dir` のネットワークパスと同名 skill の呼び方〔v2.1.309〜〕、`--tools` と `ToolSearch`、`--worktree` の終了時の後始末、ultrareview の `--trust-workspace` 等）。`--debug-file` は作業指示者の判断（2026-10-27）でキーに加えた（W42-F-01。v2.1.305 以降、対話起動の起動時警告はデバッグログにしか出ないため、それを読む手段として）
- [x] **custom.env.template・setup-environment（レール B）**: `CLAUDE_CODE_FORK_SUBAGENT` の既定（v2.1.302〜全セッション）、`API_TIMEOUT_MS` の意味、`CLAUDE_CODE_AUTO_COMPACT_WINDOW` / `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` / `CLAUDE_CODE_WARN_{DISK,MEMORY}_FREE_GIB` の追加、テレメトリ節に `claude_code.safety_event`（v2.1.307〜）。§5 の 2026-10-18 追補と §6-bis 表を追随させた
- [x] **決定・反映（2026-10-27。W42-C-08 → W42-F-05）**: `--add-dir` に渡された `<Share>` が UNC のとき（v2.1.305 以降、Claude Code は対話起動では何も表示せずそのディレクトリを外して起動する）、ランチャーが option-settings の `--add-dir` の値だけを見て、`\\` / `//` で始まれば stderr に 1 行警告する（止めない。起動時引数は見ない）。design §5.5。判定は綴りだけで、`TEAM_OPTS` / `$TeamOpts` と `=` 形のキーは見ず（→ 2026-10-27 の判断 J-3 で `TEAM_OPTS` / `$TeamOpts` も対象に加えた。K-01。下の行）、ネットワークパスではない `\\wsl$` でも警告が出る。verify-kit は既存項目「ランチャー stdout / stderr の振り分け（スタブ）」の fixture を拡張（警告 3 → 4 行。期待値は PASS 22 のまま）。README 方法 B に同旨と、`claude` へ直接渡す場合は検査されないことを記した（W42-H-02）
- [x] **scripts（レール D）**: check-assets 3. の U 区分に `sandbox.allowNestedUserNamespaces`・`axScreenReader`、E 区分に `CLAUDE_AX_.*` と起動環境専用の変数（`CLAUDE_CODE_DISABLE_*_RM_*` 系 5 個・`CLAUDE_CODE_WARN_{DISK,MEMORY}_FREE_GIB`）を追加し、E の WARN 文言から `~/.claude/settings.json` の推奨を外した（OS の環境変数 / managed）。照合されない権限ルール（パス付きの `Write` / `NotebookEdit` / `MultiEdit` / `Glob`）の WARN を新設。verify-kit に「ランチャー stdout / stderr の振り分け（スタブ）」を新設し、期待値は PASS 21 → 22。Week 41 で見送った publish-plugin の D-19 / D-20 / D-23 は前提が変わっていないので再提案しない
- [x] **配布文書（レール E）**: `.claude/CLAUDE.md` と rule で、`Edit(...)` の deny が止める範囲を「Bash のリダイレクト先と、Claude Code が認識するファイル操作コマンド」に限定し、v2.1.309 未満ではサブシェルを含む一部のリダイレクトが止まらなかったことを明記。orchestrate SKILL.md と `.claude/CLAUDE.md` に、Sub-agent が既定で background で動き完了通知で結果が届くことを追記。README に同名 skill の `/<フォルダ名>:<名前>`（v2.1.309〜）・U 区分の例示 2 キー・rules の 1 ファイル上限・mod による deny の上書きを追記。Windows の hook fail-open 修正（2.1.309・2.1.310）は exec form のキットには関係しない
- [x] **作業指示者の判断 14 件（2026-10-27）**: 採用 10 件・現状維持 4 件。採用: #1 A-13 (a) → F-01、#3 B-08 (a)（推奨案は (b) だったが、作業指示者が LiteLLM のゲートウェイ利用者であるため）→ F-02、#4 B-09 (a) → F-03、#5 custom.env.template L82 (a) → F-04、#6 C-08 (a) → F-05、#7 D-13 (a) の改変（マージンを持たせたしきい値。同日の指示で 32,000 文字超 FAIL・200 行超 WARN・`.claude/CLAUDE.md` も対象・rules はサブディレクトリを含む）→ G-01〜G-04、#10 E-17 (a) → H-01、#11 E-18 (a) → H-02、#12 E-19 (a) → H-03、#14 E-09 の展開 (a) → H-04。現状維持: #2 B-07 (c)、#8 D-14 (a)、#9 D-15 (b)、#13 E-20 (a)
- [x] **ランチャー・テンプレ・setup-environment の判断反映（2026-10-27。W42-F-01〜F-04）**: F-01 は上のテンプレの行のとおり（45 キー）。F-02 は setup-environment 両版のゲートウェイ節に、Anthropic Messages 形式（LiteLLM 等）の `ANTHROPIC_BASE_URL` の例と tool search（v2.1.304〜既定 on・v2.1.305〜 400 / 422 なら自動で再試行・転送できないゲートウェイなら `ENABLE_TOOL_SEARCH=false`）を追加し、認証値は分類A（OS の環境変数。custom.env に書くと読み飛ばされる）と明記。§6-bis に `ENABLE_TOOL_SEARCH`（B）の行を足し、`ANTHROPIC_BASE_URL` の行に追記。F-03 は OTel の例に `OTEL_METRICS_EXPORTER=otlp`・`OTEL_LOGS_EXPORTER=otlp`・`OTEL_EXPORTER_OTLP_PROTOCOL=grpc`（コメントアウト）を追加（例をそのまま有効化しても送られなかった既存の穴。W42 の差分ではない）。F-04 は custom.env.template L82 の散文を、`#` を外しても設定行にならない形に言い換えた（既存の問題）
- [x] **check-assets の rules / CLAUDE.md の大きさ（2026-10-27。W42-D-13 → W42-G-01〜04）**: 2-g を新設。対象は `.claude/rules/` 配下の `*.md`（サブディレクトリを含む。`.` で始まるディレクトリの中は除く）と `.claude/CLAUDE.md`、32,000 文字超で FAIL・200 行超で WARN（両方なら FAIL だけ）。数え方はバイト単位（UTF-8 の継続バイト以外を数える＝コードポイント。BOM は除く）で両版一致。verify-kit は 3 ケース追加（14 → 17）と expect の否定タグ、期待値は 22 のまま
- [x] **README・rule の判断反映（2026-10-27。W42-H-01〜H-04）**: H-01 README の推奨版を v2.1.299 → v2.1.309（最低版 v2.1.295 は据え置き。実機はさらに新しいが、最新化はランチャースクリプト初版の完成後に改めて行う）。H-02 方法 B に UNC の注意とランチャーの警告の範囲。H-03 check-assets の検査項目一覧に 2-g と 3. を足し、「構成」の rules の大きさの注記を 2-g に合わせた。H-04 rule の「原本への `Edit` / `Write` は `permissions.deny` で拒否される」に、mod による deny の上書きの限定を 1 句（`.claude/CLAUDE.md` には足さない）
- [x] **レビュー工程（2026-10-27。I = /code-review high → medium、J = /security-review）**: I は 1 周目の候補 10 件のうち妥当 3 件（照合されない権限ルールの WARN が改行入りのルールで両版で割れる・2-g で読めないファイルの扱いが両版で割れる・`verify-kit.sh` の未使用変数）を直し、既知の限界 2 件（UNC の判定が `\\?\` / `\\.\` でも警告を出すこと・`TEAM_OPTS` / `$TeamOpts` と「=」形のキーを見ないこと）を design §5.5 と両ランチャーのコメントに記録した（挙動は不変）。2 周目の候補 7 件のうち、1 周目の修正の退行・不完全さ 3 件（expect の断片・改行の表記を `<CR>` / `<LF>` に・bash のコメント）を直した。J は HIGH / MEDIUM 0 件で、基準未満の 7 件のうち 1 件（env のキー名が改行で終わると bash 版だけ照合されない権限ルールの行が消える）をメインの判断で直した（E / EC の一覧に出すキーの CR / LF も `<CR>` / `<LF>` に。分類は生のキーのまま）。verify-kit は両版 PASS 22 / FAIL 0 / SKIP 0 のまま（check-assets の fixture は 17 ケースのまま、`settings-wrule.json` に 2 要素を追加）
- [x] **F-02 の確定（2026-10-27。作業指示者の回答）**: `ANTHROPIC_AUTH_TOKEN`（と `ANTHROPIC_API_KEY`）は custom.env を含むどのファイルにも書かず OS の環境変数で設定する。`ANTHROPIC_CUSTOM_HEADERS` は値次第で、認証情報・個人情報を載せるなら同じ扱い（custom.env では名前で読み飛ばされる）。setup-environment 両版のゲートウェイ節（両版同文）と §6-bis の 2 行をこれに合わせた（I）
- [x] **レビューで派生した要判断のうち J-3・J-4 の反映（2026-10-27。作業指示者の判断はどちらも推奨 (b)。K-01・K-02）**: J-3 → K-01: 両ランチャーの UNC の事前検査を `TEAM_OPTS` / `$TeamOpts` の `--add-dir` にも広げた（同じ判定・同じ本文で、警告文の先頭に出どころ〔`option-settings` / `start_claude_code のチーム統制（TEAM_OPTS / $TeamOpts）`〕を出す。止めない・起動時引数と `=` 形のキーは引き続き見ない）。verify-kit の振り分け項目の fixture に `team` 行（probe が一時ツリーのランチャーの定義の行の直後へ差し込む）を足し、警告 4 → 5 行（項目数は 22 のまま）。design §5.5・README 方法 B の範囲の記述を追随。J-4 → K-02: check-assets 2-g で読み取りに失敗したファイル（ロック・権限・I/O エラー）を件数に入れず、ファイルごとに「未検査」の WARN を 1 行出す（両版同文。FAIL にはしない・終了コードは不変・他のファイルの PASS 行は読めた件数で別に出す）。fixture では再現しにくいので、Windows で実際にロック（`FileShare.None`）と ACL の読み取り拒否（`icacls /deny`）を掛けて bash / pwsh 7 / 5.1 の WARN の文言と rc 0 の一致を確かめた。README の 2-g の説明に追記
- [ ] **レビューで派生した要判断（未決・推奨は現状維持）**: J-1 2-g の文字数の単位（推奨 (a) 現状のコードポイント）、J-2 PS 版ランチャーの警告の書き方（推奨 (a) 現状の `[Console]::Error`）、J-5 UTF-8 BOM 判定の共通化（推奨 (a) 見送り）、JS-1 check-assets の表示に出る制御文字の置き換え（推奨 (a) 現状。行うなら Week 41 の S6 と一緒に）。J-3・J-4 は 2026-10-27 に判断・反映済み（上の行）

### 8-quinquies. Claude Code 追随の記録

範囲: changelog 2.1.311〜2.1.316（2.1.313・2.1.315 は欠番）、LLMs リポ（公式 docs の複製）`049e3f4`（2026-10-24）→ `23292d1`（2026-11-02）、2026-11-03 に調査・反映（W44。手順は `docs/launcher/claude-code-intake.md`）。

- [x] **changelog の仕分け**: 305 項目。手順書 5. の既定で対象外にしたもの 85（札〔`[VSCode]`・`[Cloud sessions]`・`[Claude Tag]`・`[Code Review]`・`[Remote Control]`〕69、Claude apps gateway・Self-hosted runner 16〔`self-hosted-runner` のオプションの追加を含む〕）。そのうち付表 A の語を含む 28 項目も読んだが、語は Claude apps gateway（LLM ゲートウェイではない）・Claude Tag やクラウドの管理画面の settings・VS Code 拡張の hooks / `DISABLE_TELEMETRY` の扱いで、キットの対象に当たらない。残る 220 項目を読み、下の反映・要確認・再評価に振り分けた。ほかは端末の表示・vim モード・MCP の認証・クラウド・Bedrock / Foundry のモデルの選び直し等で、付表 A の語に当たらない。キットの記述をより正しくする方向の修正（2.1.314 の `--setting-sources` で外した settings が一部の設定を供給していた修正、`claude -p` が起動に失敗すると exit 0 だった修正、`tool_reference` を拒否するゲートウェイでの再送の記憶）と、記述と一致する修正（2.1.311 の `claude daemon stop --any` の案内）は、記述の変更不要として記録だけにした。
- [x] **レール A（option-settings テンプレ）**: テンプレの変更なし（cli-reference の表は差分なし。キーの追加・削除なし）。W44-A-01: 本書 §4 を v2.1.316 の cli-reference の全 80 フラグの現行の一覧に書き直し、v2.1.302 時点の一覧と追補は「過去の追補（記録。原文のまま）」に残した。
- [x] **レール B（custom.env.template・setup-environment）**: W44-B-01: custom.env.template の effort 節の `auto` の注記を「auto か unset は effort を送らず API の既定に任せる」に改めた（env-vars の `CLAUDE_CODE_EFFORT_LEVEL`・model-config「Send no effort level」。`unset` は値としての文字列）。W44-B-02: `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` に「background セッション（agent view）は止まらない。それも止めるなら `CLAUDE_CODE_DISABLE_AGENT_VIEW` も 1」の 1 行を足した（env-vars）。W44-B-03: 本書 §5 の冒頭に現行の一覧の表を置き、従来の段落は「過去の追補（記録。原文のまま）」に残した。setup-environment 両版は変更なし。
- [x] **レール C（実行モデル）**: W44-C-01: design §5.2 の確認時点を 2026-11-03・v2.1.316 の docs（corporate-launcher）に改めた（`CLAUDE_CODE_PROCESS_WRAPPER` は Windows では引き続き無視される）。本書 §3 (1) にも再確認の日付を足した。W44-C-02: design §5.1.2 の表に「`claude-cli://` の deep link で開いたセッション」の行を background 起動（ランチャーを通らない）として足した（corporate-launcher「Processes that start outside the launcher」の deep link の項が、v2.1.316 の docs で「deep link で開いたセッションはランチャー無しで新しい端末に開く」に変わった。5.1.1 の原則どおりの分類）。W44-C-03: design §5.1.3・§5.3・§5.4・§5.5 の確認時点を 2026-11-03・v2.1.316 の docs で確かめた形に改めた（依存する節は差分なし。§5.4.1 の型は `claude --help` 由来で docs では確かめられないことを明記）。`start_claude_code.ps1` の冒頭コメントは変更なし（corporate-launcher「The launcher contract」・agent-view「Settings and provider」は差分なし）。agent-view で background へ送ったときの dynamic workflow の扱い（Claude が background セッションで再起動したときだけ続く）が変わったが、design §5.1.2 の dynamic workflow の行（セッションを終了すると run は続かない）とは矛盾しないので変更なし。
- [x] **レール D（scripts）**: W44-D-01: `scripts/check-assets.d/settings-scope.txt` の E に `CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS` を足した（settings-reference「Variables Claude Code ignores in `env`」に追加。起動環境からしか読まれない。docs の並びどおり `CLAUDE_CODE_DISABLE_*_RM_*` と `CLAUDE_CODE_WARN_*_FREE_GIB` の間）。E 節のコメントと、U / M / E / W の各節の確認時点を 2026-11-03・v2.1.316 に改めた（表の Scope 列と permissions の W の節は差分なし）。W44-D-02: check-assets 両版の E の WARN の文言で「起動環境からしか読まれない」変数を列挙している部分に同じ変数を足した（両版同文。`check-assets.expect` の断片はこの部分を含まないので不変）。verify-kit の期待値は不変。
- [x] **レール E（配布文書・ルート README）**: W44-E-01: `.claude/launcher/README.md` 付録 B「--model の既定とエイリアス」のアカウント種別に Ultra を足した（model-config・permission-modes・env-vars のプランの列挙に Ultra が加わった。Ultra は旧 Max 20x の新しい名前〔feature-availability〕）。W44-E-02: 付録 A の版の行を v2.1.316 時点に上げた（テンプレ 3 本と付録 B の依存先〔cli-reference・permission-modes・model-config・env-vars・errors・skills・agent-view・tools-reference・worktrees・agent-teams〕の v2.1.310 からの差分を確かめ、要るものは W44-B-01・B-02・E-01 で反映した）。配布文書（`.claude/CLAUDE.md`・rules・skills）は変更なし（付表 A の語に関わる差分なし。sub-agents から入れ子の旧既定の注記が消えたが、現行の既定〔主会話の下 3 層〕は同じ）。ルート README の推奨版は §8-quater の H-01 で保留中のまま。
- [x] **SH-DEFER**: なし（凍結中の `.sh` 3 本に要る変更が出なかった。`.ps1` 側のランチャー資産も変更していない）。
- **差分なしを確かめたページと節**: cli-reference（全体）、agent-view「Settings and provider」「LLM gateway」「Prompts that contain `--bg`」と「What carries over when you background」の構成フラグの列挙、network-config「Apply network settings to background agents」、errors「Configuration warnings」の節全体（「Working directory is a network path」を含む）、corporate-launcher「What the launcher covers」の Windows の記述と「The launcher contract」、settings-reference の表の Scope 列、permissions「`Write(path)`, `NotebookEdit(path)`, and `Glob(path)` rules never match」、permission-modes「Which mode a session starts in」（プランに Ultra が加わっただけ）、skills「Load skills from a directory outside the project」、agent-teams（teammate への環境変数の引き継ぎの記載は引き続き無い）、llm-gateway・gateways・microsoft-foundry（全体）、custom.env.template の 26 キーのうち 24 の env-vars の行。permissions の「`.claude/settings.local.json` は git リポジトリのルートから読む（Windows 等を除く）」は v2.1.310 の docs にもある記述で、v2.1.211 より前の経緯の文が消えて見出しが付いただけ（キットへの影響なし）。
- [ ] **要実測**: R9 ゲートウェイ変数の background への到達（design §5.1.3 の「dispatch 元シェルの env」の行の条件が実機で成り立つか）。最新版と LiteLLM で別途実測する予定。
- [ ] **要確認（changelog と docs の食い違い・docs 未反映。本文は docs のまま。要実測にするかは作業指示者の判断）**: (1) changelog 2.1.312「`claude_code.safety_event` を送らなくなった」↔ monitoring-usage は記載のまま（setup-environment 両版のテレメトリ節のコメントは docs に従い不変）。(2) changelog 2.1.312「サブエージェントの `autoCompactWindow` が `CLAUDE_CODE_AUTO_COMPACT_WINDOW` の窓を下げられる」↔ sub-agents は「環境変数を設定するとフィールドは効かない」のまま（キットの `code-reviewer` は `autoCompactWindow` を使わない）。(3) changelog 2.1.314「idle compaction をテレメトリ無効のサブスクリプションと、1 時間のプロンプトキャッシュが有効なら Bedrock・Vertex・Foundry・LLM ゲートウェイでも行う」↔ settings-reference `idleCompaction` の条件に「feature flag を取得できること」があり、env-vars は 3P と `DISABLE_TELEMETRY` では feature flag を取得しないと書く（setup-environment 両版の `DISABLE_TELEMETRY` の注記〔アイドル時コンパクションが使えなくなる〕と custom.env.template のコンテキスト節に関わる）。(4) changelog 2.1.311「設定ファイルの権限ルールの起動時警告を、ルールが変わるまで利用者ごとに 1 回だけ出す」↔ errors「Configuration warnings」は不変（design §5.5.2・README 付録 B「起動時の警告を読む」に関わる）。(5) `CLAUDE_CODE_EFFORT_LEVEL=auto` で実際の effort が変わるか（API の既定と Claude Code の既定〔Opus 5.5 は medium〕が同じか）は docs から決められない（docs は `/effort status` の表示で effort を送っていないことを確かめる方法を示す）。
- [ ] **未決（issue #4）**: I-1〜I-3（収録基準。2026-11-03 起票。裁定待ち）。I-3 に関わる候補は §5 の表の「未（I-3 の裁定後）」の行。I-1 のデータの補正: `--append-subagent-system-prompt` は docs では `-p` のときだけ効くので、I-1 の「対話起動で使えて理由が書かれていない 9」ではなく print / stream 専用に入る（print / stream 専用 9・理由が書かれていない 8 になる。§4 の表）。W44 で出た判断事項（要確認 (1)〜(4) を要実測にするか、custom.env.template に idle compaction の条件を書くか、README 付録 B に `worktree.sparsePaths` へ `.claude` を含める注意と `--model` の既定の Claude Platform on AWS を足すか）は issue #4 に追記する。
- [ ] **changelog にあって docs に無いもの（docs 掲載後に再評価）**: `CLAUDE_CODE_SUBAGENT_EFFORT`（2.1.316。サブエージェントの effort の既定。custom.env.template のサブエージェント節の候補）、`CLAUDE_CODE_DISABLE_ULTRATHINK`（2.1.316）、`CLAUDE_CODE_DISABLE_LOOPED_CROSS_CERT_DROP`（2.1.316。プロキシ・社内 CA まわりの候補）、`CLAUDE_CODE_MODEL_CATALOG`（2.1.311。3P で署名付きのモデル設定を downloads.claude.ai から読むのを止める。setup-environment の分類B〔3P〕の候補）、`permissions.blockWritesOutsideWorkingDirectories`（2.1.314。settings-reference に無く Scope が不明。`Any file` 以外なら settings-scope.txt の u / m の候補）。
- [x] **検証**: check-assets 両版 FAIL 0 / WARN 5（2-h PASS。両版の出力一致）、verify-kit 両版 PASS 23 / FAIL 0 / SKIP 0 / FROZEN 1。

---
変更履歴: 初版（実装前プレップ・2026-06-30）。design 確定版＋docs（cli-reference/env-vars v2.1 系）インベントリ反映。／2026-07-05 復帰セッションで §6-bis（判定木・再マップ・確定事項）追記、§7 を実リポ・UTF-8 BOM 方針・既存 .gitignore 実態に更新、§8 実装完了状況を追記。／同日追補: 判定木の分類ラベルを **分類C-Y→分類C、分類C-N→分類D** に改称（本文・実装スクリプト・メモリとも全置換、動作は不変）。／同日: research-by-cc（gitignore済みworkspace）からC-BDK `.claude/launcher/`へ本設計書2点をコピーし、branch `feat/launcher-scripts`（base develop）としてPR化。／同日 F1 修正: `develop` 起点でブランチを切った副作用で `.gitignore` の launcher 安全網（e233907・chore/groom-as-share のみ）が欠落していたため、同等の除外行を本ブランチへ再追加し §8 の記述を訂正。／同日 F2 修正: 本 doc と `launcher-scripts-design.md` を `.claude/launcher/` → `docs/launcher/` へ移設。`publish-share` が `.claude/` を丸ごと archive して C-BDC/C-BCP へ配布する仕様上、内部設計 doc が全消費者へ漏れるのを構造的に防ぐため（`docs/` は配布対象外・C-BDK 内では追跡継続）。／**2026-07-12（レーンB）**: Fable 5 × 3 観点クロスレビュー（2026-07-07）の指摘を実装反映。本書を**設計書の正本**として規定（IM-8）。CR-1（配布先セーフティネットの payload 搬送）・IM-1（撤回済み「custom.env＝秘匿格納」の残存）・IM-2（publish 経路誤記＝2 レール）を訂正し、§8-bis に反映状況を追加。CR-2 / IM-9 / IM-10 は PR#1（`chore/groom-as-share`）マージ後に実施する旨を明記。／**2026-07-12（Round 3 レビュー反映）**: (1) §8-bis の CR-2 を**完了**へ更新 ―― 「PR#1 マージ後に実装」としていたが PR#1 側で先行実装済みであり、**正本が存在しないタスクを指していた**（R3-H）。(2) §6 #2 に残っていた撤回済み前提の設問「秘匿系は全て custom.env でよいか」に撤回注記を追加（R3-S-3）。(3) 指摘 ID が巡回ごとに振り直される旨を注記（Round 1 の「IM-8」と Round 2 の「IM-8」は別物）。／**2026-07-12（マージ前セルフレビュー）**: 本変更履歴に Round 3 の反映が未記録だった点を補正（横断セルフレビュー F7）。／**2026-10-19**: §8-ter の要実測を 3 項目に分け、(2)（位置引数のプロンプトの取り込み）を実測して完了（design §5-3・ランチャーの `--` 補完と bash 版の組立順ソート）。／**2026-10-19（セキュリティレビュー参考所見）**: §3 (2) に、custom.env のランチャー内部変数名の読み飛ばし（bash 版だけで分類A の完全一致判定が無効化できた）と、分類A の名前パターン追加（`ANTHROPIC_CUSTOM_HEADERS`・名前全体・`SECRET_*`・`*_PASS` / `*_PASSWD` / `*_PWD` / `*_CONNECTION_STRING`）を追記。§6-bis 表に `ANTHROPIC_CUSTOM_HEADERS` を追加。／**2026-10-20**: §8-ter の要実測 (1)（supervisor 経由の env の波及）を実測して完了し、(4)（hooks の `if: "Edit(...)"` と Write）を追加して実測。(1) の結果に合わせて §3 (1) の記述、`start_claude_code.*` 冒頭と `setup-environment.*` の注記、design §3 1.・§5 表を改めた。／**2026-10-24**: §8-quater を新設（v2.1.310 追随。レール A〜C）。§3 (1) に「本ランチャーは `CLAUDE_CODE_PROCESS_WRAPPER` に登録するものではない」と「ランチャーの出力は stderr だけ」（PS 版の修正）を追記。§4 の `--permission-mode` 注記に docs の根拠と `-p` の拒否条件を追記。§5 の 2026-10-18 追補のうち fork mode の既定（v2.1.302〜全セッション）を更新し、`CLAUDE_CODE_AUTO_MODE_MODEL` の再評価を「採用しない」で閉じた。§6-bis の表にレール B が custom.env.template へ足したキーを追記し、分類B の managed 移設に「起動環境からしか読まれない変数は移せない」を補った。／**2026-10-27**: 作業指示者の判断（W42 の 14 件）を反映。§8-ter・§8-quater の「44 キー」に `--debug-file` を加えた 45 キーを併記し（W42-F-01）、§6-bis に `ENABLE_TOOL_SEARCH`（B）の行を追加して `ANTHROPIC_BASE_URL` の行に追記した（W42-F-02）。§8-quater の導入文をレール A〜H に改め、UNC の行を「決定・反映」にして範囲の限界を補い、レール D・E の結果、判断 14 件の結果、W42-F-02〜F-04・G-01〜G-04・H-01〜H-04 の反映を追記した。／**2026-10-27（レビュー工程）**: /code-review（I）・/security-review（J）の結果を反映。§6-bis の `ANTHROPIC_BASE_URL` の行と分類A の一覧の行に、`ANTHROPIC_CUSTOM_HEADERS` は値次第（認証情報・個人情報を載せるなら A）で、検知は名前で行うので値によらず読み飛ばされる、を書き足した（F-02 の確定に追随。I）。§8-quater の導入文にレビュー工程を加え、レビューの結果・F-02 の確定・未決の要判断 6 件（J-1〜J-5・JS-1）の行を追記した。／**2026-10-27（要判断 J-3・J-4 の反映）**: 作業指示者の判断（どちらも推奨 (b)）に従い、J-3（UNC の事前検査を `TEAM_OPTS` / `$TeamOpts` にも広げる。K-01）と J-4（check-assets 2-g の読み取りの失敗を「未検査」の WARN にする。K-02）を反映した。§8-quater の未決の行から J-3・J-4 を外して反映済みの行に移し、UNC の決定の行に J-3 で広げたことを注記した。／**2026-11-02**: §3 (4) の「公式推奨デフォルトを持つものは設定済み＆有効化」に、実装では採っていない（テンプレ 3 本とも全行コメントアウト）旨の注記を追加（設計書 §3 の整理で判明）。／**2026-11-02**: 設計書の小節番号の記法変更（§5-N → §5.N）に合わせ、本文の design §5-N の参照を §5.N に改めた（本行より前の履歴の原文は不変）。／**2026-11-03**: 設計書 §5 の校正（5.1 の新設と旧 5.1〜5.4 の繰り下げ）に合わせ、本文の design §5.N の参照を新しい番号に改めた（§3 (1)・§4・§5・§6-bis・§8-ter・§8-quater。履歴の原文は不変）。／**2026-11-03**: Claude Code の仕様変更の取り込み手順書 `docs/launcher/claude-code-intake.md` を新設し、冒頭の注記と §8 の直前に案内を、§8 の直前に追随記録の型（次の記録から見出しを通し番号にする）を置いた。§4・§5 の見出しから基準の版・日付と docs の出典（§4「docs 2026-10-18 / v2.1.302 時点」、§5「docs env-vars より」）を外し、本文の 1 行目に「基準: …」として移した（一覧の中身は不変。現行の一覧への書き直しは次の追随で行う）。追跡されない個人メモ・報告書の名指しを外した: §5 の bearer ゲートウェイトークンの注記にあった個人メモ 2 件の参照は、要点（専用 helper が無い・機微な値は OS の環境変数で供給する方針〔§6-bis の分類A〕）を本文に残して外し、§5 のフル一覧の参照（日本語版のファイル名）は docs の env-vars の URL に改め、§8-quater の未決の行の末尾にあった非追跡の報告書の節への参照は外した（要判断 4 件の内容は同じ行に書いてある）。／**2026-11-03（W44）**: Claude Code v2.1.311〜316 の追随を §8-quinquies として記録した（追随記録の型による最初の記録）。§4 を v2.1.316 の cli-reference の全 80 フラグの現行の一覧（テンプレ・付録 A の理由・備考）に書き直し、従来の一覧・注記・追補は「過去の追補（記録。原文のまま）」の下に残した。§5 の冒頭に現行の一覧の表（custom.env.template の全キー・setup-environment の固定 env の候補・v2.1.302 以降に env-vars に増えた変数）を置き、従来の段落は同じく「過去の追補（記録。原文のまま）」の下に残した。§4・§5 の「基準:」の行を v2.1.316 に改めた。§3 (1) の `CLAUDE_CODE_PROCESS_WRAPPER` の判定に 2026-11-03 の再確認を足した。
