#!/usr/bin/env python3
"""Remove `#Preview { ... }` blocks from Swift files in place.

The SwiftUI preview macro plugin ships only with full Xcode, so the
Command Line Tools build in build-local.sh strips previews from a copy of
the sources before compiling. Usage: strip_previews.py FILE...
"""
import re
import sys


def strip(src: str) -> str:
    out = []
    i = 0
    for m in re.finditer(r"^[ \t]*#Preview\b", src, re.M):
        if m.start() < i:
            continue
        out.append(src[i:m.start()])
        j = src.index("{", m.end())
        depth = 0
        in_str = False
        while j < len(src):
            c = src[j]
            if in_str:
                if c == "\\":
                    j += 1
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        i = j + 1
    out.append(src[i:])
    return "".join(out)


for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as f:
        src = f.read()
    if "#Preview" in src:
        with open(path, "w", encoding="utf-8") as f:
            f.write(strip(src))
