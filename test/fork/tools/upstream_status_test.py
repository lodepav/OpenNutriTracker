# The pure part of fork/tools/upstream_status.py, on made-up data.
#   python3 test/fork/tools/upstream_status_test.py
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../fork/tools'))
import upstream_status as us  # noqa: E402

SEAMS = '''# Seams
| S1 | `lib/a.dart` | Sent upstream as #20; also see upstream's #5. | active |
| S2 | `lib/b.dart` | Nothing sent, mentions #200. | active |
| S3 | `lib/c.dart` | Fix sent as #30. | active |

## Fork-owned copies

| `lib/fork/a.dart` | `lib/a.dart` | `abc` | S1 |

## Carried upstream changes

| Branch | What it changes | Upstream |
|---|---|---|
| `feat/x` | Does x (#20). | PR #20 |
| `upstream-pr/y` | Does y. | open |
| `feat/z` | Does z. | PR not opened yet |
| S4 | `lib/d.dart` | A seam row after the table, #20. | active |
'''

PRS = [
    {'number': 20, 'title': 'X', 'state': 'MERGED', 'headRefName': 'upstream-pr/x', 'mergeCommit': {'oid': 'aaa'}},
    {'number': 30, 'title': 'C', 'state': 'OPEN', 'headRefName': 'upstream-pr/c', 'mergeCommit': None},
    {'number': 31, 'title': 'Y', 'state': 'MERGED', 'headRefName': 'upstream-pr/y', 'mergeCommit': {'oid': 'bbb'}},
    {'number': 10, 'title': 'Old', 'state': 'CLOSED', 'headRefName': 'upstream-pr/c', 'mergeCommit': None},
    {'number': 11, 'title': 'Gone', 'state': 'CLOSED', 'headRefName': 'upstream-pr/gone', 'mergeCommit': None},
]


class UpstreamStatusTest(unittest.TestCase):
    def test_rows_are_found_by_heading_and_shape(self):
        self.assertEqual([c['branch'] for c in us.carried_rows(SEAMS)], ['feat/x', 'upstream-pr/y', 'feat/z'])
        self.assertEqual([s['id'] for s in us.seam_rows(SEAMS)], ['S1', 'S2', 'S3', 'S4'])
        self.assertEqual(us.pr_numbers('#20, #5 and #200x, not #2000'), {20, 5, 200, 2000})

    def test_pr_rows_newest_first_with_branch_and_containment(self):
        rows = us.pr_rows(PRS, {'upstream-pr/x', 'upstream-pr/c'}, {'aaa': (True, False)})
        self.assertEqual([(r['number'], r['state'], r['branch']) for r in rows],
                         [(31, 'merged', None), (30, 'open', 'upstream-pr/c'), (20, 'merged', 'upstream-pr/x'),
                          (11, 'closed', None), (10, 'closed', 'upstream-pr/c')])
        self.assertEqual((rows[2]['in_develop'], rows[2]['in_tag']), (True, False))
        self.assertEqual((rows[0]['in_develop'], rows[1]['in_develop']), (None, None))
        text = us.render(rows, 'v1.0').split('\n')
        self.assertRegex(text[0], r'^#\s+state\s+local branch\s+in develop\s+in v1\.0\s+title$')
        self.assertRegex(text[3], r'^#20\s+merged\s+upstream-pr/x\s+yes\s+no\s+X$')

    def test_ready_to_drop_names_merged_prs_and_finished_branches(self):
        porcelain = ('worktree /src/main\nHEAD a\nbranch refs/heads/fork/main\n\n'
                     'worktree /src/x\nHEAD b\nbranch refs/heads/upstream-pr/x\n\n'
                     'worktree /src/c\nHEAD c\nbranch refs/heads/upstream-pr/c\n\n'
                     'worktree /src/d\nHEAD d\ndetached\n')
        worktrees = us.parse_worktrees(porcelain)
        self.assertEqual([w['path'] for w in worktrees], ['/src/x', '/src/c', '/src/d'])
        drop = us.ready_to_drop(PRS, us.seam_rows(SEAMS), us.carried_rows(SEAMS),
                                ['upstream-pr/x', 'upstream-pr/c', 'upstream-pr/gone', 'upstream-pr/none'], worktrees)
        # S2's #200 and S1's #5 are not the fork's PRs; S3's #30 is still open.
        self.assertEqual(drop['seams'], [('S1', [20]), ('S4', [20])])
        self.assertEqual(drop['carried'], [('feat/x', [20]), ('upstream-pr/y', [31])])
        # upstream-pr/c's newest PR is open, so its older closed one does not count.
        self.assertEqual(drop['branches'], [('upstream-pr/gone', 11, 'closed'), ('upstream-pr/x', 20, 'merged')])
        self.assertEqual(drop['worktrees'], [('/src/x', 'upstream-pr/x', 20, 'merged')])
        text = us.render_drop(drop)
        self.assertIn('  S1  (#20)', text)
        self.assertIn('  /src/x  upstream-pr/x  (#20, merged)', text)
        empty = us.render_drop({'seams': [], 'carried': [], 'branches': [], 'worktrees': []})
        self.assertEqual(empty.count('  none'), 4)


if __name__ == '__main__':
    unittest.main()
