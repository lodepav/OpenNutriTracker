#!/usr/bin/env python3
"""What became of the fork's pull requests on upstream, and what the fork can drop.

    fork/tools/upstream_status.py

Per PR lodepav opened on upstream: number, state (open, merged, closed), the local branch that
carries it, for a merged PR whether its merge commit is in upstream/develop and in the newest
v* release tag, and the title. Then what is ready to drop: seam rows and "Carried upstream
changes" rows of fork/SEAMS.md that name a merged PR (the fork can take upstream's version), and
local branches and worktrees whose PR is merged or closed. It reads the refs of the last
`git fetch upstream`. It prints only: it deletes nothing and writes nothing on GitHub.
Ported from openGym-Hevier's hevier/tools/upstream-status.mjs; tested by
test/fork/tools/upstream_status_test.py.
"""
import json
import re
import subprocess
import sys

UPSTREAM = 'simonoppowa/OpenNutriTracker'
AUTHOR = 'lodepav'
SEAMS = 'fork/SEAMS.md'
DEVELOP = 'upstream/develop'


def pr_numbers(text):
    return {int(n) for n in re.findall(r'#(\d+)(?!\d)', text)}


def carried_rows(seams_text):
    """The "Carried upstream changes" rows, found by heading and row shape, not position."""
    rows, inside = [], False
    for line in seams_text.splitlines():
        if line.startswith('## '):
            inside = line.strip() == '## Carried upstream changes'
            continue
        m = re.match(r'\| `([^`]+)` \|', line)
        if inside and m:
            rows.append({'branch': m.group(1), 'text': line})
    return rows


def seam_rows(seams_text):
    return [{'id': m.group(1), 'text': line}
            for line in seams_text.splitlines() if (m := re.match(r'\| (S\d+) \|', line))]


def parse_worktrees(porcelain):
    """`git worktree list --porcelain` as [{path, branch}], the main checkout (the first) left out."""
    out = []
    for block in re.split(r'\n\n+', porcelain.strip()):
        path = re.search(r'^worktree (.+)$', block, re.M)
        branch = re.search(r'^branch refs/heads/(.+)$', block, re.M)
        if path:
            out.append({'path': path.group(1), 'branch': branch.group(1) if branch else None})
    return out[1:]


def state_of(pr):
    return str(pr.get('state') or '').lower()


def pr_rows(prs, branches, contains):
    """prs as gh gives them; contains: {merge commit oid: (in develop, in the tag)}, None if unknown."""
    rows = []
    for pr in sorted(prs, key=lambda p: -p['number']):
        oid = (pr.get('mergeCommit') or {}).get('oid')
        inside = contains.get(oid, (None, None)) if state_of(pr) == 'merged' else (None, None)
        rows.append({
            'number': pr['number'],
            'state': state_of(pr),
            'branch': pr.get('headRefName') if pr.get('headRefName') in branches else None,
            'in_develop': inside[0],
            'in_tag': inside[1],
            'title': pr['title'],
        })
    return rows


def ready_to_drop(prs, seams, carried, branches, worktrees):
    """Seams and carried rows naming a merged PR; branches and worktrees whose newest PR is done."""
    merged = {p['number'] for p in prs if state_of(p) == 'merged'}
    merged_heads = {p.get('headRefName'): p['number'] for p in prs if state_of(p) == 'merged'}
    newest = {}
    for pr in sorted(prs, key=lambda p: p['number']):
        newest[pr.get('headRefName')] = pr
    done = {b: p for b, p in newest.items() if state_of(p) in ('merged', 'closed')}
    return {
        'seams': [(s['id'], sorted(pr_numbers(s['text']) & merged)) for s in seams
                  if pr_numbers(s['text']) & merged],
        'carried': [(c['branch'], sorted((pr_numbers(c['text']) & merged)
                                         | ({merged_heads[c['branch']]} if c['branch'] in merged_heads else set())))
                    for c in carried
                    if pr_numbers(c['text']) & merged or c['branch'] in merged_heads],
        'branches': [(b, done[b]['number'], state_of(done[b])) for b in sorted(branches) if b in done],
        'worktrees': [(w['path'], w['branch'], done[w['branch']]['number'], state_of(done[w['branch']]))
                      for w in worktrees if w['branch'] in done],
    }


