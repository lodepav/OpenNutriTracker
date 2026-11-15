#!/usr/bin/env bash
# What upstream has coming, ahead of the release merge: the release tags, a dry merge into
# fork/main, the seam files upstream changed and the fork-owned copies to port. Prints only.
# Usage: fork/tools/upstream-coming.sh [ref] [--no-fetch]
# ref: default upstream/develop. --no-fetch skips `git fetch upstream --tags`.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ref=upstream/develop
fetch=yes
for arg in "$@"; do
  case $arg in
    --no-fetch) fetch= ;;
    -*) echo "usage: fork/tools/upstream-coming.sh [ref] [--no-fetch]" >&2; exit 2 ;;
    *) ref=$arg ;;
  esac
done
if [[ -n $fetch ]]; then git fetch --quiet upstream --tags; fi

# v* tags are upstream's releases, openbite-v* are the fork's.
merged=$(git tag --merged fork/main --list 'v*' --sort=-v:refname | sed -n 1p)
newest=$(git tag --list 'v*' --sort=-v:refname | sed -n 1p)
echo "Upstream coming: $ref against fork/main."
echo "A hint only: develop is not what gets released, the release tag is."
echo "Merged release: $merged. Newest release: $newest. $ref is $(git rev-list --count "$merged..$ref") commits ahead of $merged."

seam_files=$(git grep -l '\[fork\]' fork/main -- . ':!fork' | sed 's|^fork/main:||' | sort -u)
# Rows of SEAMS.md's "Carried upstream changes" table start with a branch in backticks.
carried=$(sed -n '/^## Carried upstream changes/,/^## /p' fork/SEAMS.md | { grep -E '^\| `' || true; })

echo
echo "== Dry merge of $ref into fork/main (the tree is not touched)"
status=0
out=$(git merge-tree --write-tree --name-only fork/main "$ref") || status=$?
if ((status > 1)); then echo "$out" >&2; exit "$status"; fi
# Line 1 is the tree; the conflicted files follow, up to the first blank line.
conflicts=$(sed -n '2,/^$/p' <<<"$out" | sed '/^$/d')
if [[ -z $conflicts ]]; then
  echo "no conflicts"
else
  while read -r f; do
    kind=""
    if grep -qxF "$f" <<<"$seam_files"; then kind=" (seam file, has [fork] markers)"; fi
    if grep -qF "\`$f\`" <<<"$carried"; then kind="$kind (named on a Carried upstream changes row)"; fi
    echo "conflict: $f$kind"
  done <<<"$conflicts"
fi

echo
echo "== Seam files upstream changed since $merged"
touched=$(comm -12 <(git diff --name-only "$merged..$ref" | sort -u) <(echo "$seam_files"))
if [[ -z $touched ]]; then
  echo "none"
else
  while read -r f; do
    if grep -qxF "$f" <<<"$conflicts"; then echo "$f (conflicts)"; else echo "$f"; fi
  done <<<"$touched"
fi

echo
echo "== Fork-owned copies to port (fork/tools/upstream-copies.sh $ref)"
copies=$(fork/tools/upstream-copies.sh "$ref" | { grep -v '^up to date: ' || true; })
if [[ -z $copies ]]; then echo "none"; else echo "$copies"; fi

count() { if [[ -z $1 ]]; then echo 0; else wc -l <<<"$1"; fi; }
echo
echo "Summary: $(count "$conflicts") conflicted, $(count "$touched") seam files touched, $(grep -c '^== port into' <<<"$copies" || true) copies to port."
