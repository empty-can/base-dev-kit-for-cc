<#
.SYNOPSIS
  verify-kit.ps1 — bash 版と PowerShell 版のスクリプトを実際に走らせ、結果の一致を検査する

.DESCRIPTION
  ルート CLAUDE.md の「bash 版と PowerShell 版は両方直し、両版を実際に走らせて結果が一致することを
  確認する」をスクリプトで担保する。verify-kit.sh と対称で、どちらから呼んでも同じ系統
  （bash / pwsh 7 / Windows PowerShell 5.1）を駆動し、同じ判定を出す。
    構成: 各版は「自系統で実スクリプトを走らせ、正規化した結果をファイルへ書く probe」を持つ。
          比較役（-Probe なしで起動した側）は全系統の probe を子プロセスで呼び、結果を突き合わせる。
          入力と期待値は verify-kit.d\（UTF-8・LF・BOM なし）を両版で共有する。
  FAIL が 1 件以上で終了コード 1、なければ 0（CI 利用可）。

  安全上の約束（手作業の検証で、Git Bash の PATH に Windows 形式のパスを渡したため実物の claude が
  2 回起動した。以下はコードで強制している）:
    - 実物の claude を起動するのは --version だけ。同じ一時ツリー・同じ引数を先にスタブで流し、
      claude に届く引数が "--version" 1 個だけであることを確かめてから実物を呼ぶ。
    - それ以外はスタブ（claude.ps1 / git.ps1）。スタブのディレクトリと System32 だけの PATH で実行し、
      起動前に Get-Command の解決先がスタブであることを確かめる。
    - リポジトリの .claude\ には何も作らない。ランチャーと setup-environment は一時ツリーへ
      コピーしてから実行する（どちらも $PSScriptRoot からルートを解決する）。
    - publish-plugin は -Name 検証が git / ファイル書き込みより前にあることを確かめたうえで、
      名前検証で止まるケースと、その直後の副作用の無い前提条件（存在しない marketplace）で止まる
      ケースだけを、git と claude をスタブにした PATH で実行する。大文字小文字違いの検査は一時ディレクトリの
      偽 marketplace に対して同じスタブの PATH で実行する（中止されなくても、スタブの git は何も出力しない
      ため取り出しで止まり、ミラーには到達しない。一時ファイルもケースのディレクトリの中に作らせる）。
    - publish-plugin の plugin.json の name 照合（2-a）は、取り出しまで進ませるため実物の git を使う。対象は
      一時ディレクトリに作ったリポジトリだけ: 開発リポは publish-plugin のコピーと plugin.json を 1 コミットした
      一時リポジトリ（スクリプトは自身の位置から開発リポを決める）、marketplace は remote の無い一時リポジトリ。
      claude だけのスタブディレクトリ・実物の git のディレクトリ・System32 の PATH で、標準入力を閉じた子プロセスの
      pwsh として実行し、起動前に claude の解決先がスタブ、git の解決先が実物、marketplace に remote が無いことを
      確かめる。照合を通っても確認プロンプト（Read-Host）は空を受け取って止まる。git の設定は空の一時ファイルに
      隔離する（global / system を読まない）。
    - check-assets の追跡基準（git 層）の fixture も実物の git を使うが、対象は一時ディレクトリに作ったリポジトリだけで、
      書くのはその中の init / add / commit だけ（check-assets 自身は読むだけ）。git の設定は同じく隔離する。
    - 実スクリプトを呼ぶ。実スクリプトで検査できない項目は再実装で代用せず SKIP にする。

.PARAMETER Probe
  （内部用）自系統（この PowerShell）の probe を実行し、結果を -Out へ書く。

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-kit.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-kit.ps1 -Verbose
#>
[CmdletBinding()]
param(
  [switch]$Probe,
  [string]$Out = ''
)
# ⚠ Set-StrictMode は使わない。検査対象のスクリプトを & で呼ぶため、ここで有効にすると
#    呼び先（check-assets.ps1 等）にまで効いて、実運用と違う条件で検査することになる。
$ErrorActionPreference = 'Continue'

$VkScripts = $PSScriptRoot
$VkRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$VkFix = Join-Path $PSScriptRoot 'verify-kit.d'
$VkSh = Join-Path $PSScriptRoot 'verify-kit.sh'
$VkSelf = $PSCommandPath
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$Utf8Bom = New-Object System.Text.UTF8Encoding $true
$OnWindows = ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows
$PathCmp = if ($OnWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$HostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

if (-not (Test-Path -LiteralPath $VkFix -PathType Container)) { Write-Host "‼ fixture ディレクトリが無い: $VkFix"; exit 2 }

# rel は / 区切り。Windows では GetFullPath が \ へ揃える（Parser へは Windows 形式の絶対パスを渡すため）。
function Join-Full([string]$base, [string]$rel) { [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($base, $rel)) }
function Read-Lines([string]$path) { [System.IO.File]::ReadAllLines($path, $Utf8NoBom) }
# 値の一致判定は序数（ordinal）で行う。-ceq / -cne / -ccontains はカルチャ依存で、pwsh 7 ではゼロ幅文字（U+200B）だけが
# 違う文字列を等しいと判定する（bash 側の cmp はバイト比較なので、pwsh 側の比較だけが差を見逃す）。
function Oeq($a, $b) { [string]::Equals([string]$a, [string]$b, [StringComparison]::Ordinal) }
function One($a, $b) { -not [string]::Equals([string]$a, [string]$b, [StringComparison]::Ordinal) }
function Oin($arr, $x) { foreach ($e in @($arr)) { if ([string]::Equals([string]$e, [string]$x, [StringComparison]::Ordinal)) { return $true } }; return $false }
function Onin($arr, $x) { -not (Oin $arr $x) }
function Same-Path([string]$a, [string]$b){ [string]::Equals($a, $b, $PathCmp) }
function Resolve-Cmd([string]$name) {
  $c = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c -and $c.Source) { return [string]$c.Source } else { return '' }
}

