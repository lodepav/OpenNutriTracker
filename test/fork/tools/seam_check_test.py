# The pure part of fork/tools/seam_check.py, on made-up data.
#   python3 test/fork/tools/seam_check_test.py
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../fork/tools'))
import seam_check as sc  # noqa: E402


class SeamCheckTest(unittest.TestCase):
    def test_a_marker_counts_for_every_id_before_its_colon(self):
        self.assertEqual(sc.marker_ids("import 'x.dart'; // [fork] S1 S21 S113"), {'S1', 'S21', 'S113'})
        self.assertEqual(sc.marker_ids('// [fork] S28 weight-import, S44 steps, S48 body-fat-import, S49'),
                         {'S28', 'S44', 'S48', 'S49'})
        # Prose after the colon may name another seam; that is not a marker for it.
        self.assertEqual(sc.marker_ids("// [fork] S18 dev-adaptive: as main's S6"), {'S18'})
        self.assertEqual(sc.marker_ids('// [fork] S83: titled as S177 does'), {'S83'})

    def test_a_file_added_under_an_upstream_path_needs_a_row_or_a_marker(self):
        diff = ['M\tlib/features/a.dart', 'A\tlib/features/new.dart', 'A\ttest/helpers/new_test.dart',
                'A\tlib/features/marked.dart', 'A\tlib/features/named.dart', 'A\tlib/features/named.g.dart',
                'M\tlib/features/b.dart', 'A\t.claude/skills/x/SKILL.md', 'A\tandroid/app/src/fork/x.xml',
                'M\t.gitignore']
        markers = {'lib/features/a.dart': {'S1'}, 'lib/features/marked.dart': {'S2'}}
        paths = {'lib/features/named.dart', 'lib/features/b*'}
        self.assertEqual(sc.unmarked(diff, markers, paths), [
            'lib/features/new.dart: added under an upstream path, with no marker and no row',
            'test/helpers/new_test.dart: added under an upstream path, with no marker and no row',
        ])
        self.assertEqual(sc.unmarked(['M\tlib/features/c.dart'], markers, paths),
                         ['lib/features/c.dart: changed from upstream, with no marker and no row'])


if __name__ == '__main__':
    unittest.main()
