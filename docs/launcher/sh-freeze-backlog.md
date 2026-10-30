# `.sh` 凍結バックログ（ランチャー資産）

ランチャー資産の bash 版 3 本について、PowerShell 版との同時メンテを一時中断（凍結）している間に、PowerShell 版だけに入れた変更と、再開時に `.sh` 側で要る作業を記録する。開発リポジトリ専用の文書で、配布されない（`docs/` は payload に乗らない）。

## 凍結の範囲

- **開始日**: 2026-10-30
- **最後に同期した状態**: `c241150`（develop。`.sh` と `.ps1` を対で保守した最後の統合点）。それ以後、凍結開始までのコミット（`1b6e9fb`・`987cab8`）はランチャー資産に触れていない。凍結開始のコミットでは 3 本の先頭に「PowerShell 版に追随していない」旨のコメントを足しただけで、挙動は `c241150` のまま。
- **対象（凍結する 3 本）**: `start_claude_code.sh`（リポジトリのルート。`basic_cc_project` へ手動で配る側）・`.claude/launcher/setup-environment.sh`・`.claude/launcher/option-settings.sh.template`（後の 2 本は payload として配布される）。
- **対象外**: `scripts/*.sh`（check-assets・verify-kit・publish 系・clean-test-env）。従来どおり両版を同時に保守する。
- **終了条件**: 「作業指示者が bash 利用者（職場のチームメンバー）へ展開できる状態になったと判断した」の 1 条件だけ。設計 v2 の確定や経過週数は条件にしない。

## 凍結中の運用

- 週次追随（Claude Code の更新への追随）で `.sh` 固有の項目が出たら、SH-DEFER の札を付けて下の一覧に 1 行足す。`.sh` は直さない。
- `.ps1` の検証は pwsh 7 と Windows PowerShell 5.1 の 2 系統比較を省かない（bash 系統が比較から外れても、残る 2 系統の一致は必ず見る）。
- verify-kit が両版の集合一致を要求するデータ的な追随（setup-environment の内部変数名の列挙など。項目 `internal-keys` は凍結できない）は、凍結中も `.sh` に反映する。custom.env の受け付ける形を狭める変更・機微情報の判定を増やす変更もこれに含める。
- custom.env の書式を広げる変更（両版のローダが受け付ける行の形を増やす変更。例: 値の引用符を剥がす、`export KEY=` を許す、行末の `# コメント` を切り落とす、変数参照を展開する）は避ける。どうしても要るなら「PowerShell 版のみ」と明記し、`custom.env.template` の例は両版が同じに読む共通部分集合で書く。
- `.ps1` だけを変えたことで verify-kit の比較項目の系統が食い違うようになるときは、同じ変更で `scripts/verify-kit.d/frozen.txt` に行を足し、この一覧にも対応する行を足す。

## 再開の手順

1. 一覧の `open` の項目を 1 件選び、機能単位で `.sh` に移植する（`.ps1` 側の変更は `出所` から辿る）。
2. その項目に対応する `frozen.txt` の行を消し、verify-kit を両版で走らせて、該当する項目が FROZEN ではなく PASS になることを確かめる（同じ項目キーに影響する `open` の項目が残っているうちは、その行は消せない）。
3. 一覧の `状態` を `done` にする。
4. 1〜3 を 1 件ずつ繰り返す。一覧の `open` と `frozen.txt` のデータ行が両方とも 0 になったら凍結終了。3 本の先頭のコメントと、ルート `CLAUDE.md`・`README.md`・`.claude/launcher/README.md` の凍結の記述を外す。

## `frozen.txt` との役割分担

- この一覧は人が読む「理由と作業内容」、`scripts/verify-kit.d/frozen.txt` は verify-kit が読む「検査の免除」（期待される系統の非対称の宣言）。再開時は両方を空にする。
- 1 件の SH-DEFER が verify-kit の項目に影響するなら、`影響する verify-kit 項目・fixture` 列にその項目キー（例: `launcher-streams`）と変えた fixture（例: `launcher-streams.txt`）を書き、`frozen.txt` には同じ項目キーの行を足す。影響しないもの（コメント・文言だけの差など）は `—` とする。
- 複数の SH-DEFER が同じ項目キーに影響することがある（`frozen.txt` の行は項目キーと系統の組ごとに 1 行）。

## 記入のしかた

- `ID` は `SH-DEFER-nn`（01 から連番。番号は再利用しない）。
- `出所` は週次追随の項目 ID（例: `W44-C-03`）か、機能を入れたコミットの SHA。
- 「`.ps1` 側で何が変わったか」と「`.sh` 側に要る作業」は 1 文ずつ。
- `状態` は `open` / `done`。`done` の行も消さずに残す（再開の記録）。

## 一覧

| ID | 記入日 | 出所 | `.ps1` 側で何が変わったか | `.sh` 側に要る作業 | 影響する verify-kit 項目・fixture | 状態 |
|---|---|---|---|---|---|---|
| SH-DEFER-01 | 2026-10-30 | スクリプト追加改善のフェーズ 2（計画書 `2026-10-30_script-improvements_00_plan.md` §3、報告書 `2026-10-30_script-improvements_03_omitted-options.md`。コミットは件名が `feat(launcher)` で始まるもの。SHA はコミット前に決まらないので書いていない） | `start_claude_code.ps1` が option-settings（`$Opts`）と `$TeamOpts` を出どころごとに検査し、区分 1 のキー（`--restricted`・`--bare`・`--safe-mode`・`--system-prompt`・`--system-prompt-file`）と `project` を含まない `--setting-sources` を、UNC 検査の後に出どころ付きで stderr へ 1 件 1 行警告するようにした（起動は止めず、キーも捨てない）。 | `OPTS` と `TEAM_OPTS` を同じ固定表・同じ順（出どころ順 → 表の順 → `--setting-sources`）で検査して同じ文言（前置きは `⚠ `）を `>&2` に出し、fixture の stderr 8 行で PASS に戻す（PS 版のキー照合は `[ordered]` の `Contains` で大文字小文字を区別しないので、その扱いも揃える）。 | `launcher-streams`・`launcher-streams.txt` | open |
