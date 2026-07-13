#!/usr/bin/env python3
"""Let Claude work on CP932 .bat files without ever corrupting them.

`.bat` must stay CP932 on disk: cmd.exe does not skip a BOM (it breaks line 1),
and putting `chcp 65001` at the top degrades console rendering. Claude's file
tools assume UTF-8, so they read a CP932 .bat as mojibake and would write UTF-8
back over it. The original is therefore never handed to the file tools.

    read   PreToolUse rewrites Read's file_path to a UTF-8 shadow under
           .claude/.bat-shadow/ -- updatedInput works for Read.
    guide  PostToolUse(Read) tells Claude to edit that shadow, not the original.
    write  PostToolUse compiles an edited shadow back to CP932 + CRLF. A character
           with no CP932 code point aborts the write-back and leaves the original
           untouched, so a broken .bat can never reach the repo.
    block  settings.json denies Edit/Write on **/*.bat outright. updatedInput is
           IGNORED by Edit and Write (measured) -- they would reach the original
           and write UTF-8 into it -- and a hook cannot be the guarantee anyway:
           with no Python on PATH it fails open. The deny rule is the hard guard;
           this script is the convenience. Hence the shadow is *.utf8.txt and not
           *.bat: deny beats allow, so a shadow named *.bat would be caught by the
           very rule that protects the original.

Modes:
    pre / post   hook entry points (see .claude/settings.json)
    new <path>   scaffold a new .bat (Write is denied, so Claude cannot create one)
    sync         refresh every shadow, so Grep over .claude/.bat-shadow/ can search
                 .bat content that Grep cannot match in CP932
"""
import json
import os
import pathlib
import subprocess
import sys

SHADOW_SUBDIR = pathlib.PurePosixPath(".claude/.bat-shadow")
SHADOW_SUFFIX = ".utf8.txt"
ORIGIN_SUFFIX = ".origin"

# Wave dash, em dash and friends have no CP932 code point but do have a CP932
# counterpart; normalise them instead of rejecting the write-back. The table in
# the win-file-encoding skill is the source of truth -- this is only the fallback.
MAPPING_JSON = pathlib.PurePosixPath(
    ".claude/skills/win-file-encoding/references/cp932-mapping.json"
)
FALLBACK_TO_WIN = {"〜": "～", "−": "－", "—": "―", "‖": "∥", "¢": "￠", "£": "￡", "¬": "￢"}


def project_root() -> pathlib.Path:
    return pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())


def to_win_map() -> dict[str, str]:
    try:
        data = json.loads((project_root() / MAPPING_JSON).read_text(encoding="utf-8"))
        return data.get("to_win") or FALLBACK_TO_WIN
    except (OSError, ValueError):
        return FALLBACK_TO_WIN


def normalise(text: str) -> str:
    for src, dst in to_win_map().items():
        text = text.replace(src, dst)
    return text


def shadow_root() -> pathlib.Path:
    return project_root() / SHADOW_SUBDIR


def is_shadow(path: pathlib.Path) -> bool:
    try:
        return shadow_root().resolve() in path.resolve().parents
    except OSError:
        return False


def shadow_for(src: pathlib.Path) -> pathlib.Path:
    """Mirror the project-relative path so two same-named .bat never collide."""
    try:
        rel = src.resolve().relative_to(project_root().resolve())
    except ValueError:
        rel = pathlib.Path(src.name)  # outside the project: fall back to the bare name
    return shadow_root() / rel.with_name(rel.name + SHADOW_SUFFIX)


def origin_of(shadow: pathlib.Path) -> pathlib.Path | None:
    ref = shadow.with_name(shadow.name + ORIGIN_SUFFIX)
    if not ref.is_file():
        return None
    return pathlib.Path(ref.read_text(encoding="utf-8").strip())


def emit(obj: dict) -> int:
    json.dump(obj, sys.stdout, ensure_ascii=False)
    return 0


def unmappable(text: str) -> list[str]:
    bad = []
    for ch in dict.fromkeys(text):
        try:
            ch.encode("cp932")
        except UnicodeEncodeError:
            bad.append(f"{ch} (U+{ord(ch):04X})")
    return bad


def write_shadow(src: pathlib.Path, text: str) -> pathlib.Path:
    shadow = shadow_for(src)
    shadow.parent.mkdir(parents=True, exist_ok=True)
    shadow.write_text(text.replace("\r\n", "\n"), encoding="utf-8", newline="\n")
    shadow.with_name(shadow.name + ORIGIN_SUFFIX).write_text(str(src), encoding="utf-8")
    return shadow


def refresh(src: pathlib.Path) -> pathlib.Path:
    """Raise UnicodeDecodeError if the .bat is not actually CP932."""
    return write_shadow(src, src.read_bytes().decode("cp932"))


def compile_back(shadow: pathlib.Path, src: pathlib.Path) -> list[str]:
    """Write the shadow back as CP932 + CRLF. Returns the offending characters, if any."""
    text = normalise(shadow.read_text(encoding="utf-8"))
    bad = unmappable(text)
    if bad:
        return bad
    body = text.replace("\r\n", "\n").replace("\n", "\r\n")
    src.write_bytes(body.encode("cp932"))
    return []


# --- hook entry points -------------------------------------------------------