# 子プロセスを起動して終了コードと出力（UTF-8 として読む）を返す。標準入力は閉じる。
# 引数は Windows のコマンドライン規則（CommandLineToArgvW）で引用する。
function ConvertTo-ArgString([string[]]$argv) {
  $parts = foreach ($a in $argv) {
    if ($a -ne '' -and $a -notmatch '[\s"]') { $a; continue }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $a.ToCharArray()) {
      if ($ch -eq '\') { $bs++; continue }
      if ($ch -eq '"') { [void]$sb.Append('\' * (2 * $bs + 1)).Append('"'); $bs = 0; continue }
      if ($bs -gt 0) { [void]$sb.Append('\' * $bs); $bs = 0 }
      [void]$sb.Append($ch)
    }
    [void]$sb.Append('\' * (2 * $bs)).Append('"')
    $sb.ToString()
  }
  return ($parts -join ' ')
}
function Invoke-Proc([string]$exe, [string[]]$argv, [int]$timeoutMs = 300000, [string]$cwd = '') {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = ConvertTo-ArgString $argv
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8NoBom
  $psi.StandardErrorEncoding = $Utf8NoBom
  if ($cwd) { $psi.WorkingDirectory = $cwd }
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Close()
  $so = $p.StandardOutput.ReadToEndAsync()
  $se = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($timeoutMs)) {
    # プロセスツリーごと止める。$p.Kill() は直接の子（ランチャーを動かす PowerShell 等）しか止めず、その先の
    # 実物 claude --version などが残る（実測: 孫プロセスが生き残った）。Kill($true) は .NET Core 3.0 以降
    # （pwsh 7）にしか無いので、5.1 では taskkill /T へフォールバックする。
    $killed = $false
    if ($PSVersionTable.PSVersion.Major -ge 7) {
      try { $p.Kill($true); $killed = $true } catch { }
    }
    if (-not $killed -and $OnWindows) {
      try { & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $p.Id /T /F *> $null } catch { }
    }
    try { if (-not $p.HasExited) { $p.Kill() } } catch { }
    return New-Object psobject -Property @{ Rc = -1; Out = ''; Err = "timeout（$timeoutMs ms）"; TimedOut = $true }
  }
  $p.WaitForExit()
  return New-Object psobject -Property @{ Rc = $p.ExitCode; Out = $so.Result; Err = $se.Result; TimedOut = $false }
}

# =============================================================================
# probe（自系統で実スクリプトを走らせ、正規化した結果を -Out へ書く）
#   行は「タグ<TAB>値」、節は「@@ 名前」。最後に「@@ end」を書く（無ければ比較役は異常終了とみなす）。
#   出力の形式・順序は verify-kit.sh の probe と揃えること。
# =============================================================================
$script:ProbeOut = New-Object 'System.Collections.Generic.List[string]'
function Sec([string]$n) { $script:ProbeOut.Add("@@ $n") }
function Put([string]$tag, [string]$v) { $script:ProbeOut.Add("$tag`t$v") }

# 行に from→to の置換（リテラル）を施し、最後に \ を / へ揃える（bash 版の vk_norm と同じ）
function Norm([string]$line, [string[]]$pairs) {
  $l = $line.TrimEnd("`r")
  for ($i = 0; $i + 1 -lt $pairs.Count; $i += 2) {
    if ($pairs[$i]) { $l = $l.Replace($pairs[$i], $pairs[$i + 1]) }
  }
  return $l.Replace('\', '/')
}

# スタブ（実物の代わりに、受け取った引数を 1 行 1 引数で <名前>.args へ、環境を <名前>.env へ書く）。
# 中身は ASCII だけにする（5.1 は BOM なしの .ps1 を ANSI で読む）。
function New-Stub([string]$name) {
  $body = @'
# verify-kit stub: records its arguments and environment instead of running the real @NAME@
$d = $env:VERIFY_KIT_STUB_DIR
if (-not $d) { exit 97 }
$enc = New-Object System.Text.UTF8Encoding $false
$sb = New-Object System.Text.StringBuilder
foreach ($a in $args) { [void]$sb.Append([string]$a).Append("`n") }
[System.IO.File]::WriteAllText([System.IO.Path]::Combine($d, '@NAME@.args'), $sb.ToString(), $enc)
$e = New-Object System.Text.StringBuilder
foreach ($v in @('CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD', 'CLAUDE_CODE_PLUGIN_DIRS',
                 'CLAUDE_CODE_PLUGIN_SEED_DIR', 'CLAUDE_CODE_PLUGIN_CACHE_DIR')) {
  $x = [Environment]::GetEnvironmentVariable($v)
  if ($null -eq $x) { $x = '<unset>' }
  [void]$e.Append("ENV`t" + $v + '=' + $x + "`n")
}
[void]$e.Append("CWD`t" + (Get-Location).Path + "`n")
[System.IO.File]::WriteAllText([System.IO.Path]::Combine($d, '@NAME@.env'), $e.ToString(), $enc)
[System.IO.File]::AppendAllText([System.IO.Path]::Combine($d, 'calls'), "@NAME@`n", $enc)
exit 0
'@
  [System.IO.File]::WriteAllText((Join-Full $script:Stub "$name.ps1"), $body.Replace('@NAME@', $name).Replace("`r`n", "`n"), $Utf8NoBom)
}

# スタブの PATH で、各コマンドの解決先がスタブであることを確かめる。問題なければ空文字を返す
function Test-Stubs([string[]]$names) {
  foreach ($n in $names) {
    $r = Resolve-Cmd $n
    if (-not (Same-Path $r (Join-Full $script:Stub "$n.ps1"))) {
      return "ng $n の解決先がスタブでない（$(if ($r) { $r } else { '見つからない' })）。実行しない"
    }
  }
  return ''
}

# 実物が見つからない PATH でスタブへの解決を確かめてから $action を実行する（bash 版の vk_stubbed と同じ出力）
function Invoke-Stubbed([string]$sd, [string[]]$names, [scriptblock]$action, [object]$argList) {
  New-Item -ItemType Directory -Force -Path $sd | Out-Null
  $savedPath = $env:PATH
  $savedSd = $env:VERIFY_KIT_STUB_DIR
  try {
    $env:PATH = $script:StubPath
    $env:VERIFY_KIT_STUB_DIR = $sd
    $ng = Test-Stubs $names
    if ($ng) { Put 'ASSERT' $ng; return }
    Put 'ASSERT' 'ok'
    $rc = & $action $argList
    Put 'RC' ([string]$rc)
  } finally {
    $env:PATH = $savedPath
    [Environment]::SetEnvironmentVariable('VERIFY_KIT_STUB_DIR', $savedSd)
  }
}

function Read-ArgFile([string]$f) {
  $t = [System.IO.File]::ReadAllText($f, $Utf8NoBom)
  if ($t -eq '') { return @() }
  if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
  return $t.Split("`n")
}

function Put-Args([string]$sd) { # RAN（スタブが動いた証拠＝引数ファイルの有無）と ARG を出す
  $f = Join-Full $sd 'claude.args'
  if (Test-Path -LiteralPath $f -PathType Leaf) {
    Put 'RAN' 'yes'
    foreach ($a in (Read-ArgFile $f)) { Put 'ARG' $a }
  } else {
    Put 'RAN' 'no'
  }
}

function Get-RepoFiles {
  $git = Resolve-Cmd 'git'
  if (-not $git) { return @() }
  $r = Invoke-Proc $git @('-C', $VkRoot, '-c', 'core.quotepath=false', 'ls-files', '-z', '--cached', '--others', '--exclude-standard') 120000
  if ($r.Rc -ne 0) { return @() }
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($f in $r.Out.Split([char]0)) { if ($f -ne '') { [void]$set.Add($f) } }
  $list = New-Object 'string[]' $set.Count
  $set.CopyTo($list)
  [Array]::Sort($list, [StringComparer]::Ordinal)
  return $list
}

# ---- 構文（Windows 形式の絶対パスを Parser に渡す）-------------------------------------
function Probe-Syntax {
  Sec 'syntax'
  if ($script:Files.Count -eq 0) { Put 'SKIP' 'git でファイル一覧を取得できない'; return }
  foreach ($f in $script:Files) {
    if (-not ($f.EndsWith('.ps1', 'Ordinal') -or $f.EndsWith('.ps1.template', 'Ordinal') -or
              $f.EndsWith('.psm1', 'Ordinal') -or $f.EndsWith('.psd1', 'Ordinal'))) { continue }
    $p = Join-Full $VkRoot $f
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
      Put 'NG' ("${f}: " + $errs[0].Message + "（" + $errs[0].Extent.StartLineNumber + " 行目）")
    } else {
      Put 'OK' $f
    }
  }
}

# ---- 保存形式（ReadAllBytes でバイトを数える。Get-Content / Select-String は改行を剥がすので使わない）---
function Probe-Format {
  Sec 'format'
  if ($script:Files.Count -eq 0) { Put 'SKIP' 'git でファイル一覧を取得できない'; return }
  foreach ($f in $script:Files) {
    $p = Join-Full $VkRoot $f
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    $b = [System.IO.File]::ReadAllBytes($p)
    $hex = ''
    for ($i = 0; $i -lt [Math]::Min(3, $b.Length); $i++) { $hex += $b[$i].ToString('x2') }
    $cr = 0; $lf = 0
    foreach ($x in $b) { if ($x -eq 13) { $cr++ } elseif ($x -eq 10) { $lf++ } }
    $script:ProbeOut.Add("F`t$f`t$hex`t$cr`t$lf")
  }
}

# ---- option-settings テンプレ（全項目を有効化したコピーと原本をロード）--------------------
function Probe-Optset {
  Sec 'optset'
  $tpl = Join-Full $VkRoot '.claude/launcher/option-settings.ps1.template'
  $d = Join-Full $script:PT 'optset'
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  if (-not (Test-Path -LiteralPath $tpl -PathType Leaf)) { Put 'LOAD' 'ng テンプレートが無い'; return }
  $text = [System.IO.File]::ReadAllText($tpl, $Utf8NoBom)
  Put 'LINES' ([string]([regex]::Matches($text, "(?m)^[ \t]*# '--")).Count)
  $all = Join-Full $d 'all.ps1'
  [System.IO.File]::WriteAllText($all, [regex]::Replace($text, "(?m)^([ \t]*)# ('--)", '$1$2'), $Utf8Bom)
  # ランチャーと同じ StrictMode Latest / ErrorAction Stop の下でロードする
  try {
    $keys = & { Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'; . $all; @($Opts.Keys) }
    Put 'LOAD' 'ok'
    $arr = @($keys | ForEach-Object { [string]$_ })
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    foreach ($k in $arr) { Put 'KEY' $k }
  } catch {
    Put 'LOAD' ('ng ' + ($_.Exception.Message -split "`r?`n")[0])
  }
  $orig = Join-Full $d 'orig.ps1'
  Copy-Item -LiteralPath $tpl -Destination $orig
  try {
    $n = & { Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'; . $orig; $Opts.Count }
    Put 'ORIG' "ok $n"
  } catch {
    Put 'ORIG' ('ng ' + ($_.Exception.Message -split "`r?`n")[0])
  }
}

# ---- setup-environment（一時ツリーの .claude\launcher\ で実行）--------------------------
function Get-EnvMap {
  $cmp = if ($OnWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
  $m = New-Object 'System.Collections.Generic.Dictionary[string,string]' ($cmp)
  foreach ($e in [Environment]::GetEnvironmentVariables().GetEnumerator()) { $m[[string]$e.Key] = [string]$e.Value }
  return , $m
}

function Probe-SetupEnv {
  foreach ($c in @('plain', 'bomcrlf')) {
    Sec "setupenv $c"
    $d = Join-Full $script:PT "setupenv-$c"
    $ld = Join-Full $d '.claude/launcher'
    New-Item -ItemType Directory -Force -Path $ld | Out-Null
    Copy-Item -LiteralPath (Join-Full $VkRoot '.claude/launcher/setup-environment.ps1') -Destination $ld
    $fx = [System.IO.File]::ReadAllBytes((Join-Path $VkFix 'custom.env.fixture'))
    $dst = Join-Full $d '.claude/custom.env'
    if (Oeq $c 'plain') {
      [System.IO.File]::WriteAllBytes($dst, $fx)
    } else {
      [System.IO.File]::WriteAllText($dst, $Utf8NoBom.GetString($fx).Replace("`n", "`r`n"), $Utf8Bom)
    }
    # 呼び出し元に同名の変数があると変化を観測できないので、対象の名前を先に外す（終わったら戻す）
    $saved = @{}
    foreach ($e in @([Environment]::GetEnvironmentVariables().GetEnumerator())) {
      $k = [string]$e.Key
      if ($k.ToUpperInvariant().StartsWith('VERIFY_KIT') -or $k -eq 'CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD') {
        $saved[$k] = [string]$e.Value
        [Environment]::SetEnvironmentVariable($k, $null)
      }
    }
    $before = Get-EnvMap
    $warns = New-Object 'System.Collections.Generic.List[string]'
    $err = ''
    try {
      & (Join-Full $ld 'setup-environment.ps1') 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) { $warns.Add($_.Message) }
      }
    } catch {
      $err = $_.Exception.Message
    }
    $after = Get-EnvMap
    $diff = New-Object 'System.Collections.Generic.List[string]'
    foreach ($k in $after.Keys) {
      if ($k -eq '_') { continue }
      if (-not $before.ContainsKey($k) -or (One ($before[$k]) ($after[$k]))) { $diff.Add("$k=$($after[$k])") }
    }
    foreach ($k in $before.Keys) { if ($k -ne '_' -and -not $after.ContainsKey($k)) { $diff.Add("-$k") } }
    # $env: はプロセス全体なので、実行前の状態へ戻してから退避した変数を戻す
    foreach ($k in @($after.Keys)) {
      if (-not $before.ContainsKey($k)) { [Environment]::SetEnvironmentVariable($k, $null) }
      elseif (One ($before[$k]) ($after[$k])) { [Environment]::SetEnvironmentVariable($k, $before[$k]) }
    }
    foreach ($k in @($before.Keys)) { if (-not $after.ContainsKey($k)) { [Environment]::SetEnvironmentVariable($k, $before[$k]) } }
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    if ($err) { Put 'ERR' "setup-environment.ps1 の実行に失敗した: $err"; continue }
    $arr = $diff.ToArray()
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    foreach ($l in $arr) { if ($l.StartsWith('-')) { Put 'UNSET' $l.Substring(1) } else { Put 'SET' $l } }
    foreach ($w in $warns) { Put 'WARN' $w }
  }
}

# ---- ランチャー（スタブ）と実物 --version ------------------------------------------
$script:LauncherGuard = ''
function New-Tree([string]$t, [string]$mode) { # opts なら launcher-opts.tsv から .claude\option-settings.ps1 を作る
  $ld = Join-Full $t '.claude/launcher'
  New-Item -ItemType Directory -Force -Path $ld | Out-Null
  Copy-Item -LiteralPath (Join-Full $VkRoot 'start_claude_code.ps1') -Destination $t
  Copy-Item -LiteralPath (Join-Full $VkRoot '.claude/launcher/setup-environment.ps1') -Destination $ld
  if (One $mode 'opts') { return }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("`$Opts = [ordered]@{`r`n")
  foreach ($line in (Read-Lines (Join-Path $VkFix 'launcher-opts.tsv'))) {
    if ((Oeq $line '') -or $line.StartsWith('#')) { continue }
    $i = $line.IndexOf("`t")
    $k = $line.Substring(0, $i); $v = $line.Substring($i + 1)
    if (Oeq $v 'true') { [void]$sb.Append("    '$k' = `$true`r`n") }
    else { [void]$sb.Append("    '$k' = '" + $v.Replace("'", "''") + "'`r`n") }
  }
  [void]$sb.Append("}`r`n")
  [System.IO.File]::WriteAllText((Join-Full $t '.claude/option-settings.ps1'), $sb.ToString(), $Utf8Bom)
}

function Get-Cases { # launcher-cases.txt → @{ Name; Opts; In; Out }
  $cases = New-Object 'System.Collections.Generic.List[object]'
  $cur = $null
  foreach ($line in (Read-Lines (Join-Path $VkFix 'launcher-cases.txt'))) {
    $f = $line.Split("`t")
    if (Oeq ($f[0]) 'case') {
      $cur = New-Object psobject -Property @{ 'Name' = $f[1]; 'Opts' = $f[2]
        'In' = (New-Object 'System.Collections.Generic.List[string]'); 'Out' = (New-Object 'System.Collections.Generic.List[string]') }
      $cases.Add($cur)
    } elseif ($cur -and (Oeq ($f[0]) 'in')) { $cur.In.Add($line.Substring(3)) }
    elseif ($cur -and (Oeq ($f[0]) 'out')) { $cur.Out.Add($line.Substring(4)) }
  }
  return $cases.ToArray()
}

function Probe-Launcher {
  $ldir = Join-Full $script:PT 'launcher'
  # 一時ツリーへのコピーで隔離できるのは、ランチャーが自身の位置からルートを解決しているときだけ
  $src = [System.IO.File]::ReadAllText((Join-Full $VkRoot 'start_claude_code.ps1'), $Utf8NoBom)
  if (-not $src.Contains('$RootDir = $PSScriptRoot')) {
    $script:LauncherGuard = 'ng start_claude_code.ps1 がルートを $PSScriptRoot から解決していない（一時ツリーで隔離できないため実行しない）'
  }
  New-Tree (Join-Full $ldir 'tree-opts') 'opts'
  New-Tree (Join-Full $ldir 'tree-none') 'none'
  foreach ($c in @(Get-Cases)) {
    Sec "launcher $($c.Name)"
    if ($script:LauncherGuard) { Put 'ASSERT' $script:LauncherGuard; continue }
    $sd = Join-Full $ldir "run-$($c.Name)"
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Full $ldir "tree-$($c.Opts)/start_claude_code.ps1")) + @($c.In)
    Invoke-Stubbed $sd @('claude') { param($a) (Invoke-Proc $script:HostExe $a 120000).Rc } $argv
    Put-Args $sd
  }
}

# 呼び出し元に古い $LASTEXITCODE（7）が残っている状態で、$LASTEXITCODE を設定しない claude（.ps1 ラッパー。
# 明示的な exit を持たない）経由で起動しても、ランチャーが 0 を返すこと（PowerShell 系統のみ。bash 版は $? を使うので対象外）
function Probe-LauncherStaleRc {
  Sec 'launcher-stalerc'
  if ($script:LauncherGuard) { Put 'ASSERT' $script:LauncherGuard; return }
  $ldir = Join-Full $script:PT 'launcher'
  $stub = Join-Full $ldir 'stub-noexit'
  New-Item -ItemType Directory -Force -Path $stub | Out-Null
  [System.IO.File]::WriteAllText((Join-Full $stub 'claude.ps1'), "# verify-kit stub: exit を書かない（`$LASTEXITCODE を設定しない）`n", $Utf8NoBom)
  $launcher = (Join-Full $ldir 'tree-none/start_claude_code.ps1').Replace("'", "''")
  $setStale = if ($OnWindows) { 'cmd /c exit 7' } else { "sh -c 'exit 7'" }
  $cmd = "$setStale; `$r = (Get-Command claude -ErrorAction Stop | Select-Object -First 1).Source; " +
         "& '$launcher' --version; `$rc = `$LASTEXITCODE; Write-Output ('RESOLVED=' + `$r); exit `$rc"
  $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
  $savedPath = $env:PATH
  try {
    $env:PATH = if ($OnWindows) { "$stub;$env:SystemRoot\System32;$env:SystemRoot" } else { "${stub}:/usr/bin:/bin" }
    $r = Invoke-Proc $script:HostExe $argv 120000 $script:PT
  } finally { $env:PATH = $savedPath }
  $res = ''
  foreach ($l in ($r.Out -split "`r?`n")) { if ($l.StartsWith('RESOLVED=')) { $res = $l.Substring(9) } }
  if (-not (Same-Path $res (Join-Full $stub 'claude.ps1'))) { Put 'ASSERT' "ng claude の解決先がスタブでない（$res）。実物は起動していない"; return }
  Put 'ASSERT' 'ok'
  Put 'RC' ([string]$r.Rc)
}

function Probe-Version {
  $ldir = Join-Full $script:PT 'launcher'
  $sd = Join-Full $ldir 'run-version'
  $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Full $ldir 'tree-none/start_claude_code.ps1'), '--version')
  Sec 'version-stub'
  if ($script:LauncherGuard) {
    Put 'ASSERT' $script:LauncherGuard
  } else {
    Invoke-Stubbed $sd @('claude') { param($a) (Invoke-Proc $script:HostExe $a 120000).Rc } $argv
    Put-Args $sd
  }
  Sec 'version'
  $af = Join-Full $sd 'claude.args'
  if ($script:LauncherGuard -or -not (Test-Path -LiteralPath $af -PathType Leaf) -or
      (One ([System.IO.File]::ReadAllText($af, $Utf8NoBom)) ("--version`n"))) {
    Put 'PRECHECK' 'ng スタブで確かめた claude への引数が --version 1 個ではない（実物は起動しない）'; return
  }
  Put 'PRECHECK' 'ok'
  $real = Resolve-Cmd 'claude'
  if (-not $real) { Put 'SKIP' 'claude が PATH に無い'; return }
  if ($real.StartsWith($script:Stub, $PathCmp)) { Put 'PRECHECK' 'ng 実物の解決先がスタブになっている'; return }
  $r = Invoke-Proc $script:HostExe $argv 120000 $script:PT
  Put 'RC' ([string]$r.Rc)
  Put 'OUT' ((($r.Out -replace "`r", '') -split "`n")[0])
}

# ---- check-assets（同一プロセスで呼び、Write-Host を情報ストリームで受ける）------------------
function Invoke-CheckAssets([string]$share, [string]$label, [bool]$payload) {
  $ca = Join-Full $VkRoot 'scripts/check-assets.ps1'
  $global:LASTEXITCODE = 0
  if ($payload) { $o = @(& $ca -Share $share -Payload 6>&1 | ForEach-Object { "$_" }) }
  else { $o = @(& $ca -Share $share 6>&1 | ForEach-Object { "$_" }) }
  Put 'RC' ([string]$LASTEXITCODE)
  foreach ($l in $o) { foreach ($x in ($l -split "`r?`n")) { Put 'O' (Norm $x @($share, $label)) } }
}

# fixture のケース（check-assets.expect の 1 列目。probe と比較役が同じ順で使う。verify-kit.sh の CA_CASES と同じ）
$CaCases = @('ume', 'clean', 'broken', 'bom', 'worktree', 'pcase', 'pexact', 'gcase', 'gexact')

function Probe-CheckAssets {
  Sec 'checkassets root'
  if (-not (Resolve-Cmd 'git')) { Put 'SKIP' 'git が無い（リポジトリルートを追跡基準で検査できない）' }
  else { Invoke-CheckAssets $VkRoot '<ROOT>' $false }
  # ケースごとの payload は check-assets.expect の冒頭に記した内容で作る（verify-kit.sh と同じ）。
  # g で始まるケースは一時の git リポジトリ（ルート＝追跡基準）で、それ以外は -Payload（実体基準）で検査する。
  foreach ($c in $CaCases) {
    Sec "checkassets $c"
    $repo = $c.StartsWith('g', [StringComparison]::Ordinal)
    if ($repo) {
      $script:RealGit = Resolve-Cmd 'git'
      if (-not $script:RealGit) { Put 'SKIP' 'git が無い（一時リポジトリを作れない）'; continue }
    }
    $s = Join-Full $script:PT "ca-$c"
    $cd = Join-Full $s '.claude'
    New-Item -ItemType Directory -Force -Path $cd | Out-Null
    Copy-Item -LiteralPath (Join-Full $VkRoot '.claude/.gitignore'), (Join-Full $VkRoot '.claude/.gitattributes') -Destination $cd
    [System.IO.File]::WriteAllText((Join-Full $cd 'CLAUDE.md'), "# verify-kit fixture`n", $Utf8NoBom)
    $dst = Join-Full $cd 'settings.json'
    if (Oeq $c 'bom') {
      [System.IO.File]::WriteAllText($dst, [System.IO.File]::ReadAllText((Join-Path $VkFix 'settings-clean.json'), $Utf8NoBom), $Utf8Bom)
    } elseif (Oeq $c 'worktree') {
      Copy-Item -LiteralPath (Join-Path $VkFix 'settings-clean.json') -Destination $dst
      New-Item -ItemType Directory -Force -Path (Join-Full $cd 'worktrees/wt/.claude/evals/results') | Out-Null
    } elseif (Oeq $c 'pcase') {
      Copy-Item -LiteralPath (Join-Path $VkFix 'settings-envcase.json') -Destination $dst
    } elseif (Oin (@('pexact', 'gcase', 'gexact')) $c) {
      Copy-Item -LiteralPath (Join-Path $VkFix 'settings-clean.json') -Destination $dst
    } else {
      Copy-Item -LiteralPath (Join-Path $VkFix "settings-$c.json") -Destination $dst
    }
    $art = @()
    if (Oeq $c 'ume') {
      Copy-Item -LiteralPath (Join-Path $VkFix 'abspath-mixed.md') -Destination $cd
      [System.IO.File]::WriteAllText((Join-Full $cd 'win-file-encoding-abspath.md'), "C:\Users\verify-kit\work`n", $Utf8NoBom)
      [System.IO.File]::WriteAllText((Join-Full $cd 'big-abspath.md'), ((@('C:\Users\verify-kit\big') * 20000) -join "`n") + "`n", $Utf8NoBom)
    } elseif (Oeq $c 'clean') {
      Copy-Item -LiteralPath (Join-Path $VkFix 'abspath-allowed.md') -Destination $cd
    } elseif (Oin (@('pcase', 'gcase')) $c) {
      $art = @('.claude/Reports/x.md', '.claude/plugin-x/Evals/Results/r.json')
    } elseif (Oin (@('pexact', 'gexact')) $c) {
      $art = @('.claude/reports/x.md', '.claude/plugin-x/evals/results/r.json')
    }
    foreach ($a in $art) {
      $f = Join-Full $s $a
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f) | Out-Null
      [System.IO.File]::WriteAllText($f, $(if ($a.EndsWith('.json')) { "{}`n" } else { "verify-kit`n" }), $Utf8NoBom)
    }
    if (-not $repo) { Invoke-CheckAssets $s '<SHARE>' $true; continue }
    # 利用者の global / system 設定を読まない（一時リポジトリの作成も check-assets の git 呼び出しも）
    $cfg = "$s.gitconfig"
    [System.IO.File]::WriteAllText($cfg, '', $Utf8NoBom)
    if (Oeq $c 'gcase') {
      New-Item -ItemType Directory -Force -Path (Join-Full $cd 'Work') | Out-Null
      [System.IO.File]::WriteAllText((Join-Full $cd 'Work/w.md'), "verify-kit`n", $Utf8NoBom)
    }
    $ok = $true
    foreach ($argv in @(@('init', '-q', $s),
                        @('-C', $s, 'add', '--', '.claude/.gitignore', '.claude/.gitattributes', '.claude/CLAUDE.md', '.claude/settings.json'),
                        (@('-C', $s, 'add', '-f', '--') + $art),
                        @('-C', $s, 'commit', '-q', '-m', 'verify-kit'))) {
      if ((Invoke-TGit $cfg $argv).Rc -ne 0) { $ok = $false; break }
    }
    if (-not $ok) { Put 'RC' 'setup-ng'; continue }
    $saved = @{}
    foreach ($k in @('GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM')) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $cfg)
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1')
    try { Invoke-CheckAssets $s '<SHARE>' $false }
    finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
  }
}

