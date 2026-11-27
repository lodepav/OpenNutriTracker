#!/usr/bin/env bash
# The whole test suite in about a fifth of the time: every test file is
# imported into one of a few generated bundles, so the suite compiles a few
# times rather than once a file (most of a plain run is that compiling).
#
#   fork/tools/test-fast.sh            # 4 bundles, run side by side
#   SHARDS=2 fork/tools/test-fast.sh   # fewer, for less memory
#
# Each file's tests run in a group named after it. A bundle shares one
# process, so after each file it closes Hive's boxes and resets the app's
# chosen locale, the service locator and the skipped days, which tests leave behind: left, they
# break later files. The check
# before a merge; plain `flutter test`, a file a process, stays the strict
# one, which fork/tools/verify.sh --strict runs on GitHub for each push, and for when
# a bundled run fails and you want to know whether a file's own tests do. The bundles (test/_bundle_*.dart) are
# deleted at the end and ignored by git; fork/tools/test_bundles.py writes them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="$HOME/flutter/bin:$PATH"
cd "$ROOT"

trap 'rm -f test/_bundle_*.dart' EXIT

# Each run's timings spread the next run's files evenly over the bundles.
REPORT=build/test-fast/last.json
mkdir -p build/test-fast
python3 -B fork/tools/test_bundles.py "${SHARDS:-4}" "$REPORT"
# A run narrowed by arguments (--name, a file) would leave timings for a few tests only.
KEEP=(); [[ $# -eq 0 ]] && KEEP=(--file-reporter "json:$REPORT")

# lib/generated is not committed: a pulled ARB change needs it rebuilt.
flutter gen-l10n
fork/tools/heavy.sh flutter test "${KEEP[@]}" test/_bundle_*.dart test/fork/upgrade/upgrade_test.dart \
  test/fork/diary/day_macro_goals_follow_profile_edit_test.dart test/fork/profile/demo_name_test.dart \
  test/fork/demo/demo_per_profile_test.dart test/fork/demo/demo_legacy_mark_test.dart "$@"
