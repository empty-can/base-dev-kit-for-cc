# Claude Code の仕様変更を取り込む手順（週次追随）

Claude Code の新しい版で changelog と公式 docs に入った変更を、キットのランチャー資産と関連文書へ取り込むための手順。対象は 1. のファイルと文書で、前回の追随の記録を入力にして範囲を決め（2.）、changelog と docs の差分を仕分けて反映し（3.〜5.）、検証して（6.）、結果を実装計画 `docs/launcher/launcher-implementation-plan.md` の追随記録と、設計書の本文を変えたときは別紙 `docs/launcher/【別紙】launcher-scripts-design変更履歴.md` に残す（7.）。開発リポジトリ専用の文書で、配布されない（`docs/` は payload に乗らない）。

## 1. 対象

- ランチャー資産: `start_claude_code.ps1`（リポジトリのルート）・`.claude/launcher/setup-environment.ps1`・テンプレ 3 本（`.claude/launcher/option-settings.ps1.template`・`.claude/launcher/option-settings.sh.template`・`.claude/launcher/custom.env.template`。sh 版は下の凍結の対象）
- `.claude/launcher/README.md`（付録 A の版の行が、テンプレ 3 本と付録 B の基準の版）
- check-assets の表 `scripts/check-assets.d/settings-scope.txt`（project では効かない settings のキー〔u / m〕・env〔e〕と、照合されない権限ルールのツール名〔wtool〕）
- 設計書 `docs/launcher/launcher-scripts-design.md` の §5（Claude Code の実行モデルとランチャーの関係）
- 配布文書（`.claude/CLAUDE.md`・`.claude/rules/`・`.claude/skills/`）とルートの `README.md`

凍結中の `.sh` 3 本（`start_claude_code.sh`・`.claude/launcher/setup-environment.sh`・`.claude/launcher/option-settings.sh.template`）は直さず、要る変更は SH-DEFER の札を付けて `docs/launcher/sh-freeze-backlog.md` へ送る（ルート `CLAUDE.md`「開発時の約束」）。ただし verify-kit が両版の集合一致を要求するデータ的な追随（setup-environment の内部変数名の列挙など）は、凍結中も `.sh` に反映する。

## 2. 入力

- **前回の基準点**: 実装計画の追随記録（§8 以降）の範囲にある head の SHA（`<LLMs>` リポのコミット）と changelog の版。範囲は、7. の型で書いた記録では本文の 1 行目に、それより前の記録（§8-ter・§8-quater）では導入文の括弧の中（「LLMs リポ `<base>`→`<head>`、changelog 2.1.X〜2.1.Y」）にある。実装計画 §4・§5 のインベントリ（現行の一覧）の差分は、前回の head ではなく、インベントリを最後に書き直した時点の head（§4・§5 の「基準:」の行にある版の追随記録の head）と比べる。
- **公式 docs の複製**: `<LLMs>` は、公式 docs を定期的に取り込んでいるローカルのリポジトリ。
  - `<LLMs>/official-llms-txts/code.claude.com/docs/llms-full.txt`: 全文。各ページは `# <title>` の行の次の行が `Source: <URL>`。
  - `<LLMs>/official-llms-txts/code.claude.com/docs/llms.txt`: 索引。
  - `<LLMs>/official-llms-txts/code.claude.com/docs/en/claude_code_docs_map.md`: 見出しの地図。
  - `<LLMs>` の実体（ローカルのパス）はマシンごとに違うので、各自の `CLAUDE.local.md` に書く。
- **changelog**: `llms-full.txt` の changelog のページ（`Source: https://code.claude.com/docs/en/changelog`）。各版は `**2.1.316**` のような太字の行で始まり、札は `\[VSCode]` のように `[` をエスケープして書かれている。複製に無い版は https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md を見る。版番号には欠番がある（例: 2.1.313・2.1.315）。

## 3. 手順

