# CLAUDE.md

**このリポジトリ（`base-dev-kit-for-cc`）を開発・リリースするための指示**。

> ⚠ **本ファイルは開発リポ専用**。配布物ではない。`publish-share` は `.claude/` 配下だけを payload として
> 取り出すため、本ファイルは配布先へ届かない。**利用先へ届けたい共通指示は `.claude/CLAUDE.md` に書くこと**
> （本ファイルに書いても誰にも届かない）。**コピー展開先が使うプロジェクト固有 `CLAUDE.md` の雛型は
> `basic_cc_project` の `CLAUDE.md.sample` に一本化した**（本リポジトリには置かない ―― 雛型を 2 か所に
> 置くと必ず片方が陳腐化する）。
>
> リポジトリの説明・使い方・構成・MCP ポリシーは **`README.md` が正本**。ここで重複させない。

## このリポジトリの役割

Claude Code の**共有 `.claude/` キット（`<Share>`）そのもの**。ここで作った `.claude/` を、公開リポジトリ
`basic_dot_claude` へ publish し、利用先はそれを submodule として取り込む。つまり**本リポジトリの成果物は
`.claude/` ディレクトリ 1 個**であり、それ以外（`scripts/` / `docs/` / ルート直下）は**それを作って配るための道具**。

## 配布レールは 2 本ある（混同しない）

| レール | 運ぶもの | 手段 | 配布先 |
|---|---|---|---|
| **payload レール** | `.claude/` 配下**だけ** | `scripts/publish-share.{sh,ps1}` | `basic_dot_claude`（ルート＝`.claude/` の中身） |
| **ルート直コミットレール** | `start_claude_code.{sh,ps1}` / ルート `.gitattributes` | 手動コミット | `basic_cc_project`（参照ハブ） |

**ルート直下のファイルは payload に乗らない**。ランチャーは「部品（`.claude/launcher/`＝配布される）」と
「本体（ルート＝配布されない）」に分かれているため、片方だけ届けると動かない。

## リリース手順（要点）

詳細は `README.md` の「公開前チェック・テスト」「配布（publish）」節。ここでは**順序の制約**だけ示す。

1. **grooming が前提条件**。`.claude/reports/` 等のセッション成果物が追跡された ref を publish すると、
   内部レポートが公開リポへ流出し、配布先の `.claude/CLAUDE.md` も消える（ミラーは payload に無いものを削除する）。
2. `develop` → `main` へ統合し、**タグを打った ref** を publish する。feature ブランチからの publish は検証用に限る。
3. `publish-share` は `--ref` 必須。publish 前に `check-assets` が**実体基準**で自動実行され、FAIL なら中止する。
4. publish 後に `basic_cc_project` で submodule を bump する。

## 開発時の約束

- **`.claude/` に何かを足したら、それが payload に乗ることを意識する**。個人実体・成果物・一時物は
  `.gitignore` と `check-assets` の成果物クラス配列（`scripts/check-assets.*` の 2-c）に**必ず追随させる**。
  片側だけ更新すると配布先に穴が残る。
- **`.gitattributes` は「深い階層が勝つ」**（`.gitignore` と違い加算されない）。`.claude/` 配下の改行方針を
  変えるときは `.claude/.gitattributes` を直す。ルート側の指定は `.claude/` には効かない。
- **bash 版と PowerShell 版は必ず両方直す**。片方だけ直した実績が複数回ある（fail-closed を PS 版にだけ実装、
  警告を bash 版にだけ実装）。修正したら**両版を実際に走らせて結果が一致すること**を確認する。
- **例外: ランチャー資産の `.sh` 3 本は同時メンテを凍結中**（2026-10-30 開始。最後に同期した状態は `c241150`）。
  対象は `start_claude_code.sh`・`.claude/launcher/setup-environment.sh`・`.claude/launcher/option-settings.sh.template`
  の 3 本だけで、**それ以外の `.sh`（`scripts/*.sh`）は従来どおり両方直す**。終了条件は「作業指示者が bash 利用者
  （職場のチームメンバー）へ展開できる状態になったと判断した」の 1 つだけ。凍結中は次を守る:
  - 週次追随で `.sh` 固有の項目は SH-DEFER の札を付け、`.sh` を直さずに凍結バックログ
    `docs/launcher/sh-freeze-backlog.md` へ送る
  - `.ps1` の検証は pwsh 7 と Windows PowerShell 5.1 の 2 系統比較を省かない
  - verify-kit が両版の集合一致を要求するデータ的な追随（setup-environment の内部変数名の列挙など）は、
    凍結中も `.sh` に反映する
  - custom.env の書式を広げる変更（両版のローダが受け付ける行の形を増やす変更）は避ける。要るなら
    「PowerShell 版のみ」と明記し、テンプレの例は両版の共通部分集合で書く
  - `.ps1` だけを変えて verify-kit の系統が食い違うときは、凍結 fixture `scripts/verify-kit.d/frozen.txt` に行を足し
    （FROZEN として集計される）、バックログにも対応する行を足す。再開はバックログの項目を機能単位で `.sh` に
    移植し、verify-kit を通して frozen.txt の該当行を 1 つずつ消す。両方が空になったら凍結終了
- **修正した後の状態で再検証する**。「修正それ自体が新たな欠陥を生む」ことが繰り返し起きている。
  過去に取った検証結果を、前提を変えた後も使い回さない。
- **Git Bash の `grep` / `awk` で CR を数えない**。間違い方が 2 通りあり、どちらも“それらしい値”を返す ――
  `grep -c $'\r'` は**パターンが空になり全行にマッチして総行数**を返し、実 CR をパターンにすると今度は
  **grep が入力の CR を剥がして常に 0** を返す。**「大きい数」と「0」の両方が誤りになりうる**ため、
  before/after を別の書き方で測ると**壊れた計測どうしが「修正が効いた」ように見える**（実際に起きた）。
  `tr -cd '\r' | wc -c` か `git ls-files --eol` を使う。PowerShell ツール側で数えるなら
  `([IO.File]::ReadAllBytes('<file>') | Where-Object { $_ -eq 13 }).Count` でバイトを数える
  （`Get-Content` / `Select-String` は改行を剥がすので CR を数えられない）。

## 環境

- Windows がプライマリ。bash（Git Bash）と PowerShell の両方で動く必要がある（スクリプト側の要件）。
- Claude 自身のシェルツールは、Windows では PowerShell ツールが主になる（Git for Windows があっても
  claude.ai / Console アカウントでは既定で有効で、Claude は PowerShell を primary shell として扱う。
  Bash ツールは Git Bash がある場合に POSIX スクリプト用として残り、無ければ登録されない）。
  bash 版は Bash ツール（Git Bash）で、PS 版は PowerShell ツールで、それぞれ実際に走らせて検証する。
- Python（CPython 3.x）を使う資産がある（`.claude/hooks/` と `win-file-encoding` skill）。
- **`.bat` は CP932 で保存する**。Claude は原本に触れず、hook が見せる UTF-8 の作業コピーを編集する。
  詳細は `.claude/rules/win-file-encoding.md`（path-scoped rule。`.bat` や作業コピーを Read / Edit したとき、
  または Bash の `cat` 等で閲覧したときに自動でロードされる）。
