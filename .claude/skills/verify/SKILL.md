---
name: verify
description: Run OpenBite's checks. Before a merge into fork/main the seams, analyze and the whole suite; on each commit the changed tests. Use after any change, before merging a branch or upstream into fork/main, or when asked to verify, test or "check everything".
---

# Verify

Report the counts, and quote any failure in full. A failure that shows only in the bundled run is a bug to fix, not a baseline: a test leaves state behind.

The emulator can stay up for all of this: with it at 3 GB, the whole suite beside it ended with 4.3 GB free and swap untouched (2026-10-31). Builds and whole suites queue on one lock (`fork/tools/heavy.sh`), shared with openGym-Hevier, so a wait of a few minutes may be another session's build.

## Every commit

```bash
flutter analyze lib test
flutter test -j 1 <the test files of what changed>
```

## Before a merge

```bash
fork/tools/verify.sh    # about 2.5 min: Bash timeout 400000
```

No conflict marker, `fork/tools/seam_check.py`, analyze, and the whole suite bundled (`fork/tools/test-fast.sh`). A red upstream test means the fork changed behaviour it shouldn't have: fix the fork, never the test (fork/README.md, rule 4).

A clean pass is remembered by commit: merge, then push, and the hook doesn't run it again.

## What enforces it

`fork/hooks/`, on once a clone by `fork/tools/install-hooks.sh`:

- **pre-push**: a push to `fork/main` runs `verify.sh` on the working tree, so it needs that commit checked out and a clean tree. Give the push a Bash timeout of 400000 unless verify just passed. A push after a docs-only commit doesn't run it again.
- **commit-msg**: a merge into `fork/main` needs the subject `Merge fork/<branch>: what it does`, which is what the release notes read.

`--no-verify` skips them. Use it only when the user says so.

## Before a release

`fork/tools/release-apk.sh` runs `verify.sh --strict` itself (plain `flutter test`, a process a file, about 8.5 min), then builds and runs `fork/tools/release-check.sh` on the APK. Its gates block.
