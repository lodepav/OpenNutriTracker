---
name: upstream-merge
description: Merge a new upstream OpenNutriTracker release into fork/main, resolve conflicts by the fork's rules, and check for silent drift; or take one of the fork's own PRs once it lands on upstream's develop. Use when asked to sync, update from upstream, merge a release tag, or when a fork PR was merged upstream.
---

# Upstream merge

`fork/main` merges upstream's release tags, never `develop`, and never rebases (D6, README rule 5). Read `fork/README.md`, D6, D15 and D23 first. Don't push until the user asks. Don't merge at all without a yes.

1. **Prepare.** `git status --short` is empty, on `fork/main`. `git fetch upstream --tags`. Move `develop` by fast-forward only: `git branch -f develop upstream/develop` when it is an ancestor.
2. **Target.** The newest tag: `git tag --list 'v*' --sort=-v:refname | head -3`. `openbite-v*` tags are ours. Tell the user the target and how many commits it brings. Before a tag lands, `fork/tools/upstream-coming.sh` previews develop: the dry merge's conflicts, the seam files touched and the copies to port (a hint, not the release).
3. **Read first, decide with the user.** Upstream's release notes, and `git diff --stat fork/main...$TARGET` for the seam files (`git grep -l '\[fork\]'`). Then:
   - `fork/tools/upstream-copies.sh $TARGET`: what upstream changed in the files the fork owns a copy of (D23). These never conflict, and are ported by hand.
   - SEAMS.md, "Carried upstream changes": what this release lets the fork drop (D15).
   - `fork/tools/upstream_status.py`: which of the fork's upstream PRs are merged and in $TARGET, and which seams, carried rows, branches and worktrees that makes ready to drop.
   - Each new feature or behaviour change that meets something the fork does gets a question to the user, with options and a recommendation. Record the answers in DECISIONS.md. Don't decide them yourself.
   - An answer of the form "upstream's feature applies only where X" covers every place the feature is used, not only the one a conflict or a seam shows. Take every name the feature adds (setting, function, use case) from `git diff fork/main...$TARGET`, then `git grep -n <name> $TARGET` for each, over the whole tree: `android/` draws numbers too. List each call site in the decision as `file:line`. Step 6 gates each one.
4. **Merge on a branch.** `git checkout -b fork/merge-$TARGET fork/main`, then `git merge --no-ff $TARGET`.
5. **Resolve.**
   - A seam in a changed upstream block: rebuild the seam on upstream's new code. Never restore the old upstream code.
   - `lib/l10n/intl_*.arb`: take upstream's side and run `fork/tools/l10n_overlay.py`. Check with `--check`.
   - `pubspec.yaml`: upstream's, with seam S2 and the fork's dependencies. Then `flutter pub get`, and `fork/tools/release-check.sh --accept-packages` only after reading what the lock changed.
   - A carried change upstream now has: take upstream's, and delete the row. `fork/tools/upstream_status.py` lists them, and the local branches and worktrees to delete afterwards (ask before deleting).
   - `fork/SEAMS.md` merges by union; fix rows for seams that moved.
6. **Silent drift.** A clean merge can still break the fork:
   - generated code: `dart run build_runner build --delete-conflicting-outputs`, `flutter gen-l10n`;
   - port what step 3 listed into the fork's copies, and move each copy's `sha` in SEAMS.md;
   - `flutter test -j 1 test/fork/open/open_snapshot_test.dart`, before touching its fixture: each `path: before → after` line is something the user sees that the merge changed. A line no decision in DECISIONS.md explains stops the merge: on a line a decision rules out, fix the fork; on any other, ask the user;
   - a feature a decision limits: grep its names again in the merged tree (a ported copy can bring a call site), gate every call site, then make the snapshot able to see the limit: the data in `test/fork/open/open_fixture.dart`, the settings variants and what is read in `open_snapshot.dart`. Run it again: lines only where the decision allows the feature;
   - when every remaining line is explained, `OPEN_SNAPSHOT_WRITE=1` in front rewrites the whole kept file. Name the accepted lines in the body of the merge into `fork/main`;
   - a new DBO or Hive field: `test/fork/upgrade/` must still open every release's data;
   - upstream's new tests that leave state behind: `fork/tools/test-fast.sh` resets what a file leaves, and needs any new kind added.
