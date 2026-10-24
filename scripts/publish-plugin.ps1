<#
  publish-plugin.ps1 — <Dev>(C-BDK) の指定 ref のプラグインを Marketplace リポジトリ <C-MKT> へ publish（層2・validate ゲート）

  publish-share.ps1（層1 body の publish）の plugin 版。release-ready なプラグインを marketplace
  リポジトリへコピーし commit/push する意図的な公開操作で、push はここでしか行わない。
  publish 対象は -Ref で明示指定する（既定値は無い）。checkout 不要で任意 ref を publish できる。

  使い方:
    .\scripts\publish-plugin.ps1 -Marketplace <C-MKT のパス> -Ref <ref> [-Plugin <repo相対pluginディレクトリ>] [-Name <plugin名>]
      -Name は英数字と . _ - のみ・先頭は英数字・末尾は . 以外・Windows の予約デバイス名（CON / NUL / COM1 等。
      拡張子付きも）以外・128 文字以内（既定: -Plugin のベース名）。marketplace の plugins/ に大文字小文字だけが
      違う既存エントリがあれば中止する。plugin.json の name と一致しなければ中止する（name を読めない場合も中止）。

  前提: claude CLI が PATH 上にあること（plugin validate ゲートに使用）。
  注記(ドラフト): プラグイン組成フェーズ未了のため既定 -Plugin=plugin は仮。marketplace.json の
    エントリ整備は本スクリプト範囲外（コピー後にリマインドを表示）。

  ⚠ 本スクリプトは publish-share.ps1 と同じ防御を持たせること（片方だけ直した状態を作らない）。
     -Ref 必須 / DevRoot の CWD 非依存 / 配布先ルート検査（gitlink 拒否）/ symlink 拒否 /
     zip 経由の展開 / core.autocrlf=false / 展開の fail-closed / commit・push 失敗の検知。
#>

# Windows PowerShell 5.1 では stderr リダイレクト（*> $null）と $ErrorActionPreference='Stop' の
# 組み合わせで native の stderr が terminating error に化け、ガードの診断と終了コード規約が崩れる
# （実測: ref の打ち間違いで『‼ ref が存在しない』(exit 2) ではなく NativeCommandError の生スタックが出る）。
# 対象シェルを機械で宣言して fail fast させる。
#requires -Version 7
# ⚠ -Marketplace / -Ref に [Parameter(Mandatory)] を付けない。非対話で省略すると PowerShell 独自の文言で落ち
#    （対話ではプロンプトになる）、空文字列はバインドの段階で拒否されるため、bash 版と同じ文言・終了コードにできない。
#    本文で明示的に検査する（bash 版の必須の検査と同じ文言・exit 2）。
param(
  [string]$Marketplace = '',
  [string]$Ref = '',
  [string]$Plugin = 'plugin',
  [string]$Name = ''
)
$ErrorActionPreference = 'Stop'

# ⚠ 中止のメッセージ（‼ の行とその続きの行）は bash 版と同じく stderr へ出す（Write-Host は stdout）。
#    Write-Error は使わない: $ErrorActionPreference='Stop' 下では Write-Error が terminating error になり、
#    直後の exit <code> に到達せず終了コードが不定になる。
function Write-Err([string]$m) { [Console]::Error.WriteLine($m) }

# 引数の検査（bash 版の引数の解析と必須の検査と同じ順・同じ文言・同じ終了コード）:
#   -Plugin / -Name を明示的に空で渡したら引数エラーで止める（exit 1。既定値を使うのは省略したときだけ）→
#   -Marketplace が空・省略なら exit 2 → -Ref が空・省略なら exit 2。
if ($PSBoundParameters.ContainsKey('Plugin') -and $Plugin -eq '') {
  Write-Err '‼ -Plugin に値が必要（空のディレクトリは指定できない。既定の plugin を使うなら -Plugin を省略する）'
  exit 1
}
if ($PSBoundParameters.ContainsKey('Name') -and $Name -eq '') {
  Write-Err '‼ -Name に値が必要（空の名前は指定できない。既定名を使うなら -Name を省略する）'
  exit 1
}
if ($Marketplace -eq '') { Write-Err '‼ -Marketplace <C-MKT のパス> が必要'; exit 2 }
# ⚠ -Ref に既定値を持たせない（publish-share.ps1 と同じ理由）。publish する ref は毎回意識して選ぶ。
if ($Ref -eq '') {
  Write-Err '‼ -Ref は必須です（既定値は廃止）。publish する ref を明示してください。'
  Write-Err "   例: $PSCommandPath -Marketplace <path> -Ref v1.0.0"
  exit 2
}
if (-not $Name) { $Name = Split-Path -Leaf $Plugin }

