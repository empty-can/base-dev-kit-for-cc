# =============================================================================
# start_claude_code.ps1  ―  Claude Code ランチャー本体（PowerShell 版）
# =============================================================================
# これ一つで、統制された環境変数と起動オプションが適用された状態で claude を起動する。
# 設定した環境変数（$env:）はこのプロセスと子プロセス（claude）にのみ効くローカルスコープで、
# OS の環境変数や他アプリには影響しない。
#
# 読み込み関係:
#   start_claude_code.ps1
#     ├─ setup-environment.ps1  → custom.env をロード＋チーム/組織統制 env を後勝ち固定
#     └─ option-settings.ps1    → 利用者可変の起動オプション（$Opts）
#   ＋ 本ファイル内の $TeamOpts → チーム統制の起動オプション（分類C）
#   組立順は claude <$Opts> <$TeamOpts> [--] <起動時引数>。各ハッシュは書いた順（[ordered]）で並べる
#   （bash 版はキーの辞書順）。
#
# 出力の約束: ランチャー（本ファイルと setup-environment）自身の警告・エラーはすべて stderr に書く。stdout は claude の
#   出力だけにする（claude -p の結果を読むスクリプトに混ざらないように。bash 版も同じ）。
# ⚠ これは利用者が端末から起動するランチャーで、CLAUDE_CODE_PROCESS_WRAPPER / processWrapper に登録するもの
#    ではない。登録しても契約を満たさない（Claude Code の引数に起動オプションを足す、起動前に警告を出しうる。
#    PS 版は exec しない）うえ、Windows ではその設定自体が無視される。必要なら別の薄いスクリプトを作る
#    （契約: https://code.claude.com/docs/en/corporate-launcher#the-launcher-contract）。
# ⚠ プロンプトを起動時引数で渡すなら、フラグはすべてプロンプトより前に置くこと。値を複数取るフラグ
#    （--add-dir / --mcp-config / --tools 等）や値を省略できるフラグ（--debug / --resume 等）が組み立てた
#    オプションの最後に来ると、直後のプロンプトを値として取り込む（v2.1.302 で実測）。ランチャーは起動時引数が
#    全部 - で始まらない（＝プロンプトだけ）ときに限り -- を補う。"<prompt>" -p のような混在は補わない。
#    PowerShell では裸の -- はこのスクリプトに届く前に消える。自分で渡すなら '--' と引用する。
# ⚠ ここで設定する env が確実に届くのは、このランチャーが起動した foreground の claude だけ。
#    background セッション（/bg・← で送ったもの、claude --bg、agent view から dispatch したもの）は
#    background service（supervisor）配下の別プロセスとして起動し直され、構成を「そのディレクトリの
#    settings（env ブロックを含む）＋引き継がれた構成フラグ」から読む。起動元のシェルから届く env は
#    公式に列挙されたものだけ（PATH / CLAUDE_CODE_USE_BEDROCK・CLAUDE_CODE_USE_VERTEX /
#    ANTHROPIC_DEFAULT_*_MODEL / CLAUDE_CODE_EXTRA_BODY。ゲートウェイ変数は条件付き）。
#    それ以外の env（custom.env・setup-environment の値の大半）は dispatch 元ではなく supervisor の env から
#    受け継がれる（2026-10-20 Windows で実測）。supervisor は全端末で共有され、それを立ち上げたプロセスの env を継承する
#    ため、届くかは起動順次第で確実ではない ―― このランチャーから起動した claude が supervisor を立ち上げると、
#    以後は別の端末から dispatch した background セッションにも届き、dispatch 元に同名の値があっても supervisor
#    側の値が使われる。素のシェル等が先に立ち上げていると、このランチャー経由の claude --bg でも届かない
#    （例: CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD が欠け、--add-dir だけが引き継がれる）。
#    その env は supervisor が止まるまで（claude daemon stop --any 等）使われ、auto-update による自己再起動でも変わらない。
#    background にも効かせたい値は OS の環境変数（永続的なユーザー環境変数。Windows はユーザー環境変数、
#    macOS / Linux はログインシェルの profile）で設定すること。supervisor は最初に起動したシェルの env を
#    継承するので、どの端末から起動されても届く（既に動いている service には、それが起動した時点の env が使われる）。
#    公式 docs は ~/.claude/settings.json の env を勧めるが、キットは利用者に settings 系ファイルの
#    env を使わせない（誤って commit / push する、Claude から読める場所に値が残る、を避けるため）。組織で固定する値だけは managed settings の env（管理者の経路）に置く。
#    起動オプションは構成フラグ（--settings / --setting-sources / --add-dir / --plugin-dir / --mcp-config /
#    --strict-mcp-config / --fallback-model / --allow-dangerously-skip-permissions）だけが background へ引き継がれる。
#    参照: https://code.claude.com/docs/en/agent-view#settings-and-provider
# ⚠ サブコマンド（agents / remote-control など）はこのランチャー経由で起動しないこと。組み立てた起動
#    オプションが verb の「前」に付くため、remote-control は --settings 等が前にあると起動を拒否し、
#    agents は --add-dir / --mcp-config が前にあると `claude agents --json` が unknown option で失敗する
#    （claude --bg "<prompt>" のようなフラグ形式の background 起動は問題ない）。
# =============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootDir = $PSScriptRoot

