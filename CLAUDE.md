# CLAUDE.md

**このリポジトリ（`base-dev-kit-for-cc`）を開発・リリースするための指示**。

> ⚠ **本ファイルは開発リポ専用**。配布物ではない。`publish-share` は `.claude/` 配下だけを payload として
> 取り出すため、本ファイルは配布先へ届かない。**利用先へ届けたい共通指示は `.claude/CLAUDE.md` に書くこと**
> （本ファイルに書いても誰にも届かない）。コピー展開先が使う雛型は `CLAUDE.md.example`。
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
- **修正した後の状態で再検証する**。「修正それ自体が新たな欠陥を生む」ことが繰り返し起きている。
  過去に取った検証結果を、前提を変えた後も使い回さない。
- **Git Bash の `grep` / `awk` で CR を数えない**。間違い方が 2 通りあり、どちらも“それらしい値”を返す ――
  `grep -c $'\r'` は**パターンが空になり全行にマッチして総行数**を返し、実 CR をパターンにすると今度は
  **grep が入力の CR を剥がして常に 0** を返す。**「大きい数」と「0」の両方が誤りになりうる**ため、
  before/after を別の書き方で測ると**壊れた計測どうしが「修正が効いた」ように見える**（実際に起きた）。
  `tr -cd '\r' | wc -c` か `git ls-files --eol` を使う。

## 環境

- Windows がプライマリ。bash（Git Bash）と PowerShell の両方で動く必要がある。
- Python（CPython 3.x）を使う資産がある（`.claude/hooks/` と `win-file-encoding` skill）。
- **`.bat` は CP932 で保存する**。Claude は原本に触れず、hook が見せる UTF-8 の作業コピーを編集する。
  詳細は `.claude/rules/win-file-encoding.md`（`.bat` を読むと自動でロードされる）。