- ① **範囲を決める**: 前回の head の次の版から最新の版までを範囲にする。`<LLMs>` リポの base（前回の head）と head（今回）の SHA を記録する。
- ② **changelog を仕分ける**: 範囲の版の項目を、5. の既定に従って「読む」と「対象外」に分ける。対象外にしたものは理由とともに記録する。
- ③ **docs の差分を取る**: 付表 A の依存の地図にあるページごとに、base と head のページを `llms-full.txt` から取り出して比べる。changelog に無く docs だけが変わったものは、ここでしか拾えない。

  ```bash
  # llms-full.txt から <URL> のページだけを取り出す（「# <title>」の行から、次のページの「# <title>」の行の前まで）
  page() { awk -v u="$1" '
    $0 == "Source: " u { on = 1; print prev; print; next }
    on && /^Source: https:\/\/code\.claude\.com\/docs\// { done = 1; exit }
    on { if (held) print buf; buf = $0; held = 1 }
    { prev = $0 }
    END { if (held && !done) print buf }'; }
  P=official-llms-txts/code.claude.com/docs/llms-full.txt
  U=https://code.claude.com/docs/en/cli-reference
  git -C <LLMs> show <base>:$P | page "$U" > base.txt
  git -C <LLMs> show <head>:$P | page "$U" > head.txt
  diff base.txt head.txt
  ```

  シェルごとの例がタブ表記（`[tab] 名前` の行と `> ` の字下げ）に変わった v2.1.316 以降の docs では、書式だけの差分が多いページがある。素の `diff` で実質の差分を探しにくいときは、`> ` の字下げを外し、`[tab] …` の行・`**名前**` だけの行・空行を落としてから比べる。

  ```bash
  norm() { sed -E 's/^> ?//; s/^> ?//' "$1" | grep -v -E '^\[tab\] |^\*\*[^*]+\*\*$|^\s*$'; }
  diff <(norm base.txt) <(norm head.txt)
  ```

- ④ **レールごとに反映する**。設計書の本文を変えたら、別紙にも項を足す。
  - A = option-settings テンプレ（依存する docs: cli-reference）
  - B = custom.env.template と setup-environment（env-vars・各プロバイダのページ・llm-gateway）
  - C = 実行モデル（設計書 §5・`start_claude_code.ps1` の冒頭コメント）
  - D = scripts（check-assets の表・verify-kit）
  - E = 配布文書とルート README
- ⑤ **凍結中の `.sh` に要る変更は SH-DEFER へ送る**（1. の凍結の段落）。
- ⑥ **検証する**（6.）。
- ⑦ **記録する**: 7. の型で実装計画に追随記録を足す。確かめた対象の確認時点の行を更新する（場所は付表 A の「確認時点を書く場所」）。
- ⑧ **判断を求める**: 作業指示者の判断が要る項目は、個別の issue にせず 1 つの issue にまとめる（項目ごとに選択肢と推奨を付ける）。

## 4. 項目 ID

追随の項目には `W<番号>-<レール>-<連番>` の ID を付ける（例: `W44-C-03`）。

- 番号は、月曜始まりの通し週番号（`date +%W`。年の最初の月曜から数え、それより前の日は 00）。例: 2026-10-18 = W41、2026-10-24 = W42、2026-11-03 = W44。
- レールは A〜E（3. の ④）、連番は 01 から。
- 実装計画 §4・§5 のインベントリの書き直しは、その依存先のレールの ID にする（§4 = A、§5 = B）。
- 判断の結果を反映した項目は、同じ番号で F（反映）・G・H のレールを使ってきた（実装計画 §8-quater）。
- SH-DEFER の「出所」には、この ID を書く（`docs/launcher/sh-freeze-backlog.md`）。

## 5. 判断の既定

