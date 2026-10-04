"""Brace balance check for the native Android and iOS sources.

Neither Kotlin nor Swift can be compiled on a machine without the Android
toolchain or Xcode, which is why a duplicated handler block in
MainActivity.kt and a stray brace in AppDelegate.swift both survived to CI.

This is a syntax check, not a type check. It ignores comments and string
literals, so brace characters inside them do not count. A green result means
"this parses", never "this compiles".

Usage:
    python scripts/check_native_syntax.py
"""

from __future__ import annotations

import pathlib
import re
import sys

PAIRS = [("{", "}"), ("(", ")"), ("[", "]")]


def strip(src: str) -> str:
    """Remove comments and string/char literals so braces inside them do not count."""
    out: list[str] = []
    i = 0
    n = len(src)
    in_line = in_block = in_str = in_char = in_raw = in_interp = False
    while i < n:
        c = src[i]
        nx = src[i + 1] if i + 1 < n else " "
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
        elif in_block:
            if c == "*" and nx == "/":
                in_block = False
                i += 1
        elif in_raw:
            # Swift raw strings: r"..." / #"..."#
            if c == '"' and nx == '"':
                in_raw = False
                i += 1
        elif in_interp:
            if c == "\\":
                i += 1
            elif c == '"':
                in_interp = False
        elif in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        elif in_char:
            if c == "\\":
                i += 1
            elif c == "'":
                in_char = False
        elif c == "/" and nx == "/":
            in_line = True
            i += 1
        elif c == "/" and nx == "*":
            in_block = True
            i += 1
        elif c == '"' and nx == '"' and i + 2 < n and src[i + 2] == '"':
            in_raw = True
            i += 2
        elif c == '"':
            # A Swift string interpolation \( ... ) is code, so keep it.
            if i + 1 < n and src[i + 1] == "\\":
                in_interp = True
            else:
                in_str = True
        elif c == "'":
            in_char = True
        else:
            out.append(c)
        i += 1
    return "".join(out)


def check(path: pathlib.Path) -> bool:
    if not path.is_file():
        print(f"MISSING   {path}")
        return False
    src = path.read_text(encoding="utf-8")
    code = strip(src)
    ok = True
    for open_c, close_c in PAIRS:
        a, b = code.count(open_c), code.count(close_c)
        if a != b:
            line = _locate(code, open_c, close_c)
            print(f"UNBALANCED {path}: {open_c!r} x{a} vs {close_c!r} x{b} near {line}")
            ok = False
    # A second companion object brace-balances perfectly but does not compile,
    # and the Kotlin error ("Only one companion object is allowed per class")
    # does not point at the constant that went missing. That is exactly how
    # EXTRA_CANCEL_BATCH became unresolvable here, so it is checked explicitly.
    companions = len(re.findall(r"\bcompanion\s+object\b", code))
    if companions > 1:
        print(
            f"DUPLICATE {path}: {companions} companion objects, "
            "a class may declare only one"
        )
        ok = False

    lines = len(src.splitlines())
    print(f"{'BALANCED ' if ok else 'BROKEN   '}{path} ({lines} lines)")
    return ok


def _locate(code: str, open_c: str, close_c: str) -> str:
    """Report the line where the imbalance appears, for a usable error message."""
    depth = 0
    line = 1
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch == open_c:
            depth += 1
        elif ch == close_c:
            depth -= 1
            if depth < 0:
                return f"line ~{line} (more closes than opens)"
    return f"line ~{line} (unclosed)"


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    targets: list[pathlib.Path] = []
    for pattern in ("android/app/src/main/kotlin/**/*.kt", "ios/Runner/*.swift"):
        targets.extend(sorted(root.glob(pattern)))
    # Ephemeral generated Swift is not ours and is not compiled from the repo.
    targets = [t for t in targets if "ephemeral" not in str(t)]
    if not targets:
        print("no native sources found; is this run from the repo root?")
        return 2
    bad = sum(0 if check(t) else 1 for t in targets)
    print(f"\n{len(targets) - bad}/{len(targets)} balanced")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())