7. **Verify.** The `verify` skill at "before a merge", which runs `seam_check.py`, then the `seam-check` skill's read of the diff for the conflicted files. Then on the emulator (`SEED=1 FAKE_AI=true fork/tools/emulator.sh`): log a food, see it on Home and in the Diary, add a weight, open Trends. Anything the merge changed that the user would see is a decision too: ask.
8. **Land.** Merge into `fork/main` with the subject `Merge upstream release $TARGET into fork/main`. Its body names the conflicted files, the seams added, moved or removed, the copies ported, and what was not checked on a device. Upstream's released version shows on the next OpenBite release.

## When one of the fork's PRs lands on develop

Don't leave it for the release merge. Take upstream's commit now, one PR at a time: at the release, a file the fork then holds byte-identical to upstream in the changed block merges without a conflict, and a block where another seam remains conflicts again, but only on that seam's own lines. (Replayed for #1494: 10 of its 15 conflicted files left the 2.7.0 conflict list.) Expect about an hour of care per PR. The merge into `fork/main` needs the user's yes, as any does.

1. **Find it.** `git fetch upstream`, then `fork/tools/upstream_status.py`: a PR that reads merged and in develop, but not in the newest tag. Its commit: `gh pr view <n> -R simonoppowa/OpenNutriTracker --json mergeCommit -q .mergeCommit.oid`.
2. **Take it.** `git checkout -b fork/take-pr-<n> fork/main`, then `git -c rerere.enabled=false cherry-pick -x <commit>` (`-m 1` if it has two parents; keep its subject). rerere is off so that these resolutions are not replayed into the release merge. It conflicts where a seam holds the same change, where another seam sits in the same block, and in `lib/l10n/intl_en.arb`.
3. **Resolve to upstream's bytes.**
   - In each conflicted block take upstream's lines. Then remove every marker of the upstreamed seam from the file, also outside the conflict hunks: the closing `// [/fork]` usually sits below the hunk. A block that merged without a conflict can now hold the change twice (the fork's `tooltip:` and upstream's): read it.
   - Another seam in the same block is rebuilt on upstream's lines. Where the upstreamed seam did more than the PR, the rest goes back as a smaller marked seam.
   - `lib/l10n/intl_en.arb`: keep the fork's side and add only the keys this PR adds. Don't take upstream's side: it holds keys of commits not taken. Delete from `fork/l10n/intl_en_overlay.json`, and from the end of the arb, every key the PR now provides. `fork/tools/l10n_overlay.py --check` exits 0.
   - A file the fork owns a copy of (SEAMS.md, "Fork-owned copies"): check the copy has the change; leave its `sha` for the release.
   - Read `git diff <commit> -- <file>` for each file the PR touched. Every line left is a marked seam of another number, the smaller seam you put back, or a develop change the fork has not taken (it shows reversed).
4. **Records, in the same commit as the cherry-pick.**
   - `fork/SEAMS.md`, each seam row the PR covered: take out the files that hold no marker of that seam any more, and say which part is upstream's since #<n>. Delete a row only when nothing is left.
   - A row under "Carried upstream changes": Branch, the PR's branch; What it changes, `#<n>`, upstream's commit, what it does, and "Files:" with every file the PR touched that now has no marker (`seam_check.py` fails on a changed file no row names); Upstream, "in develop, comes with the next release".
   - A fork marker in an upstream test that only adapted the test to the seam goes too. Upstream's new tests now run against the fork: where one fails on fork behaviour (sentence case, a fork screen), add a marked one-line seam and its row.
5. **Check and land.** `flutter gen-l10n` when the PR adds strings (`lib/generated` is not tracked), then `fork/tools/seam_check.py`. `flutter test -j 1 test/fork/open/open_snapshot_test.dart` prints no line: upstream's version of the fork's own change shows the user the same thing, and a line is a difference to show the user before going on. Then the `verify` skill at "before a merge", and `git merge --no-ff` with the subject `Merge fork/take-pr-<n>: upstream's version of <what it does> (#<n>)`.
6. **At the release.** The files held identical merge clean. Resolve the rest as in step 5 of the release merge, then delete the carried row.
