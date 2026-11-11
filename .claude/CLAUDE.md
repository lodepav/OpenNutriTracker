# OpenBite (fork) instructions

This checkout is OpenBite, a fork of OpenNutriTracker. The root `CLAUDE.md` and `AGENTS.md` are
upstream's and still apply, except where this file says otherwise. The fork's trunk is
`fork/main`, not `main`.

The fork's five rules, in full in [fork/README.md](../fork/README.md#the-rules):

1. Upstream first: what any user would want goes upstream as a PR; nothing waits for it.
2. Add, don't edit: fork code lives in `lib/fork/`, `test/fork/`, `fork/`; an upstream file is
   edited only at a marked seam.
3. Logic is tested: a number the user acts on is a pure function with a test in `test/fork/`.
4. Upstream's checks stay green, unmodified.
5. Merge upstream, never rebase.

Decisions are numbered in [fork/DECISIONS.md](../fork/DECISIONS.md), seams in
[fork/SEAMS.md](../fork/SEAMS.md). Before a merge, run the `seam-check` and `verify` skills.

Strings in fork code are hard-coded English: no l10n keys.

`AGENTS.md`'s rule against AI co-author trailers and naming the assistant binds upstream pull
requests only. Commits on the fork's own branches keep the session's attribution lines.