def yes_no(value):
    return '-' if value is None else ('yes' if value else 'no')


def render(rows, tag):
    head = ['#', 'state', 'local branch', 'in develop', f'in {tag}', 'title']
    cells = [[f"#{r['number']}", r['state'], r['branch'] or '-', yes_no(r['in_develop']),
              yes_no(r['in_tag']), r['title']] for r in rows]
    table = [head, *cells]
    width = [max(len(c[i]) for c in table) for i in range(len(head) - 1)]
    return '\n'.join('  '.join(c[i].ljust(width[i]) for i in range(len(width))) + '  ' + c[-1]
                     for c in table)


def render_drop(drop):
    def section(title, items):
        return ['', title] + ([f'  {i}' for i in items] if items else ['  none'])
    out = ['== Ready to drop (suggestions only, nothing is deleted)']
    out += section('Seam rows that name a merged PR (take upstream\'s version):',
                   [f"{s}  ({', '.join(f'#{n}' for n in ns)})" for s, ns in drop['seams']])
    out += section('Carried upstream changes rows whose PR is merged:',
                   [f"{b}  ({', '.join(f'#{n}' for n in ns)})" for b, ns in drop['carried']])
    out += section('Local branches whose PR is merged or closed:',
                   [f'{b}  (#{n}, {st})' for b, n, st in drop['branches']])
    out += section('Worktrees whose PR is merged or closed:',
                   [f'{p}  {b}  (#{n}, {st})' for p, b, n, st in drop['worktrees']])
    return '\n'.join(out)


# git and gh

def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def is_ancestor(oid, ref):
    code = subprocess.run(['git', 'merge-base', '--is-ancestor', oid, ref], capture_output=True).returncode
    return None if code > 1 else code == 0


def main(argv):
    if argv:
        print('usage: fork/tools/upstream_status.py', file=sys.stderr)
        return 2
    root = run('git', 'rev-parse', '--show-toplevel').strip()
    # gh pr list stops at 30 unless asked for more; ask for far more than there are.
    prs = json.loads(run('gh', 'pr', 'list', '-R', UPSTREAM, '--author', AUTHOR, '--state', 'all',
                         '--limit', '1000', '--json', 'number,title,state,headRefName,mergeCommit') or '[]')
    tag = run('git', 'tag', '--list', 'v*', '--sort=-v:refname').split('\n')[0]
    contains = {}
    for pr in prs:
        oid = (pr.get('mergeCommit') or {}).get('oid')
        if state_of(pr) == 'merged' and oid:
            contains[oid] = (is_ancestor(oid, DEVELOP), is_ancestor(oid, tag))
    branches = run('git', 'branch', '--list', 'upstream-pr/*', '--format=%(refname:short)').split()
    worktrees = parse_worktrees(run('git', 'worktree', 'list', '--porcelain'))
    with open(f'{root}/{SEAMS}', encoding='utf-8') as f:
        seams_text = f.read()
    rows = pr_rows(prs, set(branches), contains)
    drop = ready_to_drop(prs, seam_rows(seams_text), carried_rows(seams_text), branches, worktrees)
    print(f'PRs by {AUTHOR} on {UPSTREAM} (newest release tag {tag}):')
    print(render(rows, tag))
    print()
    print(render_drop(drop))
    counts = {s: sum(r['state'] == s for r in rows) for s in ('open', 'merged', 'closed')}
    print()
    print(f"Summary: {len(rows)} PRs ({counts['open']} open, {counts['merged']} merged, "
          f"{counts['closed']} closed), {len(drop['seams'])} seam rows, {len(drop['carried'])} carried rows, "
          f"{len(drop['branches'])} branches and {len(drop['worktrees'])} worktrees ready to drop.")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