- **既定で対象外**: `[VSCode]`・`[Cloud sessions]`・`[Claude Tag]`・`[Code Review]`・`[Remote Control]` の札の付いた項目、Claude apps gateway と Self-hosted runner の項目（`self-hosted-runner` サブコマンドの変更を含む）、端末の表示だけの修正。ただし付表 A の語（`--add-dir`・`--setting-sources`・`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`・background / supervisor / agent view・LLM ゲートウェイ〔`ANTHROPIC_BASE_URL`・`*_BASE_URL`。Claude apps gateway は含まない〕・hooks・権限ルール・Windows / PowerShell・テンプレのキー名）を含む項目は、札にかかわらず読む。語を機械的に拾うと、「gateway」は Claude apps gateway に、「settings」は Claude Tag やクラウドの管理画面の settings にも掛かるので、拾った項目は読んで当たりを確かめる。
- **changelog と docs の前提**: changelog と docs はどちらも公式の情報源で正確性は同等だが、docs は版の公開から反映まで 1 日から数日遅れる（作業指示者 2026-11-03）。
- **changelog にあって docs に無い・changelog と docs が食い違う**: changelog で挙動の変更が確定できるものは本文に入れ、出所を changelog の版で書く（「changelog 2.1.3xx（docs 未反映）」と明記する）。docs に反映されたら出所を docs に差し替える。値・既定・適用範囲の詳細が changelog から読めないものは docs を待ち、「docs 掲載後に再評価」として追随記録に書く（issue #5 の U-01。2026-11-03 裁定）。
- **docs だけの変更**: changelog の仕分けでは拾えないので、3. の ③ の docs の差分で拾う。
- **キットの記述をより正しくする方向の不具合修正**: 記述の変更は不要として、記録だけする。
- **収録基準**（テンプレに載せるか、理由付きで外すか）: `.claude/launcher/README.md` 付録 A（起動オプション）、`settings-scope.txt` の冒頭（settings のキー）、実装計画 §6-bis（env）に書いてある基準に従う。基準は issue #5 の I-1〜I-3 で 2026-11-03 に裁定された（どれも暫定で、基準の正式な検討・見直しは issue #6 の K-1〜K-3）。新しい環境変数を custom.env.template に載せるかは I-3 の基準どおり docs の env-vars に行があるものに限り、changelog だけの変数は「docs 掲載後に再評価」とする（上の changelog の扱いは、既存の記述を直す話）。

## 6. 検証と期待値

- **check-assets 両版**（`bash scripts/check-assets.sh .` と `pwsh -NoProfile -File scripts/check-assets.ps1 -Share .`）: FAIL 0。WARN は既知の件数（ルート `CLAUDE.md` の追跡、作業ツリーにある未追跡の個人ファイルなど）と一致すること。2-h（追跡文書から非追跡の成果物ファイルへのパス参照）が PASS。両版の出力が一致すること。
  - 2-h は `git ls-files` の `.md` を検査するので、まだ追跡していない新しい `.md` は対象にならない。コミットの前に確かめるなら `git add -N <file>` で載せてから走らせ、`git reset -- <file>` で戻す。
- **verify-kit 両版**（`bash scripts/verify-kit.sh` と `pwsh -NoProfile -File scripts/verify-kit.ps1`。各 5 分程度。実物の `claude --version` を呼ぶが、セッションは起動しない）: FAIL 0 / SKIP 0、FROZEN = `scripts/verify-kit.d/frozen.txt` のデータ行数、PASS = 項目数 − FROZEN。`.ps1` の検証は pwsh 7 と Windows PowerShell 5.1 の 2 系統で行う（verify-kit が行う）。1 回 5 分程度かかるので、Claude に実行させるときは background で走らせ、完了の通知を待つ。
- **実物の `claude`**: 追随で起動してよいのは `claude --version` と `claude --help` だけ（どちらもセッションを始めない）。`claude --help` は設計書 §5.4.1 の型の表記（`<x...>`・`[x]`）を確かめるのに使い、確かめた版を §5.4 の確認時点に書く（issue #5 の U-07。2026-11-03 裁定）。
- **現在の値**（確認時点: 2026-11-03）: check-assets FAIL 0 / WARN 5、verify-kit PASS 23 / FAIL 0 / SKIP 0 / FROZEN 1。
- **保存形式**: `.ps1` は UTF-8 + BOM + CRLF、`.sh`・`.txt`・`.md` は LF・BOM なし。CR は `tr -cd '\r' < <file> | wc -c` で数える（Git Bash の `grep` / `awk` で数えない。ルート `CLAUDE.md`「開発時の約束」）。

## 7. 記録の型

実装計画の §8 の下に、追随ごとの記録を小節として足す。

- 見出しに版を入れず、通し番号にする（例「8-quinquies. Claude Code 追随の記録」）。
- 本文の 1 行目に範囲を書く: changelog の版（2.1.X〜2.1.Y）、`<LLMs>` リポの base → head の SHA、日付。
- 続けて次を書く。
  - レール A〜E ごとの反映（項目 ID 付き）
  - 差分なしを確かめたページと節
  - 要実測
  - 未決（作業指示者の判断待ち。issue 番号）
  - changelog にあって docs に無いもの（docs 掲載後に再評価）
