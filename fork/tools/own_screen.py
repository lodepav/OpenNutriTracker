#!/usr/bin/env python3
"""Takes an upstream file the fork mostly rewrote into lib/fork (D23).

    fork/tools/own_screen.py <upstream file> <fork copy> [upstream ref]

Copies the file as the fork has it to <fork copy> without its [fork] markers
(a marker's note stays as a plain comment), then restores the upstream file
to [upstream ref] (default: the upstream/main the fork contains). Callers,
tests and SEAMS.md's "Fork-owned copies" row are left to do by hand.
"""
import re
import subprocess
import sys
from pathlib import Path

upstream, copy = Path(sys.argv[1]), Path(sys.argv[2])
ref = sys.argv[3] if len(sys.argv) > 3 else subprocess.check_output(
    ['git', 'merge-base', 'HEAD', 'upstream/main'], text=True).strip()

OPEN = re.compile(r'^(\s*)// \[fork\] S[\w-]+(?: [\w-]+)?(?:: ?(.*))?$')
CLOSE = re.compile(r'^\s*// \[/fork\]\s*$')
INLINE = re.compile(r'\s*\[fork\] S[\w-]+')

out = [f'// Fork-owned copy of {upstream} (D23); upstream\'s later changes to it\n',
       '// are ported by hand: fork/tools/upstream-copies.sh.\n']
for line in upstream.read_text().splitlines(keepends=True):
    if CLOSE.match(line):
        continue
    m = OPEN.match(line)
    if m:
        if m.group(2):
            out.append(f'{m.group(1)}// {m.group(2)}\n')
        continue
    if INLINE.search(line):
        line = INLINE.sub('', line)
        # The marker was all of the comment: no bare `//` left behind.
        if re.match(r'^\s*//\s*$', line):
            continue
        line = re.sub(r'\s*//\s*$', '', line.rstrip('\n')) + '\n'
    out.append(line)

copy.parent.mkdir(parents=True, exist_ok=True)
copy.write_text(''.join(out))
upstream.write_bytes(subprocess.check_output(['git', 'show', f'{ref}:{upstream}']))
print(f'{upstream} -> {copy}; {upstream} restored to {ref[:8]}')