# ---- 0) 実行要件の確認 ------------------------------------------------------
# .claude/ は submodule。--recurse-submodules なしで clone すると空になるため、
# 存在チェックなしで dot-source すると理由の分からないエラーになる。
# エラー出力は Write-Error を使わない。$ErrorActionPreference='Stop' の下では Write-Error が
# 終端エラーになり、直後の `exit 1` に到達しないまま例外として抜けてしまう（終了コードも
# 意図した 1 にならない）。stderr へ直接書いて exit する（bash 版の `printf >&2; exit 1` と対称）。
$SetupEnv = Join-Path $RootDir '.claude\launcher\setup-environment.ps1'
if (-not (Test-Path $SetupEnv)) {
    [Console]::Error.WriteLine(@"
$SetupEnv が見つかりません。
.claude/ が submodule として未初期化の可能性があります:
  git submodule update --init --recursive
"@)
    exit 1
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine(@"
claude コマンドが見つかりません（未インストール、または PATH 未設定）。
導入手順: https://code.claude.com/docs/en/quickstart
"@)
    exit 1
}

# ---- 1) 環境変数セットアップ（custom.env + 統制 env 後勝ち）------------------
# setup-environment の警告（Write-Warning）は stderr へ回す。PowerShell は別のプログラムから起動されると
# warning / information ストリームを stdout に書く（pwsh 7・Windows PowerShell 5.1 とも 2026-10-24 に実測）ため、
# そのままでは claude -p の出力を読むスクリプトに警告が混ざる。stdout は claude の出力だけにする（bash 版は最初から
# >&2。corporate-launcher の「起動前に標準出力へ書かない」と同じ理由）。dot-source はパイプラインの中でもこの
# スコープで動き、setup-environment の例外は従来どおりここで止まる。setup-environment.ps1 側は Write-Warning のまま
# にする（verify-kit が直接 dot-source して warning ストリームで警告を受けている）。
. $SetupEnv 3>&1 6>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.WarningRecord]) {
        [Console]::Error.WriteLine("警告: $($_.Message)")
    } else {
        [Console]::Error.WriteLine("$_")
    }
}

# ---- 2) チーム統制の起動オプション（分類C）--------------------------------
# チームで揃えたい起動オプションはここに定義する（利用者は触らない）。
# 値を取らないフラグは値を $true にする。
#
# 統制の強さ: これは「既定値をチームで揃える」ための仕組みであって、強制力はない。
#   - 値を 1 つだけ取るフラグは $TeamOpts が後段に付くためチーム値が後勝ちになる
#   - ただし起動時引数（@args）はさらに後ろに付くので、利用者が明示指定すれば上書きできる
#   - --add-dir のような反復可能フラグは上書きされず両方の値が渡る（累積する）
#   - 例外: --append-system-prompt とその -file 版は上書きではなく両方が使われる（v2.1.283 以降）。
#     --append-subagent-system-prompt とその -file 版は併用できない（$Opts と $TeamOpts に分けて書くとエラー）
# 強制したい統制は settings.json / managed settings 側で行うこと。ただし permissions.defaultMode の
#   auto / bypassPermissions はプロジェクトの .claude/settings.json / settings.local.json では無視される
#   （効かせるなら ~/.claude/settings.json または managed settings）。--permission-mode フラグは
#   settings の defaultMode より優先される。
$TeamOpts = [ordered]@{
    # '--setting-sources' = 'project,user'
}

# ---- 3) 利用者可変の起動オプション（分類D・option-settings.ps1）------------
$Opts = [ordered]@{}
$OptsFile = Join-Path $RootDir '.claude\option-settings.ps1'

