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
- **env のローカルスコープ性**: ランチャープロセス内で設定した env は、子プロセスとして起動する `claude` にのみ継承され、OS env や他アプリに影響しない（bash の export / PS の `$env:` とも本質的にプロセスローカル）。⚠ **foreground 起動にのみ届く**。background/agent-view セッションは ambient シェル env でなくディレクトリ設定から構成を読む（[[reference_cc_background_session_config_source]]）＝この経路では custom.env は届かない旨を冒頭コメントに明記。

### (2) setup-environment.{sh,ps1}
- custom.env をロード（KEY=VALUE 形式を export / `$env:` 設定）。
- その後で**チーム固定 env を後勝ちで上書き**（利用者が custom.env に書いても固定値を保証）。固定対象は §6-2 で確定。
- 秘匿値はハードコードしない（固定 env は非秘匿のものだけ）。**機微（分類A）は custom.env にも書かない** ―― OS の環境変数で供給する（§6-bis の判定木で確定）。`setup-environment` は分類A の既知キーを custom.env 内に見つけたら**読み込まずに警告**する。

### (3) option-settings.{sh,ps1}.template
- 連想配列（bash: `declare -A OPTS=( [--model]=... )` / PS: `$Opts = @{ '--model' = ... }`）で起動オプションを列挙。不要行はコメントアウトで無効化。
- 公式デフォルト推奨値はコメントで明示。CLI フラグ候補は §4。

### (4) custom.env.template
- `KEY=VALUE` 列挙＋コメント。利用者が値設定する env の全量（curated）。候補は §5。
- 公式推奨デフォルトを持つものは設定済み＆有効化。

## 4. CLI 起動オプション インベントリ（option-settings.template 候補・docs v2.1 系より）

**ランチャーで露出する有力候補（curated）**:
`--model` / `--fallback-model` / `--add-dir` / `--settings` / `--setting-sources` / `--mcp-config` / `--strict-mcp-config` / `--permission-mode` / `--agents` / `--agent` / `--append-system-prompt-file` / `--debug` / `--ide` / `--verbose`

**全フラグ（参考・docs 抽出）**:
`--add-dir --agent --agents --append-system-prompt(-file) --betas --continue --debug --disable-slash-commands --effort --fallback-model --fork-session --from-pr --ide --include-partial-messages --input-format --max-budget-usd --max-turns --mcp-config --model --output-format --permission-mode --permission-prompt-tool --plugin-dir --plugin-url --print --resume --session-id --setting-sources --settings --sso --strict-mcp-config --system-prompt(-file) --teammate-mode --tools --verbose --version --worktree` ほか（`--dangerously-*` 系は既定で露出しない方針を推奨）。

## 5. 環境変数 インベントリ（custom.env.template / 固定 env 候補・docs env-vars より）

> **⚠ 本節の分類は §6-bis の判定木で置き換わっている**。下記の「多くは秘匿＝custom.env」という
> 初期案は**撤回済み**。機微（分類A）は custom.env に書かず OS 環境変数で供給する。
> 以下はインベントリ（どんな env があるか）としてのみ読むこと。

カテゴリ分類（フル一覧は docs `ja/env-vars.md`。ここでは launcher 関連を抜粋）:

