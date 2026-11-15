#!/usr/bin/env bash
# Prints fork/DECISIONS-INDEX.md: each decision's number and bold lead sentence. After
# openGym-Hevier's hevier/tools/decision-index.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
cat <<'HEAD'
# Decision index

One line per decision in [DECISIONS.md](DECISIONS.md), its bold lead sentence. Read the full row
there before changing anything a line touches. After adding or rewording a decision, regenerate:
`fork/tools/decision-index.sh > fork/DECISIONS-INDEX.md`.

HEAD
grep -oE '^\| D[0-9]+ \| \*\*[^*]+\*\*' DECISIONS.md | sed -E 's/^\| (D[0-9]+) \| \*\*(.*)\*\*$/- **\1** \2/'
