# The pure part of fork/tools/actions_status.py.
#   python3 test/fork/tools/actions_status_test.py
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../fork/tools'))
import actions_status as a  # noqa: E402

PUSHED = 'a' * 40


class WarningTest(unittest.TestCase):
    def test_checked_and_green_says_nothing(self):
        run = {'headSha': PUSHED, 'status': 'completed', 'conclusion': 'success'}
        self.assertIsNone(a.warning(PUSHED, run))

    def test_still_running_says_nothing(self):
        self.assertIsNone(a.warning(PUSHED, {'headSha': PUSHED, 'status': 'in_progress', 'conclusion': None}))

    def test_a_push_no_run_followed(self):
        run = {'headSha': 'b' * 40, 'status': 'completed', 'conclusion': 'success'}
        self.assertIn('has not checked origin/fork/main (aaaaaaaa)', a.warning(PUSHED, run))

    def test_a_failed_run(self):
        run = {'headSha': PUSHED, 'status': 'completed', 'conclusion': 'failure'}
        self.assertIn('ended as failure', a.warning(PUSHED, run))

    def test_no_run_at_all(self):
        self.assertIn('no Fork checks run', a.warning(PUSHED, None))


if __name__ == '__main__':
    unittest.main()
