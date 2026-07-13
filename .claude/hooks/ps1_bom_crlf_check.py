#!/usr/bin/env python3
"""Fail a .ps1 edit that dropped the UTF-8 BOM or the CRLF line endings.

Windows PowerShell 5.1 reads a BOM-less .ps1 as CP932, so a lost BOM silently
mojibakes every Japanese string in the script -- and the BOM is file *content*,
which .gitattributes cannot restore. Claude Code's own file tools have twice
regressed here (v2.1.77: Write silently converted line endings when overwriting
a CRLF file; v2.1.89: Edit/Write doubled CRLF on Windows), and the docs specify
no contract for either, so this is checked rather than assumed.

Measured on this repo: Edit preserves BOM + CRLF, Write does not -- a .ps1
created with Write lands as BOM-less LF.

Wired as a PostToolUse hook on Edit/Write of **/*.ps1 (see .claude/settings.json).
Rewriting the file from the hook would fight the tool that just wrote it, so this
reports and lets Claude fix it.
"""
import json
import pathlib
import sys

BOM = b"\xef\xbb\xbf"


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    raw = (payload.get("tool_input") or {}).get("file_path")
    if not raw or not str(raw).lower().endswith((".ps1", ".psm1", ".psd1", ".ps1.template")):
        return 0

    path = pathlib.Path(raw)
    if not path.is_file():
        return 0

    data = path.read_bytes()
    problems = []
    if not data.startswith(BOM):
        problems.append(
            "UTF-8 BOM が無い（Windows PowerShell 5.1 が CP932 と誤読して日本語が化ける）"
        )
    if b"\n" in data and b"\r\n" not in data:
        problems.append("改行が LF になっている（CRLF が必要）")
    if not problems:
        return 0

    fix = (
        f"PowerShell で直す:\n"
        f"  $p = '{path}'\n"
        f"  $t = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))\n"
        f"  $t = $t -replace \"`r`n\", \"`n\" -replace \"`n\", \"`r`n\"\n"
        f"  [System.IO.File]::WriteAllText($p, $t, [System.Text.UTF8Encoding]::new($true))"
    )
    json.dump(
        {
            "decision": "block",
            "reason": (
                f"{path.name} の保存形式が壊れている: {' / '.join(problems)}。\n"
                f"`.ps1` は **UTF-8 + BOM + CRLF** で保存する（Write ツールは BOM も CRLF も"
                f"保持しないため、新規作成すると必ずこうなる）。\n{fix}"
            ),
            "hookSpecificOutput": {"hookEventName": "PostToolUse"},
        },
        sys.stdout,
        ensure_ascii=False,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