# $Name はそのまま plugins/<Name> というパスに連結される。検証しないと '..' や '.' や
# スラッシュ入りの値で dest が marketplace のルートを指し、後段の「.git 以外を全削除」が
# そこへ走る（実測: -Name .. でルートが plugin の中身に置換されて push された）。
# 加えて marketplace のエントリ名の公式規則（英数字と . _ - のみ・先頭は英数字・Desktop は 128 文字以内）に合わせる。
# ⚠ .NET の $ は末尾改行の直前にも一致するため \z で終端を判定する（bash 版の改行拒否と対称）。
# ⚠ 末尾が . の名前も拒否する。Windows はパスの末尾のドットを落とすため plugins\foo. が既存の plugins\foo を指し、
#    後段のミラー（.git 以外を全削除）が別の plugin を消す。正規表現とは別の条件にしているのは、bash 版と同じ
#    正規表現の文字列を保つため（verify-kit が両版の正規表現を突き合わせる）。
# ⚠ Windows の予約デバイス名（CON / PRN / AUX / NUL / COM0〜COM9 / LPT0〜LPT9。大文字小文字を区別せず、
#    nul.txt のように拡張子が付いた形も）も拒否する。Windows では plugins\nul がフォルダではなくデバイスを指し、
#    ミラーとコピーが plugins\<名前> 以外に作用する。Linux / macOS で publish しても、Windows の clone では
#    checkout できないパスになる。判定は「最初の . より前」が予約名かどうか（foo.con は予約名ではない）。
if ($Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z' -or $Name.EndsWith('.') -or
    $Name -imatch '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\..*)?\z') {
  Write-Err "‼ plugin 名として不正: '$Name'（英数字と . _ - のみ・先頭は英数字・末尾は . 以外・Windows の予約名（CON / NUL / COM1 等。拡張子付きも）以外・128 文字以内）"
  exit 2
}

# plugin.json の name を読む（2-a で使う）。読めなければ $null を返す: UTF-8 / JSON として不正・最上位が
# オブジェクトでない・name が無いか文字列でない。bash 版（python の json）と同じ判定にするため:
#   - 先頭の BOM 1 個だけを読み飛ばし、残りを厳格な UTF-8 として復号する（python の utf-8-sig と同じ）。
#     Get-Content は不正なバイトを U+FFFD に置き換えて読み進め、UTF-16 の BOM も解釈してしまう。
#   - ConvertFrom-Json ではなく System.Text.Json で解析する。ConvertFrom-Json はプロパティ名を大文字小文字を
#     区別せずに引き（{"Name": …} の .name が取れる）、最上位の配列を展開して要素の name を返し、日時らしい
#     文字列を DateTime に変え、末尾のカンマや引用符の無いキーも受け付ける。JsonDocument は厳格な JSON で、
#     名前の一致は大文字小文字を区別し、重複キーは最後の値を返す（python の json と同じ）。
function Get-PluginJsonName([string]$path) {
  try {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $off = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes, $off, $bytes.Length - $off)
    $doc = [System.Text.Json.JsonDocument]::Parse($text)
    try {
      $p = [System.Text.Json.JsonElement]::new()
      if ($doc.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Object -and
          $doc.RootElement.TryGetProperty('name', [ref]$p) -and
          $p.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
        return $p.GetString()
      }
    } finally { $doc.Dispose() }
  } catch {
    return $null   # 読めない（呼び出し側の 2-a が中止する）
  }
  return $null
}

# 開発リポの位置はスクリプトの場所から解決する（CWD に依存させない。別リポジトリ内から
# 実行して、そのリポのプラグインを publish してしまう事故を防ぐ）。
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$DevRoot = (Resolve-Path (Join-Path $Here '..')).Path
git -C $DevRoot rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) { Write-Err "‼ 開発リポジトリが見つからない: $DevRoot"; exit 2 }

