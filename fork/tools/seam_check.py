#!/usr/bin/env python3
"""Checks fork/SEAMS.md against the code (README rule 2).

    fork/tools/seam_check.py            # exit 1 on a finding

  - a seam id on two rows, which merge=union lets through when two branches take the
    same next number: renumber the later one, in its row and its markers;
  - a [fork] S<n> marker with no row; every id before the marker's colon counts;
  - an upstream file the fork changed that neither has a marker nor is named on a row.
    Formatting-only churn counts: restore the file to upstream's;
  - a file the fork added under lib/ or test/ (outside lib/fork, test/fork) with neither.
    It is wholly fork code: name it on a row.
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


def marker_ids(line):
    # shortcut: ids wrapped onto the next comment line are not read, upgrade if a seam needs them.
    return set(re.findall(r'\bS\d+\b', line.split('[fork]', 1)[1].split(':', 1)[0]))


def unmarked(diff, markers, paths):
    """The findings for `git diff --name-status` lines: files with no marker and no row."""
    def named(path):
        return any(fnmatch.fnmatch(path, p) for p in paths)

    found = []
    for line in diff:
        status, path = line.split('\t', 1)
        # Added files elsewhere (.claude/, android/app/src/fork/, assets/fork/) are the fork's by place.
        if status == 'A' and not path.startswith(('lib/', 'test/')):
            continue
        if path in ALLOWED or path in markers or named(path):
            continue
        # A generated file goes with its source: S117 names off_product_dto.dart.
        if path.endswith('.g.dart') and named(path.replace('.g.dart', '.dart')):
            continue
        how = 'added under an upstream path' if status == 'A' else 'changed from upstream'
        found.append(f'{path}: {how}, with no marker and no row')
    return found


def main():
    text = open(SEAMS, encoding='utf-8').read()
    rows = [line for line in text.splitlines() if re.match(r'\| (S\d+) \|', line)]
    row_ids = [re.match(r'\| (S\d+) \|', r).group(1) for r in rows]
    findings = []

    for seam in sorted({s for s in row_ids if row_ids.count(s) > 1}, key=lambda s: int(s[1:])):
        findings.append(f'{seam}: on {row_ids.count(seam)} rows')

    markers = {}
    for line in git('grep', '-nE', r'\[fork\] *S[0-9]+', '--', '.', ':!fork').splitlines():
        path = line.split(':', 1)[0]
        markers.setdefault(path, set()).update(marker_ids(line))
    marked = set().union(*markers.values()) if markers else set()
    for seam in sorted(marked - set(row_ids), key=lambda s: int(s[1:])):
        where = sorted(p for p, ids in markers.items() if seam in ids)[0]
        findings.append(f'{seam}: marker in {where} has no row')

    # Every backticked path on a row, and the "Carried upstream changes" ones.
    paths = set(re.findall(r'`([\w./*-]+)`', text))

    upstream = next((r for r in ('upstream/main', 'upstream/develop')
                     if git('rev-parse', '-q', '--verify', r)), None)
    if upstream is None:
        print('seam_check: no upstream remote here, only the rows and markers are checked')
    else:
        base = git('merge-base', 'HEAD', upstream).strip()
        diff = git('diff', '--name-status', '--no-renames', '--diff-filter=AM', base, 'HEAD', '--', '.', *FORK_OWNED)
        findings += unmarked(diff.splitlines(), markers, paths)

    for finding in findings:
        print(f'seam_check: {finding}', file=sys.stderr)
    if findings:
        sys.exit(1)
    print(f'seam_check: {len(set(row_ids))} seams, {len(markers)} files with markers: fine')


if __name__ == '__main__':
    main()