# 利用者が誤って launcher\ 側（テンプレートの隣）へ option-settings.ps1 を置いた場合、
# そのままでは無警告で無視され、起動オプションが一切効かない理由に到達できない。
# custom.env と同じガードを張る（片方だけ守るのは、探すべき場所を一つ増やすだけ）。
# 警告は 1) と同じ理由で Write-Warning ではなく stderr へ書く（bash 版の printf >&2 と対称）。
$MisplacedOpts = Join-Path $RootDir '.claude\launcher\option-settings.ps1'
if (Test-Path $MisplacedOpts) {
    [Console]::Error.WriteLine("警告: $MisplacedOpts は読み込まれません。option-settings.ps1 は一つ上の .claude\ 直下に置いてください。")
}

if (Test-Path $OptsFile) {
    . $OptsFile   # $Opts を定義（未作成なら空のまま）
}

# option-settings（$Opts）と $TeamOpts の --add-dir がネットワークパス（UNC）の形なら起動前に警告する（止めない）。
# Claude Code は起動時に渡されたネットワークパスを外して起動し（v2.1.257 以降）、v2.1.305 以降の対話起動ではその警告が
# デバッグログにしか出ない。<Share> を UNC で書くとキット無しで黙って起動するので、画面に出せるランチャーが知らせる。
# チームが <Share> を固定するのは $TeamOpts なので、そこも同じ判定で見る（2026-10-27 の判断 J-3。それまでは option-settings
# だけ）。警告文の先頭で値の出どころ（option-settings か $TeamOpts か）を示し、順は $Opts → $TeamOpts（bash 版と同じ）。
# 判定は綴りだけ（\\ か // で始まるか。解決するとネットワークへ触れてしまう）。起動時引数の --add-dir は見ない（利用者が
# 並べた引数は守らない。設計 §5-3 の責任分界）。'--add-dir=<パス>' のような = 形のキーも見ない（キーが '--add-dir' そのものの
# 値だけ。設計 §5-4）。bash 版と同じ文言（出どころの表記も同じ。単一引用符なので $TeamOpts は展開されない。前置きは 1) と
# 同じ「警告: 」）。
$uncSources = [ordered]@{
    'option-settings' = $Opts
    'start_claude_code のチーム統制（TEAM_OPTS / $TeamOpts）' = $TeamOpts
}
foreach ($uncFrom in $uncSources.Keys) {
    $uncMap = $uncSources[$uncFrom]
    if (-not $uncMap.Contains('--add-dir')) { continue }
    $addDir = [string]$uncMap['--add-dir']
    if ($addDir.StartsWith('\\', [StringComparison]::Ordinal) -or $addDir.StartsWith('//', [StringComparison]::Ordinal)) {
        [Console]::Error.WriteLine("警告: $uncFrom の --add-dir $addDir はネットワークパスの形です。ネットワークパスは v2.1.257 以降拒否され、v2.1.305 以降は警告がデバッグログにしか出ないため、Claude Code はこのディレクトリを黙って外して起動します。ドライブ文字に割り当てて指定してください。")
    }
}