# marketplace の検査: .git が「ディレクトリ」であること（submodule の .git はファイル＝gitlink）。
# -PathType Container を付けないと gitlink にも Test-Path が true を返し、submodule の checkout を
# 配布先に指定できてしまう。ミラー処理が .git を壊し、親リポジトリへ commit/push する事故になる。
if (-not (Test-Path -LiteralPath (Join-Path $Marketplace '.git') -PathType Container)) {
  Write-Err "‼ marketplace リポジトリが見つからない: $Marketplace"
  Write-Err '   .git がディレクトリである独立クローンを指定してください（submodule の checkout は不可）。'
  exit 2
}
# ルート判定は --show-prefix の空判定で行う（パス文字列の比較は表記揺れで壊れる）。
$mktPrefix = (git -C $Marketplace rev-parse --show-prefix 2>$null)
if ($LASTEXITCODE -ne 0) { Write-Err "‼ marketplace が git リポジトリではない: $Marketplace"; exit 2 }
if ($mktPrefix -and $mktPrefix.Trim() -ne '') {
  Write-Err "‼ marketplace はリポジトリのルートを指す必要があります: $Marketplace"
  Write-Err "   （リポジトリ内のサブディレクトリを指しています: $($mktPrefix.Trim())）"
  exit 2
}

# marketplace の plugins/ に、大文字小文字だけが違う既存エントリ（-Name Foo に対する plugins\foo）があれば中止する。
# Windows（と macOS の既定）のファイルシステムは大文字小文字を区別しないため plugins\Foo が既存の plugins\foo を指し、
# 後段のミラー（.git 以外を全削除）が別の plugin を消す（末尾の . を拒否したのと同じ故障クラス）。大文字小文字を
# 区別する OS で publish しても、Windows / macOS の clone では 2 つのフォルダが衝突する。
# 存在検査（Test-Path plugins\Foo）では判定しない。それ自体が大文字小文字を無視して真になるため、エントリ名を
# 列挙して文字列で比べる。畳むのは ASCII だけ（名前は ASCII に限定済みで、bash 版の tr と結果を揃えるため）。
# 完全一致のエントリ（通常の更新）は通す。破壊的な操作より前、取り出しや validate より前に判定する。
$pluginsDir = Join-Path $Marketplace 'plugins'
if (Test-Path -LiteralPath $pluginsDir -PathType Container) {
  $lname = $Name.ToLowerInvariant()
  foreach ($e in @(Get-ChildItem -Force -LiteralPath $pluginsDir)) {
    if ($e.Name -ceq $Name) { continue }
    if ($e.Name -cmatch '^[\x00-\x7F]*\z' -and $e.Name.ToLowerInvariant() -ceq $lname) {
      Write-Err "‼ marketplace の plugins/ に大文字小文字だけが違う既存エントリがある: '$($e.Name)'（plugin 名 '$Name'）。publish 中止"
      Write-Err '   Windows / macOS では同じフォルダを指し、ミラーが別の plugin を消します。既存の名前に揃えるか、別の名前にしてください。'
      exit 2
    }
  }
}

git -C $DevRoot rev-parse --verify "$Ref^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { Write-Err "‼ ref が存在しない: $Ref"; exit 2 }

# 0. symlink（mode 120000）を含む ref は publish しない。zip 経由の本版は symlink を
#    「ターゲットのパス文字列を中身とする通常ファイル」として配布してしまう（件数照合もすり抜ける）。
$links = @(git -C $DevRoot ls-tree -r $Ref -- $Plugin |
  Where-Object { $_ -match '^120000\s' } |
  ForEach-Object { ($_ -split "`t", 2)[1] })
if ($links.Count -gt 0) {
  Write-Err '‼ plugin に symlink が含まれている。publish 中止（配布先で壊れたファイルになる）:'
  $links | ForEach-Object { Write-Err "   $_" }
  exit 1
}