# ---- clean-test-env（スタブ・-Keep。一時ディレクトリは $env:TEMP で自分の一時領域の中へ作らせる）----
function Probe-CleanEnv {
  Sec 'cleanenv'
  $d = Join-Full $script:PT 'cleanenv'
  $sd = Join-Full $d 'stub-out'
  $tmp = Join-Full $d 'tmp'
  New-Item -ItemType Directory -Force -Path $sd, $tmp | Out-Null
  $pre = @()
  foreach ($line in (Read-Lines (Join-Path $VkFix 'clean-test-env.txt'))) {
    if (-not $line.StartsWith("PRE`t")) { continue }
    $kv = $line.Substring(4); $i = $kv.IndexOf('=')
    $pre += , @($kv.Substring(0, $i), $kv.Substring($i + 1))
  }
  $script:CteOut = @(); $script:CteAfter = @()
  # PRE を置いた呼び出し元として clean-test-env.ps1 を呼び、実行後の環境を AFTER に残す（終わったら元に戻す）
  Invoke-Stubbed $sd @('claude') {
    param($a)
    $tmpDir = $a[0]; $preList = $a[1]
    $saved = @{}
    foreach ($p in $preList) { $saved[$p[0]] = [Environment]::GetEnvironmentVariable($p[0]) }
    $savedTemp = $env:TEMP
    try {
      foreach ($p in $preList) {
        if (Oeq ($p[1]) '<unset>') { [Environment]::SetEnvironmentVariable($p[0], $null) }
        else { [Environment]::SetEnvironmentVariable($p[0], $p[1]) }
      }
      $env:TEMP = $tmpDir
      $global:LASTEXITCODE = 0
      $script:CteOut = @(& (Join-Full $VkRoot 'scripts/clean-test-env.ps1') -Share $VkRoot -Keep 6>&1 | ForEach-Object { "$_" })
      $rc = $LASTEXITCODE
      $script:CteAfter = @(foreach ($p in $preList) {
          $x = [Environment]::GetEnvironmentVariable($p[0])
          if ($null -eq $x) { $x = '<unset>' }
          "AFTER`t$($p[0])=$x"
        })
    } finally {
      foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
      $env:TEMP = $savedTemp
    }
    $rc
  } @($tmp, $pre)
  $cfg = ''; $work = ''
  $envf = Join-Full $sd 'claude.env'
  $envLines = @()
  if (Test-Path -LiteralPath $envf -PathType Leaf) {
    $envLines = @(Read-ArgFile $envf)
    foreach ($l in $envLines) {
      if ($l.StartsWith("ENV`tCLAUDE_CONFIG_DIR=")) { $cfg = $l.Substring(("ENV`tCLAUDE_CONFIG_DIR=").Length) }
      elseif ($l.StartsWith("CWD`t")) { $work = $l.Substring(4) }
    }
  }
  # 一時 config dir → <CFG>、作業ディレクトリ → <WORK>、<Share> → <R>
  $nm = @($cfg, '<CFG>', $work, '<WORK>', $VkRoot, '<R>')
  $af = Join-Full $sd 'claude.args'
  if (Test-Path -LiteralPath $af -PathType Leaf) {
    Put 'RAN' 'yes'
    foreach ($a in (Read-ArgFile $af)) { Put 'ARG' (Norm $a $nm) }
  } else {
    Put 'RAN' 'no'
  }
  foreach ($l in $envLines) { $script:ProbeOut.Add((Norm $l $nm)) }
  $sf = if ($cfg) { Join-Full $cfg 'settings.json' } else { '' }
  if ($sf -and (Test-Path -LiteralPath $sf -PathType Leaf)) {
    Put 'SETTINGS' (([System.IO.File]::ReadAllText($sf, $Utf8NoBom)) -replace "[`r`n]", '')
  } else {
    Put 'SETTINGS' '<なし>'
  }
  foreach ($l in $script:CteAfter) { $script:ProbeOut.Add($l) }
  foreach ($l in $script:CteOut) { foreach ($x in ($l -split "`r?`n")) { Put 'O' (Norm $x $nm) } }
}

# ---- clean-test-env の不正な権限モード（スタブ。起動前に止まり claude が呼ばれないこと）-------------
function Probe-CleanEnvBadMode {
  $d = Join-Full $script:PT 'cleanenv-bad'
  $i = 0
  foreach ($line in (Read-Lines (Join-Path $VkFix 'clean-test-env.txt'))) {
    if (-not $line.StartsWith("BADMODE`t")) { continue }
    $m = $line.Substring(8); $i++
    Sec "cleanenv-badmode $i"
    Put 'MODE' $m
    $sd = Join-Full $d "case$i"
    $tmp = Join-Full $sd 'tmp'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $script:CteBadOut = @()
    $script:CteBadErr = ''
    Invoke-Stubbed $sd @('claude') {
      param($a)
      $savedTemp = $env:TEMP
      # エラー文は [Console]::Error に書かれ PowerShell のストリームには乗らないので、Console.Error を差し替えて stderr を別に受ける
      $savedErr = [Console]::Error
      $errSw = New-Object System.IO.StringWriter
      try {
        $env:TEMP = $a[0]
        $global:LASTEXITCODE = 0
        [Console]::SetError($errSw)
        try {
          $script:CteBadOut = @(& (Join-Full $VkRoot 'scripts/clean-test-env.ps1') -Share $VkRoot -Keep -PermissionMode $a[1] 6>&1 2>&1 | ForEach-Object { "$_" })
          $rc = $LASTEXITCODE
        } catch {
          # パラメータの検証（ValidateSet 等）で落ちた場合。終了コードの代わりに -1、出力の代わりに例外の文言を残す
          $script:CteBadOut = @("$_"); $rc = -1
        }
      } finally {
        [Console]::SetError($savedErr)
        $script:CteBadErr = $errSw.ToString()
        $env:TEMP = $savedTemp
      }
      $rc
    } @($tmp, $m)
    Put-Args $sd
    foreach ($l in $script:CteBadOut) { foreach ($x in ($l -split "`r?`n")) { Put 'O' (Norm $x @($VkRoot, '<R>')) } }
    foreach ($x in ($script:CteBadErr -split "`r?`n")) { if (One $x '') { Put 'E' (Norm $x @($VkRoot, '<R>')) } }
  }
}