# option-settings（$Opts）と $TeamOpts に、キットの前提が黙って崩れる起動オプション（区分 1）があれば起動前に警告する（止めない）。
# 2026-10-30 の作業指示者決定（設計 §5-4）。対象は下の表のキー（キットの settings.json の permissions.deny・hooks や CLAUDE.md /
# rules が読まれないまま起動する）と、--setting-sources の値に project が無い場合（キットの .claude/settings.json が読まれない）。
# --setting-sources は値を [string] にしてカンマで分け、前後の空白を除いた要素に project（大文字小文字を区別した完全一致）が
# 無ければ警告する（$true は 'True' になり、project が無いので警告する）。未設定は既定で全ソースを読むので対象外。
# 警告するだけでキーは捨てない（そのまま claude へ渡す）。1 検出 = stderr 1 行で、前置き・出どころの表記・出どころの順
# （$Opts → $TeamOpts）は上の UNC 検査と同じ。出どころの中は表の順、最後に --setting-sources。出どころごとに独立に判定する
# （$Opts と $TeamOpts を合成した実効値は見ない。UNC 検査と同じ責任分界）。起動時引数と '--bare=…' のような = 形のキーは
# 見ない（設計 §5-3・§5-4）。キーの照合は UNC 検査と同じ Contains で、大文字小文字を区別しない（'--Bare' も警告する）。
# チームとして禁じるなら managed settings で固定する（ランチャーの統制には強制力が無い）。
# bash 版は凍結中で未追随（SH-DEFER-01。docs/launcher/sh-freeze-backlog.md）。
$kitBreakingOpts = [ordered]@{
    '--restricted'         = 'user・project・local の settings を読まずに起動するため、キットの permissions.deny も hooks も効きません'
    '--bare'               = 'settings は読みますが hooks・CLAUDE.md・skills を読まないため、キットの hooks（.bat 保護を含む）も CLAUDE.md も効きません'
    '--safe-mode'          = 'settings は読みますが hooks・CLAUDE.md・skills を読まないため、キットの hooks（.bat 保護を含む）も CLAUDE.md も効きません'
    '--system-prompt'      = '既定のシステムプロンプトを丸ごと置き換えるため、キットの前提（CLAUDE.md / rules のロード）が崩れます'
    '--system-prompt-file' = '既定のシステムプロンプトを丸ごと置き換えるため、キットの前提（CLAUDE.md / rules のロード）が崩れます'
}
$omitTail = 'そのまま渡して起動します（止めません）。チームで禁じるなら managed settings で固定してください。'
foreach ($omitFrom in $uncSources.Keys) {
    $omitMap = $uncSources[$omitFrom]
    foreach ($omitKey in $kitBreakingOpts.Keys) {
        if ($omitMap.Contains($omitKey)) {
            [Console]::Error.WriteLine("警告: $omitFrom の $omitKey は、$($kitBreakingOpts[$omitKey])。$omitTail")
        }
    }
    if ($omitMap.Contains('--setting-sources')) {
        $srcRaw = [string]$omitMap['--setting-sources']
        $srcParts = @($srcRaw.Split(',') | ForEach-Object { $_.Trim() })
        if (-not ($srcParts -ccontains 'project')) {
            [Console]::Error.WriteLine("警告: $omitFrom の --setting-sources $srcRaw に project が含まれません。キットの .claude/settings.json（permissions.deny・hooks）と、--add-dir で足したディレクトリの skill 等が読まれません。$omitTail")
        }
    }
}

# ---- 4) claude コマンドを組み立て ------------------------------------------
# $TeamOpts を後に置くことで、同じフラグを $Opts にも書いた場合はチーム値が後勝ちする。
$cliArgs = [System.Collections.Generic.List[string]]::new()
foreach ($map in @($Opts, $TeamOpts)) {
    foreach ($k in $map.Keys) {
        $v = $map[$k]
        $cliArgs.Add([string]$k)
        # 値が空 / $true / 'true' のものは値なしフラグとして扱う
        if ($null -ne $v -and "$v" -ne '' -and "$v" -ne 'true' -and $v -ne $true) {
            $cliArgs.Add([string]$v)
        }
    }
}

# 値を複数取る／値を省略できるフラグが $cliArgs の最後だと、直後のプロンプトを値として取り込む（冒頭の注意）。
# 起動時引数が全部非フラグ（＝プロンプトだけ）のときに限り -- で区切る。フラグを含む場合（混在を含む）は
# 素の claude と同じく利用者の並べ方に任せる。組み立てたオプションが無いときは素の claude と同じ引数列にする。
# -- は配列の要素として渡す。コマンド行に直接 -- と書くと、claude が .ps1（npm のシム等）に解決されたとき
# PowerShell のパラメータバインダに消される（配列要素の '--' は pwsh 7 / 5.1 とも残る。実測）。
if ($cliArgs.Count -gt 0 -and $args.Count -gt 0) {
    $onlyPositional = $true
    foreach ($userArg in $args) {
        if ("$userArg".StartsWith('-')) {
            $onlyPositional = $false
            break
        }
    }
    if ($onlyPositional) {
        $cliArgs.Add('--')
    }
}

# ---- 5) 起動（追加引数はそのまま claude へ委譲）------------------------------
$argsArray = $cliArgs.ToArray()
# ⚠ 起動直前に $LASTEXITCODE を 0 へ初期化する。claude が .ps1 ラッパーに解決されると $LASTEXITCODE が設定されず、
#    呼び出し元の対話セッションに残っていた古い値（直前に失敗した git 等）をそのまま返してしまうため。
$global:LASTEXITCODE = 0
& claude @argsArray @args

# claude の終了コードをそのまま返す（ヘッドレス実行・CI で失敗を検知できるようにする）。
# ⚠ 上の初期化により、ラッパー経由で $LASTEXITCODE が設定されなくても 0 になる（古い値は返さない）。
#    Set-StrictMode 下の未定義変数参照で落ちないよう、存在を確かめてから返す（Test-Path は念のため残す）。
if (Test-Path Variable:LASTEXITCODE) { exit $LASTEXITCODE } else { exit 0 }
