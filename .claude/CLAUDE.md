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

**注意**: Sub-agent から別の Sub-agent を呼び出すことは公式仕様上不可能。マルチエージェント協調は
必ず `/orchestrate`（メインセッション実行）を経由する。

## Windows 向けファイルの文字コード

`.ps1` は **UTF-8 + BOM + CRLF**、`.bat` は **CP932 + CRLF**（BOM なし）で保存する。**`.bat` は Claude の
ファイルツールで直接扱えない**（UTF-8 前提のため、読むと文字化けし、書くと壊す）。

- **読む**: 普通に `Read` してよい。hook が UTF-8 の作業コピーへ差し替える
- **編集する**: 原本ではなく作業コピー（`.claude/.bat-shadow/…`）を `Edit` する。保存すると CP932 へ書き戻る
- **新規作成する**: `python .claude/hooks/bat_cp932_guard.py new <path>.bat`
- **`.bat` を Bash のリダイレクト・heredoc・`sed -i` で作成/編集してはならない**（hook が守れず、UTF-8 の
  壊れた `.bat` が生まれる。cmd.exe は 1 行目から誤動作する）

> このルールは**新規作成時にも効かせる必要がある**ためここに置いてある（`.claude/rules/win-file-encoding.md`
> は path-scoped で、**既存ファイルを読んだ時にしかロードされない**）。詳細・根拠は同 rule を参照。
> hook には Python（3.10+）が要る。無い環境では `.bat` は読めないが、`permissions.deny` により
> 編集は常に拒否されるので**原本が壊れることはない**。

## 重要な制約

- `.env` ファイルを直接編集しない。環境変数は実行環境から参照する
- API キー・パスワード等の機密情報をコードにハードコードしない
- 機密情報は `secrets/` 等へ隔離し、`.gitignore` で除外する（**除外されているかは各リポジトリで確認する**）
- DB マイグレーション等の破壊的操作は必ず確認を取ってから実行する