def handle_pre(tool: str, path: pathlib.Path) -> int:
    if is_shadow(path) or tool != "Read" or not path.is_file():
        return 0
    try:
        shadow = refresh(path)
    except UnicodeDecodeError as exc:
        print(f"{path} を CP932 として読めない（{exc}）。この .bat は CP932 ではない。", file=sys.stderr)
        return 2
    return emit(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "updatedInput": {"file_path": str(shadow)},
            }
        }
    )


def handle_post(tool: str, path: pathlib.Path) -> int:
    if not is_shadow(path) or not path.is_file():
        return 0
    src = origin_of(path)
    if src is None:
        return 0

    if tool == "Read":
        return emit(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": (
                        f"[bat-cp932-guard] {src.name} は CP932 で保存する .bat のため、"
                        f"いま読んだのは UTF-8 の作業コピー {path} である。"
                        f"編集するときは原本ではなく**この作業コピーを Edit すること**"
                        f"（原本への Edit / Write は permissions.deny で拒否される）。"
                        f"保存すると自動で CP932 + CRLF へ書き戻される。"
                        f"CP932 に存在しない文字（⚠ ✓ — 等）は書き戻し時に拒否されるので、"
                        f"メッセージ記号は ASCII（[!] / [OK] 等）を使うこと。"
                    ),
                }
            }
        )

    bad = compile_back(path, src)
    if bad:
        return emit(
            {
                "decision": "block",
                "reason": (
                    f"{src.name} は CP932 で保存する必要があるが、CP932 に存在しない文字が含まれている: "
                    f"{', '.join(bad)}。**原本は書き換えていない**。"
                    f"これらを ASCII（[!] / [OK] 等）へ置き換えて編集し直すこと。"
                ),
                "hookSpecificOutput": {"hookEventName": "PostToolUse"},
            }
        )
    return 0


def run_hook(phase: str) -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # malformed payload: stay out of the way

    raw = (payload.get("tool_input") or {}).get("file_path")
    if not raw:
        return 0
    path = pathlib.Path(raw)
    # The `if` conditions in settings.json already narrow this down, but they fail
    # open, so re-check: we touch originals (*.bat) and their shadows, nothing else.
    if not str(raw).lower().endswith(".bat") and not is_shadow(path):
        return 0

    tool = payload.get("tool_name", "")
    return handle_pre(tool, path) if phase == "pre" else handle_post(tool, path)


# --- CLI modes ---------------------------------------------------------------


def mode_new(target: str) -> int:
    src = pathlib.Path(target)
    if src.suffix.lower() != ".bat":
        print(f"'{target}' は .bat ではない。", file=sys.stderr)
        return 1
    if src.exists():
        print(f"'{target}' は既に存在する。Read してから作業コピーを編集すること。", file=sys.stderr)
        return 1
    src.parent.mkdir(parents=True, exist_ok=True)
    src.write_bytes("@echo off\r\n".encode("cp932"))
    shadow = refresh(src)
    print(f"作成した: {src}（CP932 + CRLF・空の .bat）")
    print(f"以降はこの作業コピーを Edit すること: {shadow}")
    return 0


def ignored(paths: list[pathlib.Path]) -> set[pathlib.Path]:
    """Paths git would ignore. Empty set when git is unavailable -- sync is best-effort."""
    if not paths:
        return set()
    root = project_root()
    # check-ignore only accepts repo-relative, forward-slash paths: a Windows absolute
    # path is read as C-style escapes ("\b" -> backspace) and git rejects it.
    rel = {p.relative_to(root).as_posix(): p for p in paths}
    try:
        # -z, and bytes rather than text=True: on Windows text mode rewrites the "\n"
        # separators to "\r\n", so git sees paths ending in CR and echoes them back
        # quoted -- every lookup then misses and nothing gets filtered.
        proc = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "--stdin", "-z"],
            input="\0".join(rel).encode("utf-8"),
            capture_output=True,
        )
    except OSError:
        return set()
    out = proc.stdout.decode("utf-8", "replace")
    return {rel[token] for token in out.split("\0") if token in rel}


def mode_sync() -> int:
    root = project_root()
    candidates = [
        p for p in root.rglob("*.bat") if not is_shadow(p) and ".git" not in p.parts
    ]
    skip = ignored(candidates)  # build artefacts and session work dirs are not interesting
    count, skipped = 0, []
    for src in candidates:
        if src in skip:
            continue
        try:
            refresh(src)
            count += 1
        except UnicodeDecodeError:
            skipped.append(str(src))
    print(f"作業コピーを更新: {count} 件 -> {shadow_root()}")
    if skipped:
        print("CP932 として読めずスキップ:", file=sys.stderr)
        for s in skipped:
            print(f"  {s}", file=sys.stderr)
    print("Grep で .bat の中身を検索するときは .claude/.bat-shadow/ を対象にすること。")
    return 0


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "pre"
    if mode in ("pre", "post"):
        return run_hook(mode)
    if mode == "new":
        if len(sys.argv) < 3:
            print("使い方: bat_cp932_guard.py new <作成する .bat のパス>", file=sys.stderr)
            return 1
        return mode_new(sys.argv[2])
    if mode == "sync":
        return mode_sync()
    print(f"不明なモード: {mode}（pre / post / new / sync）", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
