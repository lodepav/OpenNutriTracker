#!/usr/bin/env python3
"""Says when GitHub has not checked what was pushed to fork/main.

The Fork checks workflow runs on every push; Actions was once off for two weeks and
nothing said so. verify.sh calls this: it prints a warning or nothing, and never fails.

  fork/tools/actions_status.py
"""
import json
import os
import re
import shutil
import subprocess
import sys

WORKFLOW = 'fork-checks.yml'
BRANCH = 'fork/main'


def warning(pushed, run):
    """The warning for the pushed commit and the newest run (None when there is none)."""
    if run is None:
        return f'GitHub has no Fork checks run for {BRANCH}: is Actions on for the repository?'
    sha = run.get('headSha', '')
    if sha != pushed:
        return (f'GitHub has not checked origin/{BRANCH} ({pushed[:8]}): its last Fork checks '
                f'run was on {sha[:8]}. Is Actions on for the repository?')
    if run.get('status') == 'completed' and run.get('conclusion') != 'success':
        return f"GitHub's Fork checks run on {sha[:8]} ended as {run.get('conclusion')}"
    return None


def _out(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=15, check=True).stdout.strip()


def main():
    if os.environ.get('CI') or not shutil.which('gh'):
        return
    try:
        pushed = _out('git', 'rev-parse', '-q', '--verify', f'origin/{BRANCH}')
        repo = re.sub(r'^.*github\.com[:/]|\.git$', '', _out('git', 'remote', 'get-url', 'origin'))
        runs = json.loads(_out('gh', 'run', 'list', '-R', repo, '--workflow', WORKFLOW,
                               '--branch', BRANCH, '-L', '1',
                               '--json', 'headSha,status,conclusion'))
    except (subprocess.SubprocessError, ValueError, OSError):
        print("verify: warning: couldn't read the Fork checks run on GitHub", file=sys.stderr)
        return
    said = warning(pushed, runs[0] if runs else None)
    if said:
        print(f'verify: warning: {said}', file=sys.stderr)


if __name__ == '__main__':
    main()
