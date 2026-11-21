# fork/tools/eval_failed.py on a made-up typed report.
#   python3 test/fork/tools/eval_failed_test.py
import os
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../fork/tools'))
import eval_failed as ef  # noqa: E402


class TypedFailedTest(unittest.TestCase):
    def test_the_usage_section_is_not_a_model(self):
        ef.typed_reads = lambda: ['en|an apple', 'en|a pear']
        with tempfile.TemporaryDirectory() as d:
            (pathlib.Path(d) / 'report.md').write_text(
                '## model-a\n| an apple | en | ok |\n\n'
                '## Usage\n| model | calls | cost |\n| model-a | 2 | 0.01 |\n')
            self.assertEqual(ef.typed_failed(pathlib.Path(d)), {'model-a': ['en|a pear']})


if __name__ == '__main__':
    unittest.main()
