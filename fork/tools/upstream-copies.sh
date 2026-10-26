#!/usr/bin/env bash
# What upstream changed in the files the fork owns a copy of (D23), since each
# copy was taken. Usage: fork/tools/upstream-copies.sh [ref] [--patch]
# ref: the upstream release being merged (default upstream/main).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ref=${1:-upstream/main}
mode=--stat
[[ ${2:-} == --patch ]] && mode=-p
# Rows of SEAMS.md's "Fork-owned copies" table: | `copy` | `upstream file` | `sha` | seam |
sed -n '/^## Fork-owned copies/,/^## /p' fork/SEAMS.md |
  { grep -E '^\| `lib/fork/' || true; } |
  while IFS='|' read -r _ copy file sha _; do
    copy=$(tr -d ' `' <<<"$copy")
    file=$(tr -d ' `' <<<"$file")
    sha=$(tr -d ' `' <<<"$sha")
    changes=$(git diff "$mode" "$sha" "$ref" -- "$file")
    if [[ -z $changes ]]; then
      echo "up to date: $copy ($file)"
    else
      echo "== port into $copy: upstream changed $file ($sha..$ref)"
      echo "$changes"
    fi
  done
