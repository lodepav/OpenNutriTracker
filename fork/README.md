# OpenNutriTracker fork — notes

A fork of [OpenNutriTracker](https://github.com/simonoppowa/OpenNutriTracker) (ONT) that adds
the [MacroFactor](https://macrofactor.com/) features users value most: adaptive expenditure,
weekly coaching, fast AI logging with your own model. It stays a server-free Android app and
stays easy to update from upstream.

Modelled on the openGym-Hevier fork (`~/IdeaProjects/openGym-Hevier/hevier/`).

Everything that belongs only to the fork lives in this `fork/` folder or in `lib/fork/` (and
`test/fork/`). Upstream never touches them, so they never conflict.

| File | What it is |
|---|---|
| [DECISIONS.md](DECISIONS.md) | Agreed decisions, numbered D1, D2, … They override PLAN.md where the two differ. Change a decision here first, with the date, before changing the code. |
| [PLAN.md](PLAN.md) | The backlog, open questions and risks. The finished phases are in [archive/PLAN-phases.md](archive/PLAN-phases.md). |
| [FEATURES.md](FEATURES.md) | The fork's features, each marked fork only, an upstream candidate, or already sent upstream. |
| [SEAMS.md](SEAMS.md) | Every place the fork edits an upstream file. Keep it current: it is what makes conflicts predictable. |
| [tools/emulator.sh](tools/emulator.sh) | Builds the debug APK, boots the Android 16 emulator, installs and launches it. Drive the app with upstream's `tools/adb/adb-driver.sh`. |
| [tools/upstream-coming.sh](tools/upstream-coming.sh) | What upstream has coming before merge day: a dry merge of `upstream/develop` (or a ref) into `fork/main`, the seam files it changed and the copies to port. A hint: develop is not the release. Prints only. |
| [tools/upstream_status.py](tools/upstream_status.py) | The state of the fork's upstream PRs, whether a merged one is in develop and the newest release, and what is ready to drop. Prints only. Test: `python3 test/fork/tools/upstream_status_test.py`. |

## The rules

1. **Upstream first.** A feature that any ONT user would want goes to upstream as a pull
   request from a branch off `develop`. The fork carries it only until upstream merges it.
   Every merged PR is one less divergence to carry. Nothing waits for upstream, though (D15):
   the fork carries upstream's work before its release and swaps to the release when it lands,
   takes one of its own PRs as soon as it lands on `develop`, and reviews code from other forks
   before porting it.
2. **Add, don't edit.** Fork-only behaviour goes in new files under `lib/fork/`. An upstream
   file is edited only at a *seam*: a short hook between `[fork]` markers, listed in
   [SEAMS.md](SEAMS.md).
   A screen the fork mostly rewrites is copied whole into `lib/fork/` instead, wired in with
   one seam, and the upstream file is restored (D23). Upstream's later changes to it are
   ported by hand at each release merge: `fork/tools/upstream-copies.sh <tag>` lists them.
3. **Logic is tested.** Anything that computes a number the user acts on (expenditure, targets,
   trend weight) is a pure Dart function in `lib/fork/` with a unit test in `test/fork/`.
4. **Upstream's checks stay green, unmodified.** Upstream's tests and analyze pass on the fork
   trunk, checked by `fork/tools/verify.sh` (below). Nothing runs `just ci`: its format step
   fails on the fork. A red upstream test means the fork changed behaviour it shouldn't have:
   fix the fork, never the test. Where a seam changes behaviour on purpose, the upstream test
   is skipped between markers and the fork's version lives in `test/fork/`; fork tests never
   go into upstream test files (`test/fork/cases/` mirrors upstream's paths for the ones
   that share an upstream file's harness).
   Before a merge, `fork/tools/verify.sh` runs the seams, analyze and the whole suite bundled,
   in about 2.5 minutes; a push to `fork/main` runs it too (`fork/hooks/`, turned on once a
   clone with `fork/tools/install-hooks.sh`). `verify.sh --strict` (plain
   `flutter test`, a file a process) runs in `.github/workflows/fork-checks.yml` on every push
   to `fork/main`; a release needs that run green for its commit. `fork/tools/release-apk.sh`
   is local on purpose (`.git/info/exclude`), so it exists only on the release machine, with a
   copy in `~/.local/share/openbite/`.
   That workflow also runs the release gate's Trivy scan, so a known vulnerability shows up with
   the next push. Dependabot would read upstream's `main`, not the fork's lockfiles.
5. **Merge upstream, never rebase.** `fork/main` merges each upstream release tag (D6); `develop` mirrors `upstream/develop` for upstream PRs.

## A bad release

Version codes only rise, so a phone cannot go back to an older release. To stop the damage,
mark the last good release as latest:
`gh release edit openbite-v<good> --latest -R lodepav/OpenNutriTracker`. The app's updater (`lib/fork/update/updater.dart`) reads only the
release GitHub marks latest (`/releases/latest`) and offers it when its version is higher than
the installed one, so phones still on an older version stop being offered the bad one. Phones
that already have it keep it. Then release a fix: it gets a higher version, and the updater
offers it to everyone.
