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
fork/tools/verify.sh    # about 2.5 min: Bash timeout 500000
```

No conflict marker, `fork/tools/seam_check.py`, the tests of `upstream_status.py`, `actions_status.py` and `seam_check.py` (`test/fork/tools/`), `fork/tools/sibling_check.sh` (the same `heavy.sh` lock and emulator `-gpu` flag as openGym-Hevier's), `fork/DECISIONS-INDEX.md` against `fork/tools/decision-index.sh` (after a new decision: `fork/tools/decision-index.sh > fork/DECISIONS-INDEX.md`), analyze, and the whole suite bundled (`fork/tools/test-fast.sh`). A red upstream test means the fork changed behaviour it shouldn't have: fix the fork, never the test (fork/README.md, rule 4).

A clean pass is remembered by commit: merge, then push, and the hook doesn't run it again. A later commit that changes only `.md` files or `fork/VERSION`, or adds an upgrade fixture, passes on that stamp too.

`fork/tools/verify.sh --strict` is the strict level: it rebuilds the `*.g.dart` files (a stale committed one fails) and the strings, then runs plain `flutter test`, a process a file, as upstream's CI. The Fork checks workflow runs it on GitHub, and it never passes on a stamp. To tell a bundled failure from a file's own, run that file alone: `flutter test -j 1 <file>`.

A `verify: warning:` line that names GitHub's Fork checks (from `fork/tools/actions_status.py`, printed by every `verify.sh` run) is about what was already pushed, not about this tree: the line says whether the run for `origin/fork/main` is missing or ended red, or that GitHub couldn't be read. It doesn't fail the pass or block the merge. Go on, and tell the user the line in your reply.

## What enforces it

`fork/hooks/`, on once a clone by `fork/tools/install-hooks.sh`:

- **pre-push**: a push to `fork/main` runs `verify.sh` on the working tree, so it needs that commit checked out and a clean tree. Give the push a Bash timeout of 500000 unless verify just passed. A push after a docs-only commit passes on the stamp.
- **commit-msg**: a merge into `fork/main` needs the subject `Merge fork/<branch>: what it does`, which is what the release notes read. It also lets through `Merge upstream release ...` and git's own subjects for pulling `origin/fork/main`.

`verify.sh` warns when `core.hooksPath` isn't `fork/hooks`: run `fork/tools/install-hooks.sh`.

`--no-verify` skips them. Use it only when the user says so.

## Before a release

`fork/tools/release-apk.sh` runs the bundled `verify.sh` (usually passed on its stamp at the push), with `fork/tools/release-check.sh`'s source gates and the release manifest's permissions and exported components beside it, then builds and runs `release-check.sh` on the APK. Its gates block. The strict level is the Fork checks run on GitHub: the release stops if it failed for the commit, or is missing because the commit isn't pushed yet (push `fork/main` first), and waits for one still running before it tags.

`.github/workflows/fork-checks.yml` runs the strict level on every push to `fork/main`. `fork/tools/release-apk.sh` is local only, not in git.
