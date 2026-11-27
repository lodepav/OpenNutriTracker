# The pure part of fork/tools/test_bundles.py.
#   python3 test/fork/tools/test_bundles_test.py
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../fork/tools'))
import test_bundles as b  # noqa: E402


def report(*tests):
    lines = []
    for i, (name, ms) in enumerate(tests):
        lines.append(json.dumps({'type': 'testStart', 'test': {'id': i, 'name': name}, 'time': 1000}))
        lines.append(json.dumps({'type': 'testDone', 'testID': i, 'time': 1000 + ms}))
    return lines


class FileTimesTest(unittest.TestCase):
    def test_a_files_tests_and_hooks_add_up(self):
        times = b.file_times(report(
            ('fork/a_test.dart (setUpAll)', 500),
            ('fork/a_test.dart saves the photo', 1500),
            ('fork/b_test.dart group a test', 250),
        ))
        self.assertEqual(times, {'fork/a_test.dart': 2.0, 'fork/b_test.dart': 0.25})

    def test_a_cut_off_line_and_a_test_outside_a_bundle_are_left_out(self):
        lines = report(('fork/a_test.dart one', 1000), ('loading test/_bundle_0.dart', 9000))
        lines.append('{"type": "testSta')
        self.assertEqual(b.file_times(lines), {'fork/a_test.dart': 1.0})


class SplitTest(unittest.TestCase):
    def test_slow_files_go_to_different_bundles(self):
        times = {'a': 40, 'b': 30, 'c': 20, 'd': 10}
        self.assertEqual(b.split(list('abcd'), times, 2), [['a', 'd'], ['b', 'c']])

    def test_a_new_file_counts_as_an_average_one(self):
        times = {'a': 10, 'b': 2}
        self.assertEqual(b.split(['a', 'b', 'new'], times, 2), [['a'], ['b', 'new']])

    def test_without_times_files_are_dealt_in_turn(self):
        self.assertEqual(b.split(list('abcde'), {}, 2), [['a', 'c', 'e'], ['b', 'd']])


if __name__ == '__main__':
    unittest.main()
