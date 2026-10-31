---
name: seam-check
description: Check that the fork edits upstream files only at marked [fork] seams listed in fork/SEAMS.md. Use before committing a change outside lib/fork, test/fork and fork/, and after an upstream merge.
---

# Seam check

Fork rule 2 (fork/README.md): an upstream file is edited only at a seam, a short hook between `[fork]` markers, with a row in `fork/SEAMS.md`. A screen the fork mostly rewrites is copied whole into `lib/fork/` instead (D23).

1. Run `fork/tools/seam_check.py` (`verify.sh` runs it too). It finds:
   - a seam id on two rows. `merge=union` keeps both sides of a SEAMS.md merge, so two branches can take the same next number: renumber the later one, in its row and its markers;
   - a `[fork] S<n>` marker with no row;
   - an upstream file changed from upstream with no marker and no row.
2. The script works file by file, so read the diff of each upstream file this change touches:
   ```bash
   git diff --name-only HEAD -- . ':!fork' ':!lib/fork' ':!test/fork' ':!lib/generated'   # uncommitted
   git diff $(git merge-base HEAD upstream/main) HEAD -- <file>
   ```
   Every added or changed line sits between `[fork]` markers, except a file with a reason on its row: the ARBs (S31, by `fork/tools/l10n_overlay.py`), the `justfile`, and "Carried upstream changes", which have no markers until upstream merges them.
3. Logic that computes a number the user acts on doesn't belong in a seam: move it to a pure function in `lib/fork/` with a test (rule 3).

Fix a finding by moving the edit behind a marker or into a fork file, and adding its row in the same commit. Formatting alone is not a seam: restore the file to upstream's, or the next release conflicts on it for nothing.

Report a table: file · seam id · OK / undeclared lines / missing row.