$tmp = Join-Path $env:TEMP ('pubplugin_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  # 1. 追跡ファイルのみを ref から取り出し（checkout 不要・個人/未追跡は構造的に除外）
  #
  #    ⚠ tar ではなく zip を使う。PowerShell から呼ばれる tar は C:\Windows\System32\tar.exe
  #       （bsdtar）で、UTF-8 の日本語ファイル名を黙って取りこぼす。欠落したまま publish すると
  #       ミラー処理が「payload に無い」と見なして配布先の該当ファイルを削除する。
  #    ⚠ core.autocrlf を無効化する。git archive は working-tree 変換（text/eol 属性 ＋
  #       core.autocrlf）を適用するため、付けないと publisher のローカル設定で中身が変わる
  #       （Git for Windows の既定は autocrlf=true）。bash 版と対称にすること。
  $zip = Join-Path $tmp 'plugin.zip'
  git -c core.autocrlf=false -C $DevRoot archive $Ref $Plugin --format=zip -o $zip
  if ($LASTEXITCODE -ne 0) { Write-Err "‼ $Ref から $Plugin を取り出せない（パス誤り? 未コミット?）"; exit 1 }
  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force   # → $tmp\$Plugin\
  $src = Join-Path $tmp $Plugin

  # 2. 安全弁: 空 / manifest 不在なら中止
  if (-not (Test-Path $src) -or -not (Get-ChildItem -Force $src)) { Write-Err "‼ $Ref の $Plugin が空。中止"; exit 1 }
  if (-not (Test-Path (Join-Path $src '.claude-plugin/plugin.json'))) {
    Write-Err "‼ $Plugin/.claude-plugin/plugin.json が無い（plugin ではない?）。中止"; exit 1
  }

  # 2-a. marketplace 側の名前（-Name）と plugin.json の name が一致しなければ中止する（bash 版と同じ文言・終了コード）。
  #      警告だけでは止まらない: -Name を誤ると、後段のミラー（plugins\<名前> の .git 以外を全削除してコピー）が
  #      別の plugin の中身を置き換えたまま公開 push まで進む（例: statusline の資材を -Name pre-compact で publish）。
  #      name を読めない場合も、照合できないので中止する。比較は序数（ordinal）の完全一致
  #      （-cne はカルチャ依存の比較で、無視される文字を含む値を一致とみなしうる）。
  $mname = Get-PluginJsonName (Join-Path $src '.claude-plugin/plugin.json')
  if ($null -eq $mname) {
    Write-Err "‼ $Plugin/.claude-plugin/plugin.json の name を読めない（UTF-8 / JSON として不正・最上位がオブジェクトでない・name が無いか文字列でない）。中止"
    exit 1
  }
  if (-not [string]::Equals($mname, $Name, [StringComparison]::Ordinal)) {
    Write-Err "‼ $Plugin/.claude-plugin/plugin.json の name（'$mname'）と marketplace 側の名前（'$Name'）が違う。中止"
    Write-Err "   このまま進むと、ミラーが marketplace の plugins/$Name をこの plugin の中身で置き換えて公開します。"
    Write-Err '   どちらが正しいか確かめ、marketplace 側の名前（marketplace.json のエントリ名も）と plugin.json の name を揃えてください。'
    exit 1
  }

  # 2-b. 安全弁: 展開したファイル数が ref の追跡ファイル数と一致するか（fail-closed）
  $expected = (git -C $DevRoot ls-tree -r --name-only $Ref -- $Plugin | Measure-Object).Count
  $actual   = (Get-ChildItem -Recurse -File -Force -LiteralPath $src | Measure-Object).Count
  if ($actual -ne $expected) {
    Write-Err "‼ plugin の展開に失敗（期待 $expected ファイル / 実際 $actual ファイル）。publish 中止"
    Write-Err '   ファイル名の文字コードが原因の可能性があります。'
    exit 1
  }

  # 3. ゲート: claude plugin validate（--strict）
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Err '‼ claude CLI が PATH に無い。中止'; exit 1 }
  #    終了コード: 0=合格（--strict では警告もゼロ）/ 1=不合格 / 2=validator 自体の失敗（パス不可読等）。どちらも中止。
  claude plugin validate --strict $src
  if ($LASTEXITCODE -eq 2) { Write-Err '‼ validate 自体が失敗した（パス不可読等。plugin の不合格ではない）。publish 中止'; exit 1 }
  if ($LASTEXITCODE -ne 0) { Write-Err '‼ plugin validate FAIL。publish 中止'; exit 1 }

  # 4. /security-review は対話のため手動確認
  $ok = Read-Host "→ $Name について /security-review を実行済みなら y で続行"
  if ($ok -ne 'y') { Write-Host '中止'; exit 1 }

  # 5. marketplace へミラー（<C-MKT>/plugins/<name>/ を総入れ替え。.git は保護）
  #    ⚠ robocopy /XF は使わない。ファイル名マッチが全階層に効くため、plugin 内の同名ファイル
  #       （.gitignore 等）まで除外してしまい bash 版と挙動が食い違う。bash 版と同じく
  #       「.git だけ残して消し、payload を上書きコピー」で揃える。
  #    ⚠ New-Item -ItemType Directory -Force は、パスをファイルが占有していると
  #       $ErrorActionPreference='Stop' でも**例外を投げず $null を返して黙って続行する**
  #       （実測）。その後の Get-ChildItem -LiteralPath はそのファイル自身を返すため、
  #       「dest を空にする」つもりの削除が占有ファイルを消し、Copy-Item は dest 不在の
  #       ため最初の子（.claude-plugin/）を dest へ「リネーム」してしまう。結果、階層の
  #       壊れた plugin が commit・push され「✓ publish 完了」が表示される。
  #       事前にディレクトリであることを検査し、作成後も確認する。
  $script:dest = Join-Path $Marketplace "plugins/$Name"
  if (Test-Path -LiteralPath $script:dest -PathType Leaf) {
    Write-Err "‼ 配布先 $script:dest がディレクトリではない（ファイルが占有している）。publish 中止"; exit 1
  }
  New-Item -ItemType Directory -Force -Path $script:dest | Out-Null
  if (-not (Test-Path -LiteralPath $script:dest -PathType Container)) {
    Write-Err "‼ 配布先ディレクトリを作れない: $script:dest。publish 中止"; exit 1
  }
  Get-ChildItem -Force -LiteralPath $script:dest |
    Where-Object { $_.Name -ne '.git' } |
    Remove-Item -Recurse -Force
  Get-ChildItem -Force -LiteralPath $src | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $script:dest -Recurse -Force
  }

  # 5-b. 出口検査: コピーしたファイル数が payload と一致するか（2-b と対称の fail-closed）
  $copied = (Get-ChildItem -Recurse -File -Force -LiteralPath $script:dest |
    Where-Object { $_.FullName -notlike (Join-Path $script:dest '.git*') } | Measure-Object).Count
  if ($copied -ne $expected) {
    Write-Err "‼ ミラーの結果が payload と一致しない（payload $expected / 配布先 $copied）。publish 中止"
    exit 1
  }
} finally { Remove-Item -Recurse -Force $tmp }

# 6. commit & push（失敗を握りつぶさない。publish 未完了なのに ✓ を出さない）
git -C $Marketplace add -A
if ($LASTEXITCODE -ne 0) { Write-Err '‼ add 失敗。publish 中止'; exit 1 }
git -C $Marketplace diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host '変更なし。publish 不要'; exit 0 }
$short = (git -C $DevRoot rev-parse --short $Ref).Trim()
git -C $Marketplace commit -m "publish: sync plugin '$Name' from <Dev>@$short (ref: $Ref)"
if ($LASTEXITCODE -ne 0) { Write-Err '‼ commit 失敗。publish は完了していない'; exit 1 }
git -C $Marketplace push
if ($LASTEXITCODE -ne 0) {
  Write-Err '‼ push 失敗。publish は完了していない（marketplace にローカルコミットが残っている）'
  Write-Err "   認証・保護ブランチ設定を確認し、$Marketplace で push し直してください。"
  exit 1
}

Write-Host "✓ plugin '$Name' を $script:dest へ publish 完了（ref: $Ref）。"
Write-Host "  ※ <C-MKT>/.claude-plugin/marketplace.json に '$Name' エントリがあるか確認してください（本スクリプトは marketplace.json を編集しません）。"