- 設計書の本文を変えたら、別紙にも項を足す。
- 実装計画 §4・§5 のインベントリを現行の一覧に書き直すときは、一覧を表にし、従来の一覧・注記・追補は「過去の追補（記録。原文のまま）」の小見出しの下に原文のまま残す（消さない）。「基準:」の行の版と日付を上げる。

## 付表 A. 依存の地図

| 追随の対象 | 依存する docs のページと節 | changelog で拾う語 | 確認時点を書く場所 |
|---|---|---|---|
| option-settings テンプレの全キー | [cli-reference](https://code.claude.com/docs/en/cli-reference)「CLI flags」 | フラグ名 | README 付録 A の版の行 |
| `--permission-mode` | [permission-modes](https://code.claude.com/docs/en/permission-modes)「Which mode a session starts in」 | permission mode | 同上 |
| `--model`・`--effort` | [model-config](https://code.claude.com/docs/en/model-config)（「Adjust effort level」「Send no effort level」） | model, effort | 同上 |
| custom.env.template の全キー | [env-vars](https://code.claude.com/docs/en/env-vars)「Variables」 | 変数名 | README 付録 A の版の行 |
| setup-environment の分類B（3P・ゲートウェイ・テレメトリ） | env-vars、[llm-gateway](https://code.claude.com/docs/en/llm-gateway)、[monitoring-usage](https://code.claude.com/docs/en/monitoring-usage)、各プロバイダのページ、[feature-availability](https://code.claude.com/docs/en/feature-availability)（3P で使えない機能の注記の典拠） | 変数名、gateway, OpenTelemetry | 実装計画 §5 の「基準:」の行 |
| `settings-scope.txt` の u / m | [settings-reference](https://code.claude.com/docs/en/settings-reference) の表の Scope 列 | キー名、settings（settings ファイルのキーの話に限る） | `settings-scope.txt` の各節のコメント |
| `settings-scope.txt` の e | settings-reference「[Variables Claude Code ignores in `env`](https://code.claude.com/docs/en/settings-reference#variables-claude-code-ignores-in-env)」 | 変数名 | 同上 |
| `settings-scope.txt` の wtool | [permissions](https://code.claude.com/docs/en/permissions)「`Write(path)`, `NotebookEdit(path)`, and `Glob(path)` rules never match」 | permission rules | 同上 |
| 設計書 §5.1.1〜5.1.2 | [sub-agents](https://code.claude.com/docs/en/sub-agents)、[agent-view](https://code.claude.com/docs/en/agent-view)「Monitor sessions with agent view」、[agent-teams](https://code.claude.com/docs/en/agent-teams)、[workflows](https://code.claude.com/docs/en/workflows)、corporate-launcher「Processes that start outside the launcher」と [deep-links](https://code.claude.com/docs/en/deep-links)（deep link で開いたセッションの行） | subagent, teammate, background, deep link | 5.1.2 の末尾（5.1.3 の前） |
| 設計書 §5.1.3 | agent-view「[Settings and provider](https://code.claude.com/docs/en/agent-view#settings-and-provider)」、[network-config](https://code.claude.com/docs/en/network-config)「Apply network settings to background agents」、settings-reference「Variables Claude Code ignores in `env`」、[permission-modes](https://code.claude.com/docs/en/permission-modes)「Why the critical-path removal prompt stays on」（background セッションが持たずに始まる変数。列挙に載せるかの判断） | background, supervisor, env | 5.1 の末尾 |
| 設計書 §5.2 | [corporate-launcher](https://code.claude.com/docs/en/corporate-launcher)（「What the launcher covers」「The launcher contract」） | CLAUDE_CODE_PROCESS_WRAPPER, launcher | 5.2 の末尾 |
| 設計書 §5.3 | agent-view「Settings, plugins, and MCP servers」（`agents` の前に置けないフラグ）、errors「`<flag>` before `remote-control` is not carried over to the sessions Remote Control starts」、[remote-control](https://code.claude.com/docs/en/remote-control)、cli-reference（サブコマンド） | remote-control, agents | 5.3 の末尾 |
| 設計書 §5.4 | `claude --help` の型の表記（`<x...>`・`[x]`。cli-reference の表には型の表記が無く、`--file` は行も無い。確かめた版を書く。`claude --help` の表記で確かめる〔U-07 で許可〕）、agent-view「Prompts that contain `--bg`」 | `--`, positional, `--bg` | 5.4 の末尾 |
| 設計書 §5.5 | [errors](https://code.claude.com/docs/en/errors)「[Configuration warnings](https://code.claude.com/docs/en/errors#configuration-warnings)」「[Working directory is a network path](https://code.claude.com/docs/en/errors#working-directory-is-a-network-path)」 | warning, network path, `--add-dir`, debug log | 5.5 の末尾 |
| README 付録 B の各項目 | 項目ごと: `--model` → model-config／`--add-dir` → errors「Working directory is a network path」、[skills](https://code.claude.com/docs/en/skills)「Load skills from a directory outside the project」／`--setting-sources` → cli-reference「CLI flags」の行、skills「Load skills from a directory outside the project」、agent-view「What carries over when you background」／`--permission-mode` → permission-modes／`--tools` → [tools-reference](https://code.claude.com/docs/en/tools-reference)／`--worktree` → [worktrees](https://code.claude.com/docs/en/worktrees)、settings-reference の [`worktree.sparsePaths`](https://code.claude.com/docs/en/settings-reference#worktree-sparsepaths) と [large-codebases](https://code.claude.com/docs/en/large-codebases)「Check out only the directories you need」（`.claude` を列挙に含める注意。worktrees のページには無い）／`--teammate-mode` → agent-teams／`--debug-file` → errors「Configuration warnings」 | 同左（項目のフラグ名） | README 付録 A の版の行 |
| README 付録 D（custom.env に載せていない環境変数） | env-vars、settings-reference「Variables Claude Code ignores in `env`」、permission-modes「Why the critical-path removal prompt stays on」 | 変数名 | README 付録 A の版の行 |
| `start_claude_code.ps1` の冒頭コメント | corporate-launcher「[The launcher contract](https://code.claude.com/docs/en/corporate-launcher#the-launcher-contract)」、agent-view「Settings and provider」 | launcher, background | コメント内の版・実測の札（「v2.1.302 で実測」等） |
| ルート README「動作環境」 | [changelog](https://code.claude.com/docs/en/changelog) | version | README の推奨版の行 |

## 付表 B. 同じ事実を書いている場所

1 つの事実が複数の文書に書かれている。追随で事実が変わったら、行の場所をすべて直す。

| 事実 | 書いてある場所 |
|---|---|
| 起動環境からしか読まれない変数（どの settings の `env` でも無視される） | 設計書 §5.1.3、実装計画 §6-bis の分類B の注記と §5 の表、`settings-scope.txt` の E 節のコメント、`check-assets.sh`・`check-assets.ps1` の 3. の冒頭コメント、check-assets 両版の E の WARN の文言（変数を「等」なしで列挙している。両版同文に保つ）、`.claude/launcher/README.md` §2-4「空き容量の警告」 |
| v2.1.305 以降、対話起動の起動時警告はデバッグログにだけ出る | 設計書 §5.5.2、`.claude/launcher/README.md` 付録 B「起動時の警告を読む」「--add-dir とネットワークパス」、option-settings テンプレの `--debug-file` のコメント、`start_claude_code.ps1` の (a)（UNC の検査）のコメント、`check-assets.sh` の 3. の冒頭コメント、ルート README の方法 B |
| background に引き継がれる構成フラグ | 設計書 §5.1.3、`.claude/launcher/README.md` §5、`start_claude_code.ps1` の冒頭コメント、実装計画 §3 (1) |
| `CLAUDE_CODE_EVEN_MORE_DANGEROUSLY_SKIP_PERMISSIONS` は background セッション等が持たずに始まり、Bash / Edit / Read を対象にする deny / ask ルールがあると効かない（起動環境からしか読まれない変数の列挙・custom.env.template に載せない理由） | 設計書 §5.1.3 の注記、`.claude/launcher/README.md` 付録 D、実装計画 §5 の表 |
| `CLAUDE_CODE_PROCESS_WRAPPER` は Windows で無視される | 設計書 §5.2.2、実装計画 §3 (1)・§5、`start_claude_code.ps1` の冒頭コメント、`setup-environment.ps1` の冒頭コメント（supervisor ごとラップする公式手段の注記） |

将来は、事実ごとに正本を設計書の 1 か所に決め、他の場所は参照に寄せる。
