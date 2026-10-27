# CLAUDE.md（チーム共有・共通指示）

base-dev-kit-for-cc が配布する**チーム共通の Claude Code 指示**。`--add-dir <Share>` ＋
`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` で参照する利用先リポジトリ、または本キットを
コピー展開したプロジェクトの双方で、共通ルールとしてロードされることを想定する。

> **このファイルに書かないもの**: リポジトリ固有の使い方・MCP ポリシー・拡張オプション・
> ローカル絶対パス。それらは `README.md`（`--add-dir` では非ロード）に置く。本ファイルは
> 利用先リポジトリの文脈に**そのまま混ざってよい汎用ルールだけ**を保持する。

## コーディング規約

詳細は `.claude/rules/coding-standards.md`（コードファイル編集時に path-scoped で自動ロード）。主要方針:

- 命名規則は言語慣習に従う
- コメントは「なぜそうするか」を説明する場合のみ記述する
- エラーは握り潰さない
- 外部入力の境界でのみバリデーションする

## Git ワークフロー

- ブランチ命名: `<username>/<feature-description>`（例: `alice/add-auth`）
- コミットプレフィックス: `feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `chore:`
- コミット前にテストを実行する
- `/commit-and-pr` でコミット → プッシュ → PR 作成を一括実行できる

## マルチエージェント戦略

### Skills（メインセッションで実行）

| コマンド | 用途 |
|---|---|
| `/commit-and-pr` | 変更をコミットして PR を作成 |
| `/orchestrate` | 複数エージェントを協調させる（並列調査・段階的処理・役割分担） |
| `/pre-compact` | `/compact` の前に文脈を保全する（メモリ最新化・未コミット確認・コンパクション指示の生成） |
| `/request-new-skill` | 新しい skill を依頼する（依頼書テンプレを生成） |
| `/review-skill-request` | skill 依頼書をレビューし実装方針を起こす |
| `/win-file-encoding` | UTF-8/LF ⇄ CP932/CRLF の一括変換・検査（日常の `.bat` 編集では不要。hook が自動処理する） |

### Sub-agents（隔離コンテキストで実行）

| エージェント | 用途 |
|---|---|
| `code-reviewer` | コード変更の品質・セキュリティ・保守性レビュー（出力形式は `output-styles/code-review.md`） |

**注意**: Sub-agent は既定で自分の Sub-agent を起動できる（v2.1.172〜。現在の既定はメイン会話から 3 層まで。
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` で変更でき、`1` でネスト無効）。ただし対話セッションでは入れ子の
中間出力はメイン会話に返らず、最上位 Sub-agent の要約だけが返るため、役割分担・段階的処理を設計して
協調させるときは `/orchestrate`（メインセッション実行）を経由する。メイン会話から起動した Sub-agent は既定で
background で動き、fork モード（既定で有効）の間、対話セッションの Claude はその完了を待てない ―― 結果は後の
ターンに完了通知で届くので、前段の結果を使う処理は通知を受け取ってから次へ進む（待たせる設定は
`.claude/skills/orchestrate/SKILL.md`）。読み取り専用に留めたい Sub-agent（`code-reviewer` 等）は `tools` に
`Agent` を含めない。

## Windows 向けファイルの文字コード

`.ps1` は **UTF-8 + BOM + CRLF**、`.bat` は **CP932 + CRLF**（BOM なし）で保存する。**`.bat` は Claude の
ファイルツールで直接扱えない**（UTF-8 前提のため、読むと文字化けする。Edit は非 UTF-8 ファイルへの変更を
拒否する（v2.1.296〜）が、ASCII だけの `.bat` は UTF-8 としても有効なので通ってしまい、日本語を足すと UTF-8 で
保存されて壊れる。Write も、日本語を含む CP932 ファイルの上書きは拒否される（v2.1.302 実測）が、ASCII だけの
`.bat` は通り、新規作成は UTF-8 になる。だから `permissions.deny` は引き続き必須）。

- **読む**: 普通に `Read` してよい。hook が UTF-8 の作業コピーへ差し替える
- **編集する**: 原本ではなく作業コピー（`.claude/.bat-shadow/…`）を `Edit` する。保存すると CP932 へ書き戻る
- **新規作成する**: `python .claude/hooks/bat_cp932_guard.py new <path>.bat`
- **`.bat` をシェルやスクリプト経由で作成/編集してはならない** ―― Bash のリダイレクト・heredoc・`sed -i`、
  PowerShell の `Set-Content` / `Add-Content` / `Out-File` / `>`、Python 等のスクリプトのいずれも不可（hook が
  守れず、UTF-8 の壊れた `.bat` が生まれる。cmd.exe は 1 行目から誤動作する）。Windows では PowerShell ツールが
  有効なら主シェルになる。Bash のリダイレクト先や `tee` / `sed` は `permissions.deny` の `Edit(...)` でも止まるが
  （サブシェルを含む一部のコマンドのリダイレクトは v2.1.309 未満では止まらなかった）、
  PowerShell やスクリプトからの書き込みには機構による保証が無い。**例外は 2 つだけ**: `bat_cp932_guard.py new`
  （新規作成）と、`win-file-encoding` skill の `convert_encoding.py --to-win`（UTF-8 で保存されてしまった
  `.bat` の修復。実行後は原本を Read し直す）。`Edit` / `Write` の拒否メッセージが勧める iconv・
  `Set-Content -Encoding`・「消してから Write」には `.bat` では従わない

> このルールは**新規作成時にも効かせる必要がある**ためここに置いてある（`.claude/rules/win-file-encoding.md`
> は path-scoped で、対象ファイルを Read / Edit / Write したとき（Bash の `cat` 等での閲覧を含む）にロードされる。
> **新規作成では最初の操作より前に載っている保証が無い**）。詳細・根拠は同 rule を参照。
> hook には Python（3.10+）が要る。無い環境では `.bat` は読めないが、`permissions.deny` により
> 編集は常に拒否されるので**原本が壊れることはない**。

## 重要な制約

- `.env` ファイルを直接編集しない。環境変数は実行環境から参照する
- API キー・パスワード等の機密情報をコードにハードコードしない
- 機密情報は `secrets/` 等へ隔離し、`.gitignore` で除外する（**除外されているかは各リポジトリで確認する**）
- DB マイグレーション等の破壊的操作は必ず確認を取ってから実行する