# ---- publish-plugin の -Name 検証 -----------------------------------------------
function Probe-PubName {
  Sec 'pubname'
  if ($PSVersionTable.PSVersion.Major -lt 7) { Put 'MODE' 'na'; return }   # 本体が #requires -Version 7
  $pp = Join-Full $VkRoot 'scripts/publish-plugin.ps1'
  $d = Join-Full $script:PT 'pubname'
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  # -Name 検証（{0,127} を含む行）が、最初の副作用コマンド（git / ファイル操作 / claude 等）より前にあること
  $lines = Read-Lines $pp
  $nl = 0; $sl = 0; $inBlock = $false
  $sideRe = '(^|[^A-Za-z0-9_.-])(git|claude|New-Item|Remove-Item|Copy-Item|Move-Item|Expand-Archive|Compress-Archive|Set-Content|Add-Content|Out-File|Invoke-WebRequest|Invoke-RestMethod|Start-Process|mkdir|ni|rm|del|cp|copy|mv|move)([^A-Za-z0-9_.-]|$)'
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $t = $lines[$i].Trim()
    if ($inBlock) { if ($t.Contains('#>')) { $inBlock = $false }; continue }
    if ($t.StartsWith('<#')) { if (-not $t.Contains('#>')) { $inBlock = $true }; continue }
    if ($t.StartsWith('#')) { continue }
    if ($nl -eq 0 -and $lines[$i].Contains('{0,127}')) { $nl = $i + 1 }
    if ($sl -eq 0 -and $lines[$i] -match $sideRe) { $sl = $i + 1 }
  }
  $cases = @()
  foreach ($line in (Read-Lines (Join-Path $VkFix 'plugin-names.tsv'))) {
    if ((Oeq $line '') -or $line.StartsWith('#')) { continue }
    $cols = $line.Split("`t")
    $cases += , $(if ($cols.Count -ge 3) { $cols[2] } else { '' })
  }
  if ($nl -gt 0 -and $sl -gt 0 -and $nl -lt $sl) {
    Put 'ORDER' "ok 名前検証 $nl 行目 < 最初の副作用 $sl 行目"
    Put 'MODE' 'real'
    $nomkt = Join-Full $d 'no-such-marketplace'
    $ang = ''
    for ($i = 1; $i -le $cases.Count; $i++) {
      $name = [string]$cases[$i - 1]
      $sd = Join-Full $d "case$i"
      New-Item -ItemType Directory -Force -Path $sd | Out-Null
      $savedPath = $env:PATH; $savedSd = $env:VERIFY_KIT_STUB_DIR
      $cls = 'other'; $rc = '-'
      try {
        $env:PATH = $script:StubPath
        $env:VERIFY_KIT_STUB_DIR = $sd
        $ng = Test-Stubs @('git', 'claude')
        if ($ng) {
          $cls = 'assert-ng'
          if (-not $ang) { $ang = $ng }
        } else {
          $global:LASTEXITCODE = 0
          try {
            $o = (@(& $pp -Marketplace $nomkt -Ref 'verify-kit-dummy-ref' -Name $name 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n")
            $rc = [string]$LASTEXITCODE
          } catch {
            $o = "$_"; $rc = '-1'
          }
          if ($o.Contains('plugin 名として不正')) { if (Oeq $rc '2') { $cls = 'reject' } }
          elseif ($o.Contains('marketplace リポジトリが見つからない')) { if (Oeq $rc '2') { $cls = 'accept' } }
          elseif ($o.Contains('--name に値が必要') -or $o.Contains('-Name に値が必要')) { if (Oeq $rc '1') { $cls = 'argerr' } }
        }
      } finally {
        $env:PATH = $savedPath
        [Environment]::SetEnvironmentVariable('VERIFY_KIT_STUB_DIR', $savedSd)
      }
      $calls = 0
      $cf = Join-Full $sd 'calls'
      if (Test-Path -LiteralPath $cf -PathType Leaf) { $calls = @(Read-ArgFile $cf).Count }
      Put 'CASE' "$i $cls rc=$rc stubcalls=$calls"
    }
    Put 'ASSERT' $(if ($ang) { $ang } else { 'ok' })
  } else {
    # 順序を確かめられないときは実スクリプトを実行しない。検証の正規表現を抽出して各ケースを当てる（フォールバック）
    Put 'ORDER' "ng 名前検証=$(if ($nl) { $nl } else { '?' }) 行目 / 最初の副作用=$(if ($sl) { $sl } else { '?' }) 行目"
    Put 'MODE' 'fallback'
    $m = [regex]::Match(($lines -join "`n"), "-cnotmatch '([^']+)'")
    $re = if ($m.Success) { $m.Groups[1].Value } else { '' }
    Put 'REGEX' $re
    for ($i = 1; $i -le $cases.Count; $i++) {
      $cls = if ($re -and ([string]$cases[$i - 1] -cmatch $re)) { 'accept' } else { 'reject' }
      Put 'CASE' "$i $cls rc=- stubcalls=0"
    }
  }
}

# ---- publish-plugin の大文字小文字違い（一時ディレクトリの偽 marketplace）------------------
# 偽 marketplace は .git を空のディレクトリ、plugins\<既存>\ に目印のファイルを置いて作る（verify-kit.sh と同じ）。
function Probe-PubCase {
  Sec 'pubcase'
  if ($PSVersionTable.PSVersion.Major -lt 7) { Put 'MODE' 'na'; return }   # 本体が #requires -Version 7
  $pp = Join-Full $VkRoot 'scripts/publish-plugin.ps1'
  $d = Join-Full $script:PT 'pubcase'
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $ang = ''; $i = 0
  foreach ($line in (Read-Lines (Join-Path $VkFix 'plugin-case.tsv'))) {
    if ((Oeq $line '') -or $line.StartsWith('#')) { continue }
    $f = $line.Split("`t")
    $ent = $f[1]; $name = $f[2]
    $i++
    $mkt = Join-Full $d "mkt$i"
    $sd = Join-Full $d "case$i"
    $tmp = Join-Full $sd 'tmp'
    foreach ($p in @((Join-Full $mkt '.git'), (Join-Full $mkt "plugins/$ent"), $tmp)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
    [System.IO.File]::WriteAllText((Join-Full $mkt "plugins/$ent/sentinel.txt"), "verify-kit`n", $Utf8NoBom)
    $savedPath = $env:PATH; $savedSd = $env:VERIFY_KIT_STUB_DIR; $savedTemp = $env:TEMP
    $cls = 'other'; $rc = '-'; $o = ''
    try {
      $env:PATH = $script:StubPath
      $env:VERIFY_KIT_STUB_DIR = $sd
      $env:TEMP = $tmp
      $ng = Test-Stubs @('git', 'claude')
      if ($ng) {
        $cls = 'assert-ng'
        if (-not $ang) { $ang = $ng }
      } else {
        $global:LASTEXITCODE = 0
        try {
          $o = (@(& $pp -Marketplace $mkt -Ref 'verify-kit-dummy-ref' -Name $name 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n")
          $rc = [string]$LASTEXITCODE
        } catch {
          $o = "$_"; $rc = '-1'
        }
      }
    } finally {
      $env:PATH = $savedPath
      [Environment]::SetEnvironmentVariable('VERIFY_KIT_STUB_DIR', $savedSd)
      $env:TEMP = $savedTemp
    }
    # スタブの git.args は最後の呼び出しの引数。取り出しまで進んだら最後は archive になる
    $ga = Join-Full $sd 'git.args'
    $arch = if ((Test-Path -LiteralPath $ga -PathType Leaf) -and ((Oin (@(Read-ArgFile $ga)) 'archive'))) { 'yes' } else { 'no' }
    $entries = @(Get-ChildItem -Force -LiteralPath (Join-Full $mkt 'plugins') | ForEach-Object { $_.Name })
    $intact = if ((Test-Path -LiteralPath (Join-Full $mkt "plugins/$ent/sentinel.txt") -PathType Leaf) -and
                  $entries.Count -eq 1 -and (Oeq ($entries[0]) $ent)) { 'yes' } else { 'no' }
    if (One $cls 'assert-ng') {
      if ($o.Contains('大文字小文字だけが違う既存エントリ')) { if ((Oeq $rc '2') -and (Oeq $arch 'no')) { $cls = 'clash' } }
      elseif (Oeq $arch 'yes') { $cls = 'pass' }
    }
    Put 'CASE' "$i $cls rc=$rc archive=$arch intact=$intact"
  }
  Put 'ASSERT' $(if ($ang) { $ang } else { 'ok' })
}

# ---- publish-plugin の plugin.json の name 照合（一時の開発リポと marketplace・実物の git・claude はスタブ）-------
# 一時リポジトリ用の git（利用者の global / system 設定を読まない。作者は固定。verify-kit.sh の vk_tgit と同じ）
function Invoke-TGit([string]$cfg, [string[]]$argv) {
  $vars = [ordered]@{ GIT_CONFIG_GLOBAL = $cfg; GIT_CONFIG_NOSYSTEM = '1'; GIT_AUTHOR_NAME = 'verify-kit'; GIT_AUTHOR_EMAIL = 'verify-kit@invalid';
                      GIT_COMMITTER_NAME = 'verify-kit'; GIT_COMMITTER_EMAIL = 'verify-kit@invalid' }
  $saved = @{}
  foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
  try { return (Invoke-Proc $script:RealGit $argv 120000) }
  finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}

# 結果は verify-kit.sh の probe_pubmanifest と同じ（pass / mismatch / unreadable / skip / other と、一時 marketplace が
# 無傷か。中止のときは文言を MSG に書く）。publish-plugin.ps1 は標準入力を閉じた子プロセスで実行し、出力は UTF-8 に固定する。
function Probe-PubManifest {
  Sec 'pubmanifest'
  if ($PSVersionTable.PSVersion.Major -lt 7) { Put 'MODE' 'na'; return }   # 本体が #requires -Version 7
  $pp = Join-Full $VkRoot 'scripts/publish-plugin.ps1'
  $d = Join-Full $script:PT 'pubman'
  $cst = Join-Full $script:PT 'stub-claude'
  New-Item -ItemType Directory -Force -Path $d, $cst | Out-Null
  $script:RealGit = Resolve-Cmd 'git'
  if (-not $script:RealGit) { Put 'SKIP' 'git が無い（一時リポジトリを作れない）'; return }
  $gitDir = Split-Path -Parent $script:RealGit
  $savedStub = $script:Stub
  try { $script:Stub = $cst; New-Stub 'claude' } finally { $script:Stub = $savedStub }
  $cfg = Join-Full $d 'gitconfig'
  [System.IO.File]::WriteAllText($cfg, '', $Utf8NoBom)
  $path = if ($OnWindows) { "$cst;$gitDir;$env:SystemRoot\System32;$env:SystemRoot" } else { "${cst}:${gitDir}:/usr/bin:/bin" }
  $ang = ''; $i = 0
  foreach ($line in (Read-Lines (Join-Path $VkFix 'plugin-manifest.tsv'))) {
    if ((Oeq $line '') -or $line.StartsWith('#')) { continue }
    $f = $line.Split("`t", 6)
    $ep = $f[1]; $bom = $f[3]; $name = $f[4]; $json = if ($f.Count -ge 6) { $f[5] } else { '' }
    $i++
    if (Oeq $ep '-') { Put 'CASE' "$i -"; continue }
    $dev = Join-Full $d "dev$i"; $mkt = Join-Full $d "mkt$i"; $cs = Join-Full $d "case$i"; $tmp = Join-Full $cs 'tmp'
    foreach ($p in @((Join-Full $dev 'scripts'), (Join-Full $dev 'plugin/.claude-plugin'), (Join-Full $mkt "plugins/$name"), $tmp)) {
      New-Item -ItemType Directory -Force -Path $p | Out-Null
    }
    $ppCopy = Join-Full $dev 'scripts/publish-plugin.ps1'
    Copy-Item -LiteralPath $pp -Destination $ppCopy
    $body = [byte[]]$Utf8NoBom.GetBytes("$json`n")
    if (Oeq $bom 'yes') { $body = [byte[]](@([byte]0xEF, [byte]0xBB, [byte]0xBF) + $body) }
    [System.IO.File]::WriteAllBytes((Join-Full $dev 'plugin/.claude-plugin/plugin.json'), $body)
    [System.IO.File]::WriteAllText((Join-Full $mkt "plugins/$name/sentinel.txt"), "verify-kit`n", $Utf8NoBom)
    $setupOk = ((Invoke-TGit $cfg @('init', '-q', $dev)).Rc -eq 0) -and
               ((Invoke-TGit $cfg @('-C', $dev, 'add', 'plugin')).Rc -eq 0) -and
               ((Invoke-TGit $cfg @('-C', $dev, 'commit', '-q', '-m', 'verify-kit')).Rc -eq 0) -and
               ((Invoke-TGit $cfg @('init', '-q', $mkt)).Rc -eq 0)
    if (-not $setupOk) { Put 'CASE' "$i setup-ng"; continue }
    # PATH はスタブの claude・実物の git・OS の標準ディレクトリだけ。TEMP はケースの中
    $envs = [ordered]@{ PATH = $path; VERIFY_KIT_STUB_DIR = $cs; TEMP = $tmp; TMP = $tmp; GIT_CONFIG_GLOBAL = $cfg; GIT_CONFIG_NOSYSTEM = '1' }
    $saved = @{}
    $a = ''; $r = $null
    try {
      foreach ($k in $envs.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $envs[$k]) }
      $rcl = Resolve-Cmd 'claude'
      $rgit = Resolve-Cmd 'git'
      if (-not (Same-Path $rcl (Join-Full $cst 'claude.ps1'))) {
        $a = "ng claude の解決先がスタブでない（$(if ($rcl) { $rcl } else { '見つからない' })）。実行しない"
      } elseif (-not (Same-Path $rgit $script:RealGit)) {
        $a = "ng git の解決先が実物でない（$(if ($rgit) { $rgit } else { '見つからない' })）。実行しない"
      } else {
        $rem = Invoke-Proc $rgit @('-C', $mkt, 'remote') 60000
        if ($rem.Rc -ne 0 -or (One ($rem.Out.Trim()) '')) {
          $a = "ng 一時 marketplace に remote がある（$(if ($rem.Rc -ne 0) { "git remote が失敗した: $($rem.Err.Trim())" } else { $rem.Out.Trim() })）。実行しない"
        } else {
          $a = 'ok'
          $q = { param($s) "'" + $s.Replace("'", "''") + "'" }
          $cmd = "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(`$false); " +
                 "& $(& $q $ppCopy) -Marketplace $(& $q $mkt) -Ref HEAD -Name $(& $q $name); exit `$LASTEXITCODE"
          $r = Invoke-Proc $script:HostExe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) 120000 $cs
        }
      }
    } finally {
      foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
    if (One $a 'ok') {
      if (-not $ang) { $ang = $a }
      Put 'CASE' "$i assert-ng"; continue
    }
    $rc = [string]$r.Rc
    $out = $r.Out + "`n" + $r.Err
    $ca = Join-Full $cs 'claude.args'
    $val = if ((Test-Path -LiteralPath $ca -PathType Leaf) -and ((Oin (@(Read-ArgFile $ca)) 'validate'))) { 'yes' } else { 'no' }
    $entries = @(Get-ChildItem -Force -LiteralPath (Join-Full $mkt 'plugins') | ForEach-Object { $_.Name })
    $top = @(Get-ChildItem -Force -LiteralPath $mkt | ForEach-Object { $_.Name })
    $head = Invoke-TGit $cfg @('-C', $mkt, 'rev-parse', '-q', '--verify', 'HEAD')
    $index = Invoke-TGit $cfg @('-C', $mkt, 'ls-files')
    $intact = if ((Test-Path -LiteralPath (Join-Full $mkt "plugins/$name/sentinel.txt") -PathType Leaf) -and
                  $entries.Count -eq 1 -and (Oeq ($entries[0]) $name) -and
                  $top.Count -eq 2 -and (Oin $top '.git') -and (Oin $top 'plugins') -and
                  $head.Rc -ne 0 -and $index.Rc -eq 0 -and (Oeq ($index.Out.Trim()) '')) { 'yes' } else { 'no' }
    $cls = 'other'
    if ($out.Contains('の name（') -and $out.Contains('が違う。中止')) { if ((Oeq $rc '1') -and (Oeq $val 'no')) { $cls = 'mismatch' } }
    elseif ($out.Contains('の name を読めない')) { if ((Oeq $rc '1') -and (Oeq $val 'no')) { $cls = 'unreadable' } }
    elseif ($out.Contains('python が無いため')) { if ((Oeq $rc '1') -and (Oeq $val 'no')) { $cls = 'nopython' } }
    elseif (Oeq $val 'yes') { $cls = 'pass' }
    Put 'CASE' "$i $cls rc=$rc validate=$val intact=$intact"
    if (One $cls 'pass') {
      foreach ($l in ($out -split "`r?`n")) { if ($l.StartsWith('‼') -or $l.StartsWith('   ')) { Put 'MSG' "$i $l" } }
    }
  }
  Put 'ASSERT' $(if ($ang) { $ang } else { 'ok' })
}

function Invoke-ProbeMain {
  if (-not $Out) { Write-Host '‼ -Probe には -Out <出力先> が必要'; exit 2 }
  $script:PT = Join-Path ([System.IO.Path]::GetTempPath()) ('verify-kit-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $script:PT | Out-Null
  try {
    $script:Stub = Join-Full $script:PT 'stub'
    New-Item -ItemType Directory -Force -Path $script:Stub | Out-Null
    New-Stub 'claude'
    New-Stub 'git'
    # 実物が見つからない PATH（スタブと OS の標準ディレクトリだけ）
    $script:StubPath = if ($OnWindows) { "$($script:Stub);$env:SystemRoot\System32;$env:SystemRoot" } else { "$($script:Stub):/usr/bin:/bin" }
    $script:Files = @(Get-RepoFiles)
    Sec 'meta'
    Put 'SYSTEM' $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'ps51' })
    Put 'VERSION' $PSVersionTable.PSVersion.ToString()
    Put 'EDITION' $(if ($PSVersionTable.PSEdition) { [string]$PSVersionTable.PSEdition } else { 'Desktop' })
    Probe-Syntax
    Probe-Format
    Probe-Optset
    Probe-SetupEnv
    Probe-Launcher
    Probe-LauncherStaleRc
    Probe-Version
    Probe-CheckAssets
    Probe-CleanEnv
    Probe-CleanEnvBadMode
    Probe-PubName
    Probe-PubCase
    Probe-PubManifest
    Sec 'end'
  } finally {
    try { [System.IO.File]::WriteAllText($Out, (($script:ProbeOut -join "`n") + "`n"), $Utf8NoBom) } catch { Write-Host "‼ 結果を書けない: $Out" }
    Remove-Item -LiteralPath $script:PT -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if ($Probe) {
  Invoke-ProbeMain
  exit 0
}

# =============================================================================
# 比較役（全系統の probe を呼んで突き合わせる）。判定の内容・文言は verify-kit.sh と揃えること。
# =============================================================================
$VkVerbose = $PSBoundParameters.ContainsKey('Verbose')
$script:NPass = 0; $script:NFail = 0; $script:NSkip = 0
$SysAll = @('bash', 'pwsh', 'ps51')
$SysLabel = @{ bash = 'bash'; pwsh = 'pwsh 7'; ps51 = '5.1' }
$SysName = @{ bash = 'bash'; pwsh = 'pwsh'; ps51 = 'Windows PowerShell' }
$SysState = @{}; $SysWhy = @{}; $SysVer = @{}; $Results = @{}

function Verdict([string]$v, [string]$t, [string]$why) {
  switch ($v) { 'PASS' { $script:NPass++ } 'FAIL' { $script:NFail++ } 'SKIP' { $script:NSkip++ } }
  Write-Host ("  [{0}] {1}: {2}" -f $v, $t, $why)
}
# FAIL の詳細（-Verbose のときだけ差分を出す）。差分の対象は Set-Diff で先に登録しておく
$script:DiffA = $null; $script:DiffB = $null; $script:DiffLabel = ''
function Set-Diff($a, $b, [string]$label) { $script:DiffA = @($a); $script:DiffB = @($b); $script:DiffLabel = $label }
function Fail-Diff([string]$t, [string]$why) {
  Verdict 'FAIL' $t $why
  if ($VkVerbose -and $null -ne $script:DiffA) {
    Write-Host "         | $($script:DiffLabel)"
    $n = 0
    foreach ($x in (Compare-Object -CaseSensitive -SyncWindow 1000 $script:DiffA $script:DiffB)) {
      $mark = if ($x.SideIndicator -eq '<=') { '<' } else { '>' }
      Write-Host "         | $mark $($x.InputObject)"
      if (++$n -ge 20) { break }
    }
  }
  $script:DiffA = $null; $script:DiffB = $null
}

function Get-Sec([string]$s, [string]$name) {
  $acc = New-Object 'System.Collections.Generic.List[string]'
  $h = "@@ $name"; $on = $false
  foreach ($l in $Results[$s]) {
    if (Oeq $l $h) { $on = $true; continue }
    if ($l.StartsWith('@@ ')) { $on = $false; continue }
    if ($on) { $acc.Add($l) }
  }
  return , $acc.ToArray()
}
function Val([string]$l) { $i = $l.IndexOf("`t"); if ($i -ge 0) { return $l.Substring($i + 1) } else { return $l } }
function Tag-Vals([string[]]$lines, [string]$tag) { @($lines | Where-Object { $_.StartsWith("$tag`t") } | ForEach-Object { Val $_ }) }
function Lines-Equal($a, $b) {
  $a = @($a); $b = @($b)
  if ($a.Count -ne $b.Count) { return $false }
  for ($i = 0; $i -lt $a.Count; $i++) { if (-not [string]::Equals([string]$a[$i], [string]$b[$i], [StringComparison]::Ordinal)) { return $false } }
  return $true
}

function Usable([string[]]$systems) { @($systems | Where-Object { $SysState[$_] -ne 'missing' }) }
function Labels([string[]]$systems) { (@($systems | ForEach-Object { $SysLabel[$_] })) -join ' / ' }
function Missing-Note([string[]]$systems) {
  $m = @($systems | Where-Object { $SysState[$_] -eq 'missing' } | ForEach-Object { "$($SysLabel[$_]): $($SysWhy[$_])" })
  if ($m.Count -gt 0) { return '（' + ($m -join '、') + '）' } else { return '' }
}
function Crashed-In([string[]]$systems) { foreach ($s in $systems) { if ($SysState[$s] -eq 'crashed') { return $s } }; return '' }

# 期待値ファイルの鍵（行頭の列）が列挙に存在するかを逆方向にも照合する。鍵を書き間違えた行は、列挙側の照合（ケースごとに
# 期待値の行があるか）では見えず、黙って無視されたまま PASS になりうる。不正があれば理由を返し、無ければ空文字列を返す
# （verify-kit.sh の vk_check_keys と同じ文言）。# 始まりと空行は対象外。
function Test-FixKeys([string]$file, [string[]]$allow, [string]$what, [int]$min = 0) {
  foreach ($line in (Read-Lines (Join-Path $VkFix $file))) {
    if ((Oeq $line '') -or $line.StartsWith('#')) { continue }
    $cols = $line.Split("`t")
    if (Onin $allow $cols[0]) { return "${file}: 行頭の鍵「$($cols[0])」が${what}に無い（行: $line）" }
    if ($min -gt 0 -and $cols.Count -lt $min) { return "${file}: 列が足りない（$min 列必要）（行: $line）" }
  }
  return ''
}
# launcher-cases.txt: 行頭タグ（case / in / out）・case 行の名前と opts|none・case より前の in / out を検査する
function Test-LauncherCases {
  $f = 'launcher-cases.txt'
  $bad = Test-FixKeys $f @('case', 'in', 'out') '定義済みの行頭タグ（case / in / out）'
  if ($bad) { return $bad }
  $seen = $false
  foreach ($line in (Read-Lines (Join-Path $VkFix $f))) {
    if ((Oeq $line '') -or $line.StartsWith('#')) { continue }
    $cols = $line.Split("`t")
    if (Oeq $cols[0] 'case') {
      $seen = $true
      if ($cols.Count -lt 2 -or (Oeq $cols[1] '')) { return "${f}: case 行の名前が空（行: $line）" }
      if ($cols.Count -lt 3 -or -not ((Oeq $cols[2] 'opts') -or (Oeq $cols[2] 'none'))) { return "${f}: case 行の第 3 列は opts か none（行: $line）" }
    } elseif (-not $seen) { return "${f}: case 行より前に $($cols[0]) 行がある（行: $line）" }
  }
  return ''
}

# 系統ごとの節を比べて全系統一致かを調べる。食い違えば SameA / SameB に系統を入れて $false を返す
function Same-All([string]$secName, [string[]]$systems) {
  $first = ''; $firstLines = $null
  foreach ($s in $systems) {
    $lines = Get-Sec $s $secName
    if (-not $first) { $first = $s; $firstLines = $lines; continue }
    if (-not (Lines-Equal $firstLines $lines)) {
      $script:SameA = $first; $script:SameB = $s
      Set-Diff $firstLines $lines "$($SysLabel[$first]) と $($SysLabel[$s]) の差分（$secName）:"
      return $false
    }
  }
  return $true
}

function Find-Bash {
  if (-not $OnWindows) { return (Resolve-Cmd 'bash') }
  # Git for Windows の bash を使う（System32\bash.exe は WSL の起動口で、別の環境になる）
  $cands = @()
  $git = Resolve-Cmd 'git'
  if ($git) {
    $g1 = Split-Path -Parent (Split-Path -Parent $git)
    $cands += (Join-Path $g1 'bin\bash.exe')
    $cands += (Join-Path (Split-Path -Parent $g1) 'bin\bash.exe')
  }
  if ($env:ProgramFiles) { $cands += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
  foreach ($c in $cands) { if (Test-Path -LiteralPath $c -PathType Leaf) { return $c } }
  $b = Resolve-Cmd 'bash'
  if ($b -and $b -notmatch '\\System32\\') { return $b }
  return ''
}

function Invoke-Probes([string]$tmp) {
  foreach ($s in $SysAll) { $SysState[$s] = 'missing' }
  $exe = @{}
  $exe.bash = Find-Bash
  if ($PSVersionTable.PSEdition -eq 'Core') { $exe.pwsh = $HostExe } else { $exe.pwsh = Resolve-Cmd 'pwsh' }
  if ($PSVersionTable.PSEdition -ne 'Core') { $exe.ps51 = $HostExe }
  elseif ($OnWindows -and $env:SystemRoot -and (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))) {
    $exe.ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  } else { $exe.ps51 = Resolve-Cmd 'powershell.exe' }
  $why = @{ bash = 'Git for Windows の bash が見つからない'; pwsh = 'pwsh が見つからない'; ps51 = 'powershell.exe が見つからない' }
  foreach ($s in $SysAll) { if ($exe[$s]) { $SysState[$s] = 'ok' } else { $SysWhy[$s] = $why[$s] } }
  if (-not (Test-Path -LiteralPath $VkSh -PathType Leaf)) { $SysState.bash = 'missing'; $SysWhy.bash = 'verify-kit.sh が無い' }
  foreach ($s in $SysAll) {
    if ($SysState[$s] -ne 'ok') { continue }
    $rf = Join-Path $tmp "r-$s.txt"
    if ($s -eq 'bash') {
      $argv = @('--noprofile', '--norc', $VkSh.Replace('\', '/'), '--probe', $rf.Replace('\', '/'))
    } else {
      $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $VkSelf, '-Probe', '-Out', $rf)
    }
    $r = Invoke-Proc $exe[$s] $argv 900000
    [System.IO.File]::WriteAllText((Join-Path $tmp "log-$s.txt"), ($r.Out + $r.Err), $Utf8NoBom)
    $lines = @()
    if (Test-Path -LiteralPath $rf -PathType Leaf) { $lines = @(Read-Lines $rf) }
    $Results[$s] = $lines
    if ($lines.Count -eq 0 -or (One ($lines[$lines.Count - 1]) '@@ end')) { $SysState[$s] = 'crashed'; $SysWhy[$s] = 'probe が異常終了した' }
    $meta = Get-Sec $s 'meta'
    $ed = @(Tag-Vals $meta 'EDITION') | Select-Object -First 1
    $SysVer[$s] = @(Tag-Vals $meta 'VERSION') | Select-Object -First 1
    # powershell.exe が Desktop 版（5.1）でない、pwsh が Core 版でない、のいずれかなら系統として扱わない
    if ($SysState[$s] -eq 'ok' -and -not (($s -eq 'pwsh' -and $ed -eq 'Core') -or ($s -eq 'ps51' -and $ed -eq 'Desktop') -or ($s -eq 'bash' -and $ed -eq '-'))) {
      $SysState[$s] = 'missing'; $SysWhy[$s] = "想定と違うエディション（$(if ($ed) { $ed } else { '不明' })）"
    }
  }
}

# ---- 各検査 -------------------------------------------------------------------
function Item-Syntax([string]$s, [string]$t) {
  if ($SysState[$s] -eq 'missing') { Verdict 'SKIP' $t $SysWhy[$s]; return }
  if ($SysState[$s] -eq 'crashed') { Verdict 'FAIL' $t 'probe が異常終了した（-Verbose でログ）'; return }
  $lines = Get-Sec $s 'syntax'
  $skip = @(Tag-Vals $lines 'SKIP')
  if ($skip.Count -gt 0) { Verdict 'SKIP' $t $skip[0]; return }
  $ok = @(Tag-Vals $lines 'OK'); $ng = @(Tag-Vals $lines 'NG')
  $n = $ok.Count + $ng.Count
  if ($n -eq 0) { Verdict 'FAIL' $t '対象ファイルが無い'; return }
  if ($ng.Count -gt 0) { Verdict 'FAIL' $t "$($ng.Count)/$n ファイルでエラー: $($ng[0])"; return }
  Verdict 'PASS' $t "$n ファイル エラー 0"
}

function Fmt-Class([string]$rel) { # 保存形式の区分（bash 版の fmt_class と同じ）
  if ($rel.StartsWith('scripts/verify-kit.d/', 'Ordinal')) { return 'lfnobom' }
  $n = $rel.Substring($rel.LastIndexOf('/') + 1)
  foreach ($e in @('.ps1', '.psm1', '.psd1', '.ps1.template')) { if ($n.EndsWith($e, 'Ordinal')) { return 'ps' } }
  foreach ($e in @('.sh', '.sh.template')) { if ($n.EndsWith($e, 'Ordinal')) { return 'lfnobom' } }
  foreach ($e in @('.md', '.json', '.template')) { if ($n.EndsWith($e, 'Ordinal')) { return 'lf' } }
  if (Oeq $n '.gitignore') { return 'lf' }
  return 'none'
}

function Item-Format {
  $t = '保存形式（BOM / CR / LF）'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $lines = Get-Sec $avail[0] 'format'
  $skip = @(Tag-Vals $lines 'SKIP')
  if ($skip.Count -gt 0) { Verdict 'SKIP' $t $skip[0]; return }
  if (-not (Same-All 'format' $avail)) { Fail-Diff $t "計測が $($SysLabel[$script:SameA]) と $($SysLabel[$script:SameB]) で食い違う（計測方法の不備を疑う）"; return }
  $n = 0; $nps = 0; $nlf = 0; $nnone = 0; $bad = 0; $first = ''
  foreach ($l in $lines) {
    $f = $l.Split("`t")
    if (One ($f[0]) 'F') { continue }
    $rel = $f[1]; $bom = $f[2]; $cr = [int]$f[3]; $lf = [int]$f[4]
    $n++
    $cls = Fmt-Class $rel
    if (Oeq $cls 'ps') {
      $nps++
      if ((One $bom 'efbbbf') -or $cr -ne $lf -or $lf -eq 0) {
        $bad++; if (-not $first) { $first = "$rel（BOM=$bom CR=$cr LF=$lf。期待: BOM efbbbf・CR 数 = LF 数）" }
      }
    } elseif ((Oeq $cls 'lf') -or (Oeq $cls 'lfnobom')) {
      $nlf++
      if ($cr -ne 0 -or ((Oeq $cls 'lfnobom') -and (Oeq $bom 'efbbbf'))) {
        $bad++; if (-not $first) { $first = "$rel（BOM=$bom CR=$cr。期待: CR 0$(if (Oeq $cls 'lfnobom') { '・BOM なし' })）" }
      }
    } else { $nnone++ }
  }
  if ($bad -gt 0) { Verdict 'FAIL' $t "$bad ファイル不適合: $first"; return }
  Verdict 'PASS' $t "$n ファイル（BOM+CRLF $nps・LF $nlf・対象外 $nnone）適合。計測は $(Labels $avail) で一致$(Missing-Note $SysAll)"
}

function Item-Version {
  $t = 'ランチャー 実物 claude --version'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $ver = ''; $nskip = 0; $why = ''
  foreach ($s in $avail) {
    $lines = Get-Sec $s 'version'
    $pre = @(Tag-Vals $lines 'PRECHECK') | Select-Object -First 1
    if (One $pre 'ok') { Verdict 'FAIL' $t "$($SysLabel[$s]): $(if ($pre) { $pre } else { '事前確認の結果が無い' })"; return }
    $skip = @(Tag-Vals $lines 'SKIP')
    if ($skip.Count -gt 0) { $nskip++; $why = $skip[0]; continue }
    $rc = @(Tag-Vals $lines 'RC') | Select-Object -First 1
    $o = @(Tag-Vals $lines 'OUT') | Select-Object -First 1
    if (One $rc '0') { Verdict 'FAIL' $t "$($SysLabel[$s]): exit $(if ($rc) { $rc } else { '?' })（出力: $o）"; return }
    if ($o -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+ \(Claude Code\)$') { Verdict 'FAIL' $t "$($SysLabel[$s]): 版表示の形式が違う（$o）"; return }
    if (-not $ver) { $ver = $o } elseif (One $ver $o) { Verdict 'FAIL' $t "系統間で版が違う（$ver / $o）"; return }
  }
  if ($nskip -eq $avail.Count) { Verdict 'SKIP' $t $why; return }
  Verdict 'PASS' $t "$(Labels $avail) とも $ver・exit 0（事前にスタブで引数が --version 1 個と確認）$(Missing-Note $SysAll)"
}

function Item-Launcher {
  $t = 'ランチャー 引数列（スタブ）'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $bad = Test-LauncherCases
  if ($bad) { Verdict 'FAIL' $t $bad; return }
  $cases = @(Get-Cases)
  foreach ($cs in $cases) {
    $exp = $cs.Out.ToArray()
    foreach ($s in $avail) {
      $lines = Get-Sec $s "launcher $($cs.Name)"
      $a = @(Tag-Vals $lines 'ASSERT') | Select-Object -First 1
      if (One $a 'ok') { Verdict 'FAIL' $t "$($SysLabel[$s]) $($cs.Name): $(if ($a) { $a } else { '結果が無い' })"; return }
      if (Onin (@(Tag-Vals $lines 'RAN')) 'yes') { Verdict 'FAIL' $t "$($SysLabel[$s]) $($cs.Name): スタブが起動していない"; return }
      $act = @(Tag-Vals $lines 'ARG')
      if (-not (Lines-Equal $exp $act)) {
        Set-Diff $exp $act "期待（<）と $($SysLabel[$s]) $($cs.Name)（>）の差分:"
        Fail-Diff $t "$($SysLabel[$s]) $($cs.Name): claude に届いた引数列が期待と違う"; return
      }
      if (Onin (@(Tag-Vals $lines 'RC')) '0') { Verdict 'FAIL' $t "$($SysLabel[$s]) $($cs.Name): ランチャーの終了コードが 0 でない"; return }
    }
  }
  Verdict 'PASS' $t "$($cases.Count) ケース（プロンプトのみ＝-- 挿入・フラグ先行・引数なし・オプション無し。= を含むキーあり）× $(Labels $avail) が期待どおり$(Missing-Note $SysAll)"
}

function Item-LauncherStaleRc {
  $t = 'ランチャー 古い $LASTEXITCODE を返さない（スタブ）'
  $avail = @(Usable @('pwsh', 'ps51'))
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t 'PowerShell 系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  foreach ($s in $avail) {
    $lines = Get-Sec $s 'launcher-stalerc'
    $a = @(Tag-Vals $lines 'ASSERT') | Select-Object -First 1
    if (One $a 'ok') { Verdict 'FAIL' $t "$($SysLabel[$s]): $(if ($a) { $a } else { '結果が無い' })"; return }
    if (Onin (@(Tag-Vals $lines 'RC')) '0') { Verdict 'FAIL' $t "$($SysLabel[$s]): 呼び出し元の古い `$LASTEXITCODE（7）が返った（RC=$(@(Tag-Vals $lines 'RC') -join ' ')）"; return }
  }
  Verdict 'PASS' $t "$(Labels $avail) とも、呼び出し元に `$LASTEXITCODE=7 が残り claude スタブが設定しなくても exit 0"
}

function Item-Optset {
  $t = 'option-settings テンプレ（全項目を有効化してロード）'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $nk = 0
  foreach ($s in $avail) {
    $lines = Get-Sec $s 'optset'
    $load = @(Tag-Vals $lines 'LOAD') | Select-Object -First 1
    $orig = @(Tag-Vals $lines 'ORIG') | Select-Object -First 1
    if (One $load 'ok') { Verdict 'FAIL' $t "$($SysLabel[$s]): 全項目版がロードできない（$load）"; return }
    if (One $orig 'ok 0') { Verdict 'FAIL' $t "$($SysLabel[$s]): 原本（全コメント）のロード結果が想定外（$orig）"; return }
    $nl = @(Tag-Vals $lines 'LINES') | Select-Object -First 1
    $nk = @(Tag-Vals $lines 'KEY').Count
    if (One $nl ([string]$nk)) { Verdict 'FAIL' $t "$($SysLabel[$s]): 有効化した $nl 行に対しキーが $nk 個（重複キー?）"; return }
  }
  if (-not (Same-All 'optset' $avail)) { Fail-Diff $t "キー集合が $($SysLabel[$script:SameA]) と $($SysLabel[$script:SameB]) で違う"; return }
  Verdict 'PASS' $t "$nk キーが $(Labels $avail) で一致。原本もロード可$(Missing-Note $SysAll)"
}

function Item-SetupEnv {
  $t = 'setup-environment（custom.env fixture）'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $bad = Test-FixKeys 'setup-environment.expect' @('SET') '定義済みの行頭タグ（SET）'
  if ($bad) { Verdict 'FAIL' $t $bad; return }
  $exp = @(Tag-Vals @(Read-Lines (Join-Path $VkFix 'setup-environment.expect')) 'SET')
  $first = $null
  $allow = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  $emptyRe = '^WARN\tcustom\.env の (.*) は空値のため設定しません'
  foreach ($s in $avail) {
    foreach ($cs in @('plain', 'bomcrlf')) {
      $lines = Get-Sec $s "setupenv $cs"
      $err = @(Tag-Vals $lines 'ERR')
      if ($err.Count -gt 0) { Verdict 'FAIL' $t "$($SysLabel[$s]) ${cs}: $($err[0])"; return }
      # 許容差: Windows は空値の環境変数を保持できない（PS 版は警告して設定しない）
      $empty = @($lines | Where-Object { $_ -cmatch $emptyRe } | ForEach-Object { [regex]::Match($_, $emptyRe).Groups[1].Value })
      foreach ($k in $empty) {
        if (Onin $exp ("$k=")) { Verdict 'FAIL' $t "$($SysLabel[$s]) ${cs}: 空値の警告が出た $k は fixture で空値ではない"; return }
      }
      $expS = @($exp | Where-Object { (Onin $empty (($_ -replace '=$', ''))) -or -not $_.EndsWith('=') })
      $act = @(Tag-Vals $lines 'SET')
      if (-not (Lines-Equal $expS $act)) {
        Set-Diff $expS $act "期待（<）と $($SysLabel[$s]) ${cs}（>）の差分:"
        Fail-Diff $t "$($SysLabel[$s]) ${cs}: 設定された環境変数が期待と違う"; return
      }
      if (@(Tag-Vals $lines 'UNSET').Count -gt 0) { Verdict 'FAIL' $t "$($SysLabel[$s]) ${cs}: 環境変数を削除している"; return }
      foreach ($k in $empty) { [void]$allow.Add($k) }
      # 系統間・ケース間の比較用（空値の SET 行と空値の警告を除いた形）
      $norm = @($lines | Where-Object { $_ -cnotmatch '^SET\t[^=]*=$' -and $_ -cnotmatch $emptyRe })
      if ($null -eq $first) { $first = $norm }
      elseif (-not (Lines-Equal $first $norm)) {
        Set-Diff $first $norm "最初の系統・ケース（<）と $($SysLabel[$s]) ${cs}（>）の差分:"
        Fail-Diff $t "$($SysLabel[$s]) ${cs}: 設定結果か警告が他の系統・ケースと違う"; return
      }
    }
  }
  $al = New-Object 'string[]' $allow.Count
  $allow.CopyTo($al)
  [Array]::Sort($al, [StringComparer]::Ordinal)
  $an = if ($al.Count -gt 0) { "（許容差: Windows は空値の env を設定しない: $($al -join ' ')）" } else { '' }
  Verdict 'PASS' $t "plain / BOM+CRLF × $(Labels $avail) で設定結果・警告が一致し期待どおり$an$(Missing-Note $SysAll)"
}

# ランチャーの内部変数名の集合は 3 か所に同じ名前が並ぶ: setup-environment.sh の case "${_key}" in 直後の IFS|…) 行、
# setup-environment.ps1 の $LauncherInternalKeys 配列、docs/launcher/launcher-implementation-plan.md の「内部変数名**（…）」の
# 列挙。片方だけ直すと分類A ガードの穴が黙って開く（custom.env fixture だけでは気付けない）ので、名前の集合を抽出して突き合わせる。
# 形が崩れて抽出できないときも FAIL にする（黙って PASS にしない）。verify-kit.sh の item_internal_keys と同じ手順・文言。
function Item-InternalKeys {
  $t = 'setup-environment 内部変数名の集合（sh / ps1 / docs）'
  $shf = Join-Full $VkRoot '.claude/launcher/setup-environment.sh'
  $psf = Join-Full $VkRoot '.claude/launcher/setup-environment.ps1'
  $mdf = Join-Full $VkRoot 'docs/launcher/launcher-implementation-plan.md'
  foreach ($f in @($shf, $psf, $mdf)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Verdict 'FAIL' $t "ファイルが無い: $($f.Substring($VkRoot.Length).TrimStart('\', '/').Replace('\', '/'))"; return }
  }
  $idRe = '^[A-Za-z_][A-Za-z0-9_]*$'
  # sh: case "${_key}" in の次の行（名前|名前|…)）
  $shl = @(Read-Lines $shf)
  $idx = @(0..($shl.Count - 1) | Where-Object { $shl[$_].Contains('case "${_key}" in') })
  if ($idx.Count -ne 1) { Verdict 'FAIL' $t "setup-environment.sh: case `"`${_key}`" in の行が 1 個ではない（$($idx.Count) 個）"; return }
  $line = if ($idx[0] + 1 -lt $shl.Count) { $shl[$idx[0] + 1].Trim() } else { '' }
  if ($line -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*(\|[A-Za-z_][A-Za-z0-9_]*)*\)$') {
    Verdict 'FAIL' $t "setup-environment.sh: case 行の形（名前|名前|…)）が崩れていて抽出できない: $line"; return
  }
  $shNames = @($line.Substring(0, $line.Length - 1).Split('|'))
  # ps1: $LauncherInternalKeys = @( … ) の中の '名前'
  $psl = @(Read-Lines $psf)
  $hdr = @(0..($psl.Count - 1) | Where-Object { Oeq $psl[$_] '$LauncherInternalKeys = @(' })
  if ($hdr.Count -ne 1) { Verdict 'FAIL' $t "setup-environment.ps1: `$LauncherInternalKeys = @( の行が 1 個ではない（$($hdr.Count) 個）"; return }
  $block = New-Object 'System.Collections.Generic.List[string]'; $closed = $false
  for ($i = $hdr[0] + 1; $i -lt $psl.Count; $i++) {
    if (Oeq $psl[$i] ')') { $closed = $true; break }
    $block.Add($psl[$i])
  }
  if (-not $closed) { Verdict 'FAIL' $t "setup-environment.ps1: `$LauncherInternalKeys の閉じ ) が行頭に見つからない"; return }
  $btxt = $block -join "`n"
  $left = [regex]::Replace([regex]::Replace($btxt, "'[A-Za-z_][A-Za-z0-9_]*'", ''), '[,\s]', '')
  if (One $left '') { Verdict 'FAIL' $t "setup-environment.ps1: 配列の形（'名前', '名前', …）が崩れていて抽出できない: $left"; return }
  $psNames = @([regex]::Matches($btxt, "'([A-Za-z_][A-Za-z0-9_]*)'") | ForEach-Object { $_.Groups[1].Value })
  if ($psNames.Count -eq 0) { Verdict 'FAIL' $t 'setup-environment.ps1: $LauncherInternalKeys に名前が 1 個も無い'; return }
  # docs: 「内部変数名**（…）」の括弧内。名前は `…` で囲まれ、start_claude_code.sh のようなファイル名は名前に数えない
  $mdl = @(Read-Lines $mdf | Where-Object { $_.Contains('内部変数名**（') -and $_.Contains('`_SENSITIVE_KEYS`') })
  if ($mdl.Count -ne 1) { Verdict 'FAIL' $t "launcher-implementation-plan.md: 「内部変数名**（」と ``_SENSITIVE_KEYS`` を含む行が 1 行ではない（$($mdl.Count) 行）"; return }
  $rest = $mdl[0].Substring($mdl[0].IndexOf('内部変数名**（', [StringComparison]::Ordinal) + '内部変数名**（'.Length)
  $ci = $rest.IndexOf('）', [StringComparison]::Ordinal)
  if ($ci -lt 0) { Verdict 'FAIL' $t 'launcher-implementation-plan.md: 内部変数名の列挙の閉じ括弧 ） が見つからない'; return }
  $seg = $rest.Substring(0, $ci)
  $mdNames = New-Object 'System.Collections.Generic.List[string]'
  foreach ($m in [regex]::Matches($seg, '`([^`]*)`')) {
    $tok = $m.Groups[1].Value
    if ($tok -cmatch $idRe) { $mdNames.Add($tok) }
    elseif ($tok -cnotmatch '^[A-Za-z0-9_.-]+\.sh$') { Verdict 'FAIL' $t "launcher-implementation-plan.md: 内部変数名の列挙に名前でもファイル名でもない ``$tok`` がある"; return }
  }
  $left = ([regex]::Matches([regex]::Replace($seg, '`[^`]*`', ''), '[A-Za-z_]') | ForEach-Object { $_.Value }) -join ''
  if (One $left '') { Verdict 'FAIL' $t "launcher-implementation-plan.md: 内部変数名の列挙にバッククォートで囲まれていない英字がある: $left"; return }
  if ($mdNames.Count -eq 0) { Verdict 'FAIL' $t 'launcher-implementation-plan.md: 内部変数名の列挙に名前が 1 個も無い'; return }
  $sets = [ordered]@{ 'sh' = $shNames; 'ps1' = $psNames; 'docs' = $mdNames.ToArray() }
  $union = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($k in $sets.Keys) { foreach ($n in $sets[$k]) { [void]$union.Add($n) } }
  $all = New-Object 'string[]' $union.Count
  $union.CopyTo($all)
  [Array]::Sort($all, [StringComparer]::Ordinal)
  $diffs = New-Object 'System.Collections.Generic.List[string]'
  foreach ($n in $all) {
    $absent = @($sets.Keys | Where-Object { Onin $sets[$_] $n })
    if ($absent.Count -gt 0) { $diffs.Add("${n}（$($absent -join '・') に無い）") }
  }
  if ($diffs.Count -gt 0) { Verdict 'FAIL' $t "名前の集合が一致しない: $($diffs -join '、')"; return }
  Verdict 'PASS' $t "sh / ps1 / docs の 3 者で同じ集合（$($all.Count) 個: $($all -join ' ')）"
}

function Item-CaRoot {
  $t = 'check-assets リポジトリルート'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  Drop-Skipping @('checkassets root') $avail
  if ($script:Kept.Count -eq 0) { Verdict 'SKIP' $t $script:SkipNote; return }
  $avail = $script:Kept
  if (-not (Same-All 'checkassets root' $avail)) { Fail-Diff $t "出力が $($SysLabel[$script:SameA]) と $($SysLabel[$script:SameB]) で違う"; return }
  $lines = Get-Sec $avail[0] 'checkassets root'
  $o = @(Tag-Vals $lines 'O')
  $nf = @($o | Where-Object { $_ -match '^\s*\[FAIL\]' }).Count
  $nw = @($o | Where-Object { $_ -match '^\s*\[WARN\]' }).Count
  $rc = @(Tag-Vals $lines 'RC') | Select-Object -First 1
  if (One $rc '0') { Verdict 'FAIL' $t "FAIL $nf 件（exit $rc）"; return }
  Verdict 'PASS' $t "$(Labels $avail) の出力が一致・FAIL=0（WARN $nw）$(Missing-Note $SysAll)$(Skip-Note)"
}

# 指定した節のどれかで SKIP を出した系統を除く。残りを Kept に、除いた系統と理由を SkipNote に入れる
$script:Kept = @(); $script:SkipNote = ''
function Drop-Skipping([string[]]$secs, [string[]]$systems) {
  $script:Kept = @(); $notes = @()
  foreach ($s in $systems) {
    $l = ''
    foreach ($n in $secs) { $l = @(Tag-Vals (Get-Sec $s $n) 'SKIP') | Select-Object -First 1; if ($l) { break } }
    if ($l) { $notes += "$($SysLabel[$s]): $l" } else { $script:Kept += $s }
  }
  $script:SkipNote = $notes -join '、'
}
function Skip-Note { if ($script:SkipNote) { return "（$($script:SkipNote)）" } else { return '' } }

function Item-CaFixture {
  $t = 'check-assets fixture（U/M/E・無害・壊れた JSON・BOM・worktree・大文字小文字違い）'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $bad = Test-FixKeys 'check-assets.expect' $CaCases "ケースの列挙（$($CaCases -join ' ')）" 4
  if ($bad) { Verdict 'FAIL' $t $bad; return }
  Drop-Skipping @($CaCases | ForEach-Object { "checkassets $_" }) $avail
  if ($script:Kept.Count -eq 0) { Verdict 'SKIP' $t $script:SkipNote; return }
  $avail = $script:Kept
  $expect = @(Read-Lines (Join-Path $VkFix 'check-assets.expect') | Where-Object { -not $_.StartsWith('#') })
  foreach ($cs in $CaCases) {
    if (@($expect | Where-Object { (Oeq ($_.Split("`t")[0]) $cs) }).Count -eq 0) { Verdict 'FAIL' $t "${cs}: check-assets.expect に期待値が無い"; return }
    if (-not (Same-All "checkassets $cs" $avail)) { Fail-Diff $t "${cs}: 判定が $($SysLabel[$script:SameA]) と $($SysLabel[$script:SameB]) で違う"; return }
    $lines = Get-Sec $avail[0] "checkassets $cs"
    $o = @(Tag-Vals $lines 'O' | ForEach-Object { $_.TrimStart() })
    foreach ($e in $expect) {
      $f = $e.Split("`t")
      if (One ($f[0]) $cs) { continue }
      if (Onin (@(Tag-Vals $lines 'RC')) ($f[1])) { Verdict 'FAIL' $t "${cs}: 終了コードが期待（$($f[1])）と違う"; return }
      # タグ - はタグの無い行（ファイル一覧）も対象にする（verify-kit.sh と同じ）
      if (@($o | Where-Object { ((Oeq ($f[2]) '-') -or $_.Contains("[$($f[2])]")) -and $_.Contains($f[3]) }).Count -eq 0) {
        Verdict 'FAIL' $t "${cs}: [$($f[2])] $($f[3]) の行が無い"; return
      }
    }
  }
  Verdict 'PASS' $t "$($CaCases.Count) ケース × $(Labels $avail) で同一判定・期待どおり（U/M/E と絶対パス混在は WARN・無害は PASS・壊れた JSON と BOM 付き・worktree の混入は FAIL・成果物の大文字小文字違いは payload で FAIL・git で WARN、env キーの大文字小文字違いは WARN で、完全一致は従来どおり）$(Missing-Note $SysAll)$(Skip-Note)"
}

function Item-CleanEnv {
  $t = 'clean-test-env（スタブ）'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $bad = Test-FixKeys 'clean-test-env.txt' @('PRE', 'OUTHAS', 'ARG', 'ENV', 'CWD', 'SETTINGS', 'AFTER', 'BADMODE', 'BADRC', 'BADOUT') '定義済みの行頭タグ（PRE / OUTHAS / ARG / ENV / CWD / SETTINGS / AFTER / BADMODE / BADRC / BADOUT）'
  if ($bad) { Verdict 'FAIL' $t $bad; return }
  $fx = @(Read-Lines (Join-Path $VkFix 'clean-test-env.txt'))
  $coreRe ='^(ARG|ENV|CWD|SETTINGS|AFTER)\t'
  $exp = @($fx | Where-Object { $_ -cmatch $coreRe })
  $outhas = @(Tag-Vals $fx 'OUTHAS')
  $first = $null
  foreach ($s in $avail) {
    $lines = Get-Sec $s 'cleanenv'
    $a = @(Tag-Vals $lines 'ASSERT') | Select-Object -First 1
    if (One $a 'ok') { Verdict 'FAIL' $t "$($SysLabel[$s]): $(if ($a) { $a } else { '結果が無い' })"; return }
    if (Onin (@(Tag-Vals $lines 'RAN')) 'yes') { Verdict 'FAIL' $t "$($SysLabel[$s]): スタブが起動していない"; return }
    if (Onin (@(Tag-Vals $lines 'RC')) '0') { Verdict 'FAIL' $t "$($SysLabel[$s]): 終了コードが 0 でない"; return }
    $act = @($lines | Where-Object { $_ -cmatch $coreRe })
    if (-not (Lines-Equal $exp $act)) {
      Set-Diff $exp $act "期待（<）と $($SysLabel[$s])（>）の差分:"
      Fail-Diff $t "$($SysLabel[$s]): 起動引数・環境・生成 settings・復元のいずれかが期待と違う"; return
    }
    $o = @(Tag-Vals $lines 'O')
    foreach ($frag in $outhas) {
      if (@($o | Where-Object { $_.Contains($frag) }).Count -eq 0) { Verdict 'FAIL' $t "$($SysLabel[$s]): 出力に「$frag」が無い"; return }
    }
    # PS 版だけが出す「環境変数を元に戻しました」（$env: の復元。bash は子プロセスなので不要）を除いて比較する
    $norm = @($lines | Where-Object { $_.StartsWith("O`t") -and -not $_.Contains('環境変数を元に戻しました') })
    if ($null -eq $first) { $first = $norm }
    elseif (-not (Lines-Equal $first $norm)) {
      Set-Diff $first $norm "最初の系統（<）と $($SysLabel[$s])（>）の出力の差分:"
      Fail-Diff $t "$($SysLabel[$s]): 出力が他の系統と違う"; return
    }
  }
  Verdict 'PASS' $t "$(Labels $avail): 起動引数・同期停止 settings・plugin 系 env の切り離しと呼び出し元の復元が期待どおりで一致$(Missing-Note $SysAll)"
}

function Item-CleanEnvBadMode {
  $t = 'clean-test-env 不正な権限モード（スタブ）'
  $avail = @(Usable $SysAll)
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t '実行できる系統が無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $fx = @(Read-Lines (Join-Path $VkFix 'clean-test-env.txt'))
  $modes = @(Tag-Vals $fx 'BADMODE')
  $erc = @(Tag-Vals $fx 'BADRC') | Select-Object -First 1
  $frag = @(Tag-Vals $fx 'BADOUT') | Select-Object -First 1
  if ($modes.Count -eq 0 -or -not $erc -or -not $frag) { Verdict 'FAIL' $t 'fixture に BADMODE / BADRC / BADOUT が無い'; return }
  for ($i = 1; $i -le $modes.Count; $i++) {
    $m = $modes[$i - 1]
    foreach ($s in $avail) {
      $lines = Get-Sec $s "cleanenv-badmode $i"
      $a = @(Tag-Vals $lines 'ASSERT') | Select-Object -First 1
      if (One $a 'ok') { Verdict 'FAIL' $t "$($SysLabel[$s]) '${m}': $(if ($a) { $a } else { '結果が無い' })"; return }
      if (One ((@(Tag-Vals $lines 'MODE') | Select-Object -First 1)) $m) { Verdict 'FAIL' $t "$($SysLabel[$s]) $i 件目: ケースの対応が取れない"; return }
      if (Onin (@(Tag-Vals $lines 'RAN')) 'no') { Verdict 'FAIL' $t "$($SysLabel[$s]) '${m}': 不正な権限モードのまま claude を起動した"; return }
      if (Onin (@(Tag-Vals $lines 'RC')) $erc) { Verdict 'FAIL' $t "$($SysLabel[$s]) '${m}': 終了コードが期待（$erc）と違う（$(@(Tag-Vals $lines 'RC') -join ' ')）"; return }
      if (@(Tag-Vals $lines 'E' | Where-Object { $_.Contains($frag) }).Count -eq 0) { Verdict 'FAIL' $t "$($SysLabel[$s]) '${m}': stderr に「$frag」が無い"; return }
      if (@(Tag-Vals $lines 'O' | Where-Object { $_.Contains($frag) }).Count -gt 0) { Verdict 'FAIL' $t "$($SysLabel[$s]) '${m}': エラー文が stdout にも出ている（stderr のみのはず）"; return }
    }
    if (-not (Same-All "cleanenv-badmode $i" $avail)) { Fail-Diff $t "'${m}': 出力が $($SysLabel[$script:SameA]) と $($SysLabel[$script:SameB]) で違う"; return }
  }
  Verdict 'PASS' $t "$($modes.Count) ケース（$($modes -join ' / ')）× $(Labels $avail) とも claude 起動前に exit $erc で停止し、出力が一致$(Missing-Note $SysAll)"
}

function Item-PubName {
  $t = 'publish-plugin --name 検証'
  $avail = @(Usable @('bash', 'pwsh'))
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t 'bash / pwsh 7 がどちらも無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $sec = @{}; $fallback = $false
  foreach ($s in $avail) {
    $sec[$s] = Get-Sec $s 'pubname'
    $m = @(Tag-Vals $sec[$s] 'MODE') | Select-Object -First 1
    if (Oeq $m 'fallback') { $fallback = $true }
    if ((Oeq $m 'real') -and (Onin (@(Tag-Vals $sec[$s] 'ASSERT')) 'ok')) {
      Verdict 'FAIL' $t "$($SysLabel[$s]): $(@(Tag-Vals $sec[$s] 'ASSERT') | Select-Object -First 1)"; return
    }
  }
  if ($fallback) {
    # 名前検証の順序を確かめられなかった版がある: 実スクリプトは実行せず、抽出した正規表現どうしの比較に落とす
    if ($avail.Count -lt 2) { Verdict 'SKIP' $t '順序を確認できず、比較相手の系統も無い'; return }
    $rx = @{}; $pc = @{}
    foreach ($s in $avail) {
      $rx[$s] = @(Tag-Vals $sec[$s] 'REGEX' | ForEach-Object { $_ -replace '^\^', '' -replace '(\\z|\$)$', '' })
      $pc[$s] = @($sec[$s] | Where-Object { $_.StartsWith("CASE`t") } | ForEach-Object { $_ -replace ' rc=.*', '' })
    }
    if ((Lines-Equal $rx[$avail[0]] $rx[$avail[1]]) -and (Lines-Equal $pc[$avail[0]] $pc[$avail[1]])) {
      Verdict 'PASS' $t "フォールバック（名前検証が副作用より前にあると確認できず、実スクリプトは未実行）: 抽出した正規表現と $($pc[$avail[0]].Count) ケースの判定が bash / pwsh で一致"
    } else {
      Verdict 'FAIL' $t 'フォールバック（実スクリプト未実行）: 抽出した正規表現かケースの判定が bash / pwsh で違う'
    }
    return
  }
  $rows = @(Read-Lines (Join-Path $VkFix 'plugin-names.tsv') | Where-Object { (One $_ '') -and -not $_.StartsWith('#') })
  $nacc = 0; $nrej = 0; $narg = 0; $nother = 0
  foreach ($s in $avail) {
    if (@(Tag-Vals $sec[$s] 'ORDER' | Where-Object { $_.StartsWith('ok') }).Count -eq 0) { Verdict 'FAIL' $t "$($SysLabel[$s]): 順序確認の結果が無い"; return }
    $col = if ($s -eq 'bash') { 0 } else { 1 }
    for ($idx = 1; $idx -le $rows.Count; $idx++) {
      $f = $rows[$idx - 1].Split("`t")
      $name = if ($f.Count -ge 3) { $f[2] } else { '' }
      $exp = $f[$col]
      $rest = @($sec[$s] | Where-Object { $_.StartsWith("CASE`t$idx ") } | ForEach-Object { Val $_ }) | Select-Object -First 1
      $cls = if ($rest) { $rest.Split(' ')[1] } else { '' }
      if (One $cls $exp) { Verdict 'FAIL' $t "$($SysLabel[$s]): '$name' は $exp のはずが $(if ($cls) { $cls } else { '結果なし' })（$rest）"; return }
      # 名前検証で止まるケースでは git も claude も呼ばれていない（＝検証が副作用より前）。通過したケースではスタブの git が呼ばれる
      if (Oeq $cls 'accept') {
        if ($rest -notmatch 'stubcalls=[1-9]') { Verdict 'FAIL' $t "$($SysLabel[$s]): '$name' で git スタブが呼ばれていない"; return }
      } elseif ($rest -notmatch 'stubcalls=0$') {
        Verdict 'FAIL' $t "$($SysLabel[$s]): '$name' の拒否より前に git / claude が呼ばれた"; return
      }
      if ($s -eq $avail[0]) {
        if (Oeq ($f[0]) ($f[1])) {
          if (Oeq ($f[0]) 'accept') { $nacc++ } elseif (Oeq ($f[0]) 'argerr') { $narg++ } else { $nrej++ }
        } else {
          $nother++
        }
      }
    }
  }
  $note = if ($nother -gt 0) { "・両版で期待が異なるケース $nother 件（plugin-names.tsv の列どおり）" } else { '' }
  Verdict 'PASS' $t "実スクリプト（git / claude はスタブ）で受理 $nacc・拒否 $nrej・引数エラー $narg$note。$(Labels $avail) とも期待どおり、拒否ケースでは git / claude 未呼び出し（5.1 は #requires -Version 7 のため対象外）$(Missing-Note @('bash', 'pwsh'))"
}

function Item-PubCase {
  $t = 'publish-plugin 大文字小文字だけが違う既存エントリ（偽 marketplace）'
  $avail = @(Usable @('bash', 'pwsh'))
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t 'bash / pwsh 7 がどちらも無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $rows = @(Read-Lines (Join-Path $VkFix 'plugin-case.tsv') | Where-Object { (One $_ '') -and -not $_.StartsWith('#') })
  $nclash = 0; $npass = 0
  foreach ($s in $avail) {
    $sec = Get-Sec $s 'pubcase'
    $a = @(Tag-Vals $sec 'ASSERT') | Select-Object -First 1
    if (One $a 'ok') { Verdict 'FAIL' $t "$($SysLabel[$s]): $a"; return }
    for ($idx = 1; $idx -le $rows.Count; $idx++) {
      $f = $rows[$idx - 1].Split("`t")
      $exp = $f[0]; $ent = $f[1]; $name = $f[2]
      $rest = @($sec | Where-Object { $_.StartsWith("CASE`t$idx ") } | ForEach-Object { Val $_ }) | Select-Object -First 1
      $cls = if ($rest) { $rest.Split(' ')[1] } else { '' }
      if (One $cls $exp) { Verdict 'FAIL' $t "$($SysLabel[$s]): plugins/$ent に対する '$name' は $exp のはずが $(if ($cls) { $cls } else { '結果なし' })（$rest）"; return }
      if (-not $rest.EndsWith(' intact=yes')) { Verdict 'FAIL' $t "$($SysLabel[$s]): '$name' で既存の plugins/$ent が変化した（$rest）"; return }
      if ($s -eq $avail[0]) { if (Oeq $exp 'clash') { $nclash++ } else { $npass++ } }
    }
  }
  Verdict 'PASS' $t "実スクリプト（git / claude はスタブ）で中止 $nclash・通過 $npass。$(Labels $avail) とも期待どおり、中止は取り出しより前に exit 2・既存エントリは無傷（5.1 は #requires -Version 7 のため対象外）$(Missing-Note @('bash', 'pwsh'))"
}

function Item-PubManifest {
  $t = 'publish-plugin plugin.json の name 照合（一時リポジトリ）'
  $avail = @(Usable @('bash', 'pwsh'))
  if ($avail.Count -eq 0) { Verdict 'SKIP' $t 'bash / pwsh 7 がどちらも無い'; return }
  $c = Crashed-In $avail
  if ($c) { Verdict 'FAIL' $t "$($SysLabel[$c]) の probe が異常終了した"; return }
  $notes = New-Object 'System.Collections.Generic.List[string]'
  $sec = @{}; $run = @()
  foreach ($s in $avail) {
    $sec[$s] = Get-Sec $s 'pubmanifest'   # @() で包まない（Get-Sec は配列を 1 個の値として返す）
    $sk = @(Tag-Vals $sec[$s] 'SKIP') | Select-Object -First 1
    if ($sk) { $notes.Add("$($SysLabel[$s]): $sk"); continue }
    $a = @(Tag-Vals $sec[$s] 'ASSERT') | Select-Object -First 1
    if (One $a 'ok') { Verdict 'FAIL' $t "$($SysLabel[$s]): $a"; return }
    $run += $s
  }
  if ($run.Count -eq 0) { Verdict 'SKIP' $t ($notes -join '、'); return }
  $rows = @(Read-Lines (Join-Path $VkFix 'plugin-manifest.tsv') | Where-Object { (One $_ '') -and -not $_.StartsWith('#') })
  $seen = @{}; $clsOf = @{}
  $npass = 0; $nmis = 0; $nunr = 0; $nnopy = 0
  foreach ($s in $run) {
    $col = if ($s -eq 'bash') { 0 } else { 1 }
    for ($idx = 1; $idx -le $rows.Count; $idx++) {
      $f = $rows[$idx - 1].Split("`t", 6)
      $exp = $f[$col]; $name = $f[4]; $json = if ($f.Count -ge 6) { $f[5] } else { '' }
      if (Oeq $exp '-') { continue }
      $rest = @($sec[$s] | Where-Object { $_.StartsWith("CASE`t$idx ") } | ForEach-Object { Val $_ }) | Select-Object -First 1
      $cls = if ($rest) { $rest.Split(' ')[1] } else { '' }
      $clsOf["${s}:$idx"] = $cls
      if (Oeq $cls 'skip') { $notes.Add("$($SysLabel[$s]) ケース ${idx}: $($rest.Substring($rest.IndexOf(' skip ') + 6))"); continue }
      if (One $cls $exp) { Verdict 'FAIL' $t "$($SysLabel[$s]): ケース $idx（名前 '$name'・$json）は $exp のはずが $(if ($cls) { $cls } else { '結果なし' })（$rest）"; return }
      if (-not $rest.EndsWith(' intact=yes')) { Verdict 'FAIL' $t "$($SysLabel[$s]): ケース $idx で一時 marketplace が変化した（$rest）"; return }
      if ((One $cls 'pass') -and @($sec[$s] | Where-Object { $_.StartsWith("MSG`t$idx ‼") }).Count -eq 0) {
        Verdict 'FAIL' $t "$($SysLabel[$s]): ケース $idx（$cls）で中止の文言（‼ の行）が無い"; return
      }
      if (-not $seen.ContainsKey($idx)) {
        $seen[$idx] = $true
        switch -CaseSensitive ($cls) { 'pass' { $npass++ } 'mismatch' { $nmis++ } 'unreadable' { $nunr++ } 'nopython' { $nnopy++ } }
      }
    }
  }
  # 両版で同じ中止になるケースは、文言（MSG）と終了コードが一致すること
  $cmpNote = ''
  if ($run.Count -eq 2) {
    $ncmp = 0
    for ($idx = 1; $idx -le $rows.Count; $idx++) {
      $f = $rows[$idx - 1].Split("`t", 6)
      if ((One ($f[0]) ($f[1])) -or (Oeq ($f[0]) 'pass') -or (Oeq ($f[0]) '-')) { continue }
      if ((One ($clsOf["bash:$idx"]) ($f[0])) -or (One ($clsOf["pwsh:$idx"]) ($f[0]))) { continue }
      $m = @{}
      foreach ($s in @('bash', 'pwsh')) {
        $caseLine = @($sec[$s] | Where-Object { $_.StartsWith("CASE`t$idx ") }) | Select-Object -First 1
        $m[$s] = @($sec[$s] | Where-Object { $_.StartsWith("MSG`t$idx ") }) + @($caseLine -replace '^.* (rc=[^ ]*) .*$', '$1')
      }
      if (-not (Lines-Equal $m['bash'] $m['pwsh'])) {
        Set-Diff $m['bash'] $m['pwsh'] "bash と pwsh 7 の差分（ケース $idx）:"
        Fail-Diff $t "ケース $idx（$($f[0])）の中止の文言か終了コードが bash / pwsh 7 で違う"; return
      }
      $ncmp++
    }
    $cmpNote = "・中止の文言と終了コードは bash / pwsh 7 で一致（$ncmp ケース）"
  }
  $skipNote = if ($notes.Count -gt 0) { "（SKIP: $($notes -join '、')）" } else { '' }
  Verdict 'PASS' $t "実スクリプトのコピー（一時の開発リポ・remote の無い一時 marketplace・実物の git・claude はスタブ・stdin は空）で通過 $npass・不一致で中止 $nmis・読めずに中止 $nunr・python 無しで中止 $nnopy。$(Labels $run) とも期待どおり、中止は validate より前に exit 1・marketplace は無傷（commit も index への追加も無い）$cmpNote$skipNote（5.1 は #requires -Version 7 のため対象外）$(Missing-Note @('bash', 'pwsh'))"
}

$LeftPaths = @('.claude/option-settings.sh', '.claude/option-settings.ps1', '.claude/custom.env',
               '.claude/launcher/option-settings.sh', '.claude/launcher/option-settings.ps1', '.claude/launcher/custom.env')
function Snapshot-Left { @($LeftPaths | Where-Object { Test-Path -LiteralPath (Join-Full $VkRoot $_) }) }

function Item-Left([string[]]$before) {
  $t = 'リポジトリ .claude/ に試験用ファイルを作っていない'
  $new = @(Snapshot-Left | Where-Object { (Onin $before $_) })
  if ($new.Count -gt 0) { Verdict 'FAIL' $t "実行中に作られた: $($new -join ' ')"; return }
  if ($before.Count -gt 0) { Verdict 'PASS' $t "新規作成なし（実行前からある個人実体: $($before -join ' ')）" }
  else { Verdict 'PASS' $t '新規作成なし' }
}

$t0 = Get-Date
$VkTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('verify-kit-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $VkTmp | Out-Null
try {
  $leftBefore = @(Snapshot-Left)
  Write-Host "[verify-kit] 対象: $VkRoot"
  Invoke-Probes $VkTmp
  $sys = @($SysAll | ForEach-Object {
      if ($SysState[$_] -eq 'ok') { "$($SysName[$_]) $($SysVer[$_])" } else { "$($SysLabel[$_])（$($SysWhy[$_])）" }
    }) -join ' / '
  Write-Host "[verify-kit] 系統: $sys"
  Item-Syntax 'bash' '構文 bash -n（.sh / .sh.template）'
  Item-Syntax 'pwsh' '構文 pwsh 7 Parser（.ps1 / .ps1.template）'
  Item-Syntax 'ps51' '構文 Windows PowerShell 5.1 Parser（.ps1 / .ps1.template）'
  Item-Format
  Item-Version
  Item-Launcher
  Item-LauncherStaleRc
  Item-Optset
  Item-SetupEnv
  Item-InternalKeys
  Item-CaRoot
  Item-CaFixture
  Item-CleanEnv
  Item-CleanEnvBadMode
  Item-PubName
  Item-PubCase
  Item-PubManifest
  Item-Left $leftBefore
  if ($VkVerbose) {
    foreach ($s in $SysAll) {
      $lf = Join-Path $VkTmp "log-$s.txt"
      if (-not (Test-Path -LiteralPath $lf)) { continue }
      Write-Host "  --- probe ログ（$($SysLabel[$s])）---"
      @(Read-Lines $lf) | Select-Object -First 40 | ForEach-Object { Write-Host "         | $_" }
    }
  }
  Write-Host ("[verify-kit] 集計: PASS {0} / FAIL {1} / SKIP {2}（所要 {3} 秒）" -f $script:NPass, $script:NFail, $script:NSkip, [int]((Get-Date) - $t0).TotalSeconds)
} finally {
  Remove-Item -LiteralPath $VkTmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:NFail -gt 0) { exit 1 } else { exit 0 }
