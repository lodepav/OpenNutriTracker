#!/usr/bin/env bash
# Runs a build or a whole test suite while no other one runs, in this repo or
# in openGym-Hevier, which has its own copy of this script and the same lock.
# Two at once beside the emulator is what ran this 14 GB machine out of memory:
# the kernel's OOM killer took qemu nine times in 18 hours (2026-10-30/31).
#
#   fork/tools/heavy.sh flutter build apk ...
#
# flock -o: what the command leaves running (a Gradle daemon, the emulator)
# doesn't inherit the lock. Called inside another heavy.sh, it just runs.
set -euo pipefail

[[ -n "${HEAVY_LOCK_HELD:-}" ]] && exec "$@"
export HEAVY_LOCK_HELD=1
lock="/tmp/heavy-work-$(id -u).lock"
flock -n "$lock" true || echo "heavy.sh: waiting for another build or suite to finish..." >&2
exec flock -o "$lock" "$@"
