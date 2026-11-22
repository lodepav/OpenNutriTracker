#!/usr/bin/env bash
# OpenBite and Go Hevier share a machine: their copies of heavy.sh must hold the same lock, or
# a build and a suite overlap unseen, and both emulator launchers must boot through
# ~/.claude/bin/emu, or one drops the shared AVDs' snapshots or drives the other's emulator.
# Skipped where the other repo isn't checked out (CI).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -d "$ROOT/hevier/tools" ]]; then
  ours=hevier/tools; theirs="$ROOT/../OpenNutriTracker/fork/tools"
else
  ours=fork/tools; theirs="$ROOT/../openGym-Hevier/hevier/tools"
fi
ours="$ROOT/$ours"
[[ -f "$theirs/heavy.sh" ]] || exit 0

same() {  # what, its line in ours, its line in theirs
  [[ "$2" == "$3" && -n "$2" ]] && return 0
  echo "sibling_check: $1 differs from the other repo: '$2' here, '$3' there" >&2
  return 1
}
lock() { grep -E '^lock=' "$1/heavy.sh" || true; }
emu() { grep -v '^[[:space:]]*#' "$1/emulator.sh" | grep -q '\.claude/bin/emu' && echo "boots through emu" || true; }
same "heavy.sh's lock" "$(lock "$ours")" "$(lock "$theirs")"
same "the emulator launcher" "$(emu "$ours")" "$(emu "$theirs")"
