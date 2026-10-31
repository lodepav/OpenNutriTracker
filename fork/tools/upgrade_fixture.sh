#!/usr/bin/env bash
# Writes test/fork/upgrade/fixtures/<version>.tar.gz: a release's demo data on disk, which
# test/fork/upgrade/upgrade_test.dart opens with the current code.
#
#   fork/tools/upgrade_fixture.sh <version>           # from the working tree (the release does this)
#   fork/tools/upgrade_fixture.sh <version> <commit>  # from an old release, in a worktree of its own
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="$HOME/flutter/bin:$PATH"
VER="$1"
COMMIT="${2:-}"
OUT="$ROOT/test/fork/upgrade/fixtures/$VER.tar.gz"
TMP="$(mktemp -d)"
SRC="$ROOT"
cleanup() {
  [[ -n "$COMMIT" ]] && git -C "$ROOT" worktree remove --force "$TMP/src" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

if [[ -n "$COMMIT" ]]; then
  git -C "$ROOT" worktree add -q --detach "$TMP/src" "$COMMIT"
  SRC="$TMP/src"
  mkdir -p "$SRC/test/fork/upgrade"
  cp "$ROOT"/test/fork/upgrade/{boot_app,write_fixture}.dart "$SRC/test/fork/upgrade/"
  cp "$ROOT/lib/core/utils/env.g.dart" "$SRC/lib/core/utils/"
  (cd "$SRC" && flutter pub get >/dev/null && flutter gen-l10n)
fi

mkdir -p "$TMP/data" "$(dirname "$OUT")"
(cd "$SRC" && FIXTURE_DIR="$TMP/data" flutter test test/fork/upgrade/write_fixture.dart --reporter=compact >"$TMP/log" 2>&1) || {
  tail -25 "$TMP/log" >&2
  echo "upgrade_fixture: $VER failed" >&2
  exit 1
}
# Only the data: the empty boxes matter as much, images don't.
tar -C "$TMP/data" --sort=name --mtime='2026-01-01 00:00Z' --owner=0 --group=0 --numeric-owner \
  -czf "$OUT" fixture.json $(cd "$TMP/data" && ls ./*.hive)
echo "wrote $OUT ($(du -h "$OUT" | cut -f1)): $(tar -xzOf "$OUT" ./fixture.json 2>/dev/null || tar -xzOf "$OUT" fixture.json)"
