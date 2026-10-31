---
name: upstream-merge
description: Merge a new upstream OpenNutriTracker release into fork/main, resolve conflicts by the fork's rules, and check for silent drift. Use when asked to sync, update from upstream or merge a release tag.
---

# Upstream merge

`fork/main` merges upstream's release tags, never `develop`, and never rebases (D6, README rule 5). Read `fork/README.md`, D6, D15 and D23 first. Don't push until the user asks. Don't merge at all without a yes.

1. **Prepare.** `git status --short` is empty, on `fork/main`. `git fetch upstream --tags`. Move `develop` by fast-forward only: `git branch -f develop upstream/develop` when it is an ancestor.
2. **Target.** The newest tag: `git tag --list 'v*' --sort=-v:refname | head -3`. `openbite-v*` tags are ours. Tell the user the target and how many commits it brings.
3. **Read first, decide with the user.** Upstream's release notes, and `git diff --stat fork/main...$TARGET` for the seam files (`git grep -l '\[fork\]'`). Then:
   - `fork/tools/upstream-copies.sh $TARGET`: what upstream changed in the files the fork owns a copy of (D23). These never conflict, and are ported by hand.
   - SEAMS.md, "Carried upstream changes": what this release lets the fork drop (D15).
   - Each new feature or behaviour change that meets something the fork does gets a question to the user, with options and a recommendation. Record the answers in DECISIONS.md. Don't decide them yourself.
4. **Merge on a branch.** `git checkout -b fork/merge-$TARGET fork/main`, then `git merge --no-ff $TARGET`.
5. **Resolve.**
   - A seam in a changed upstream block: rebuild the seam on upstream's new code. Never restore the old upstream code.
   - `lib/l10n/intl_*.arb`: take upstream's side and run `fork/tools/l10n_overlay.py`. Check with `--check`.
   - `pubspec.yaml`: upstream's, with seam S2 and the fork's dependencies. Then `flutter pub get`, and `fork/tools/release-check.sh --accept-packages` only after reading what the lock changed.
   - A carried change upstream now has: take upstream's, and delete the row.
   - `fork/SEAMS.md` merges by union; fix rows for seams that moved.
6. **Silent drift.** A clean merge can still break the fork:
   - generated code: `dart run build_runner build --delete-conflicting-outputs`, `flutter gen-l10n`;
   - port what step 3 listed into the fork's copies, and move each copy's `sha` in SEAMS.md;
   - a new DBO or Hive field: `test/fork/upgrade/` must still open every release's data;
   - upstream's new tests that leave state behind: `fork/tools/test-fast.sh` resets what a file leaves, and needs any new kind added.
7. **Verify.** The `verify` skill at "before a merge", which runs `seam_check.py`, then the `seam-check` skill's read of the diff for the conflicted files. Then on the emulator (`SEED=1 FAKE_AI=true fork/tools/emulator.sh`): log a food, see it on Home and in the Diary, add a weight, open Trends. Anything the merge changed that the user would see is a decision too: ask.
8. **Land.** Merge into `fork/main` with the subject `Merge upstream release $TARGET into fork/main`. Its body names the conflicted files, the seams added, moved or removed, the copies ported, and what was not checked on a device. Upstream's released version shows on the next OpenBite release.