- **プロバイダ/認証（大半が分類A＝機微。custom.env ではなく OS 環境変数で供給）**: `ANTHROPIC_API_KEY` `ANTHROPIC_AUTH_TOKEN` `ANTHROPIC_BASE_URL` `ANTHROPIC_MODEL` `ANTHROPIC_SMALL_FAST_MODEL` / Bedrock: `CLAUDE_CODE_USE_BEDROCK` `AWS_BEARER_TOKEN_BEDROCK` `ANTHROPIC_BEDROCK_BASE_URL` / Vertex: `CLAUDE_CODE_USE_VERTEX` `ANTHROPIC_VERTEX_PROJECT_ID` `CLAUDE_CODE_SKIP_VERTEX_AUTH` / OAuth(SSO・**今回不使用**): `CLAUDE_CODE_OAUTH_TOKEN` `CLAUDE_CODE_OAUTH_REFRESH_TOKEN`
  - ※ bearer ゲートウェイトークンには専用 helper が無い（[[reference_cc_credential_handling_mechanisms]] の gap）。**だからといって custom.env に置いてよいわけではない**（当初はそう書いていたが §6-bis で撤回）。helper が無い以上、供給手段は **OS の環境変数**となる。`setup-environment` は `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `AWS_BEARER_TOKEN_BEDROCK` 等を custom.env 内に見つけたら、**読み込まずに警告**する（規律を機構で担保）。[[user_env_secret_handling_stance]] と整合。
  - ※ プロバイダ選択（Bedrock / Vertex）を有効化すると **Advisor / Fast mode / Channels / Server-managed settings が使えなくなる**（公式 docs「CLI capabilities that vary by provider」「Admin and analytics」）。分類B の出口として想定していた server-managed settings も 3P では不可のため、代替は MDM 配布のローカル managed-settings.json となる。
- **挙動・チーム統制候補（固定 env になりうる＝非秘匿）**: `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`（キットが依存）/ `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`（自前 git skill 採用時）/ `MAX_THINKING_TOKENS` / `CLAUDE_CODE_SUBAGENT_MODEL` / `BASH_DEFAULT_TIMEOUT_MS` `BASH_MAX_TIMEOUT_MS` / `MCP_TIMEOUT` `MCP_TOOL_TIMEOUT`
- **プロキシ/テレメトリ（環境依存・任意）**: `HTTP_PROXY` `HTTPS_PROXY` `NO_PROXY` / `CLAUDE_CODE_ENABLE_TELEMETRY` `OTEL_*` / `DISABLE_TELEMETRY` `DISABLE_ERROR_REPORTING`

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
- 分類B は「暫定 C」として当面 `setup-environment` / `start_claude_code` に置くが、**将来 managed スコープへ移設予定**である旨をコメントで明記する。
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
| `ANTHROPIC_MODEL` / `ANTHROPIC_SMALL_FAST_MODEL` | **D** | custom.env（※ `--model` と重複＝原則 option-settings 側） | |
| `CLAUDE_CODE_SUBAGENT_MODEL` / `MAX_THINKING_TOKENS` | **D** | custom.env | 個人選好 |
| `BASH_DEFAULT_TIMEOUT_MS` / `BASH_MAX_TIMEOUT_MS` / `MCP_TIMEOUT` / `MCP_TOOL_TIMEOUT` | **D** | custom.env | 環境依存 |

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

---
変更履歴: 初版（実装前プレップ・2026-06-30）。design 確定版＋docs（cli-reference/env-vars v2.1 系）インベントリ反映。／2026-07-05 復帰セッションで §6-bis（判定木・再マップ・確定事項）追記、§7 を実リポ・UTF-8 BOM 方針・既存 .gitignore 実態に更新、§8 実装完了状況を追記。／同日追補: 判定木の分類ラベルを **分類C-Y→分類C、分類C-N→分類D** に改称（本文・実装スクリプト・メモリとも全置換、動作は不変）。／同日: research-by-cc（gitignore済みworkspace）からC-BDK `.claude/launcher/`へ本設計書2点をコピーし、branch `feat/launcher-scripts`（base develop）としてPR化。／同日 F1 修正: `develop` 起点でブランチを切った副作用で `.gitignore` の launcher 安全網（e233907・chore/groom-as-share のみ）が欠落していたため、同等の除外行を本ブランチへ再追加し §8 の記述を訂正。／同日 F2 修正: 本 doc と `launcher-scripts-design.md` を `.claude/launcher/` → `docs/launcher/` へ移設。`publish-share` が `.claude/` を丸ごと archive して C-BDC/C-BCP へ配布する仕様上、内部設計 doc が全消費者へ漏れるのを構造的に防ぐため（`docs/` は配布対象外・C-BDK 内では追跡継続）。／**2026-07-12（レーンB）**: Fable 5 × 3 観点クロスレビュー（2026-07-07）の指摘を実装反映。本書を**設計書の正本**として規定（IM-8）。CR-1（配布先セーフティネットの payload 搬送）・IM-1（撤回済み「custom.env＝秘匿格納」の残存）・IM-2（publish 経路誤記＝2 レール）を訂正し、§8-bis に反映状況を追加。CR-2 / IM-9 / IM-10 は PR#1（`chore/groom-as-share`）マージ後に実施する旨を明記。／**2026-07-12（Round 3 レビュー反映）**: (1) §8-bis の CR-2 を**完了**へ更新 ―― 「PR#1 マージ後に実装」としていたが PR#1 側で先行実装済みであり、**正本が存在しないタスクを指していた**（R3-H）。(2) §6 #2 に残っていた撤回済み前提の設問「秘匿系は全て custom.env でよいか」に撤回注記を追加（R3-S-3）。(3) 指摘 ID が巡回ごとに振り直される旨を注記（Round 1 の「IM-8」と Round 2 の「IM-8」は別物）。／**2026-07-12（マージ前セルフレビュー）**: 本変更履歴に Round 3 の反映が未記録だった点を補正（横断セルフレビュー F7）。
