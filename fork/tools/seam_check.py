#!/usr/bin/env python3
"""Checks fork/SEAMS.md against the code (README rule 2).

    fork/tools/seam_check.py            # exit 1 on a finding

  - a seam id on two rows, which merge=union lets through when two branches take the
    same next number: renumber the later one, in its row and its markers;
  - a [fork] S<n> marker with no row, or a row no marker or path backs;
  - an upstream file the fork changed that neither has a marker nor is named on a row.
    Formatting-only churn counts: restore the file to upstream's.
"""
import fnmatch
import re
import subprocess
import sys

SEAMS = 'fork/SEAMS.md'
FORK_OWNED = (':!fork', ':!lib/fork', ':!test/fork', ':!lib/generated', ':!pubspec.lock')
# Changed on purpose, nothing to mark: fork-only ignore lines.
ALLOWED = {'.gitignore'}


def git(*args):
    done = subprocess.run(['git', *args], capture_output=True, text=True)
    return done.stdout if done.returncode == 0 else ''


rows = [line for line in open(SEAMS, encoding='utf-8') if re.match(r'\| (S\d+) \|', line)]
row_ids = [re.match(r'\| (S\d+) \|', r).group(1) for r in rows]
findings = []

for seam in sorted({s for s in row_ids if row_ids.count(s) > 1}, key=lambda s: int(s[1:])):
    findings.append(f'{seam}: on {row_ids.count(seam)} rows')

markers = {}
for line in git('grep', '-nE', r'\[fork\] *S[0-9]+', '--', '.', ':!fork').splitlines():
    path = line.split(':', 1)[0]
    markers.setdefault(path, set()).update(re.findall(r'\[fork\] *(S\d+)', line))
marked = set().union(*markers.values()) if markers else set()
for seam in sorted(marked - set(row_ids), key=lambda s: int(s[1:])):
    where = sorted(p for p, ids in markers.items() if seam in ids)[0]
    findings.append(f'{seam}: marker in {where} has no row')

# Every backticked path on a row, and the "Carried upstream changes" ones.
paths = set(re.findall(r'`([\w./*-]+)`', open(SEAMS, encoding='utf-8').read()))


def named(path):
    return any(fnmatch.fnmatch(path, p) for p in paths)


upstream = next((r for r in ('upstream/main', 'upstream/develop')
                 if git('rev-parse', '-q', '--verify', r)), None)
if upstream is None:
    print('seam_check: no upstream remote here, only the rows and markers are checked')
else:
    base = git('merge-base', 'HEAD', upstream).strip()
    changed = git('diff', '--name-only', '--diff-filter=M', base, 'HEAD', '--', '.', *FORK_OWNED)
    for path in changed.splitlines():
        if path in ALLOWED or path in markers or named(path):
            continue
        # A generated file goes with its source: S117 names off_product_dto.dart.
        if path.endswith('.g.dart') and named(path.replace('.g.dart', '.dart')):
            continue
        findings.append(f'{path}: changed from upstream, with no marker and no row')

for finding in findings:
    print(f'seam_check: {finding}', file=sys.stderr)
if findings:
    sys.exit(1)
print(f'seam_check: {len(set(row_ids))} seams, {len(markers)} files with markers: fine')
