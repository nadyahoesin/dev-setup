#!/usr/bin/env python3
"""Print the .md path under terminal cell column X of LINE; exit 1 if none."""
import re
import sys
import unicodedata

x, line = int(sys.argv[1]), sys.argv[2]
col, idx = 0, None
for i, ch in enumerate(line):
    w = 2 if unicodedata.east_asian_width(ch) in "WF" else 1  # wide glyphs take two cells
    if col <= x < col + w:
        idx = i
        break
    col += w
if idx is None:
    sys.exit(1)
for m in re.finditer(r"[^\s`'\"()<>\[\]{},;]+", line):
    if m.start() <= idx < m.end():
        tok = re.sub(r"(:\d+)+$", "", m.group(0).rstrip(".:"))
        if tok.lower().endswith(".md"):
            print(tok)
            sys.exit(0)
sys.exit(1)
