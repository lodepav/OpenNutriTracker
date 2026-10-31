#!/usr/bin/env bash
# The check that guards fork/main: no conflict marker, the seams, analyze and the
# whole test suite. The pre-push hook and the release run this; see the verify skill.
#
#   fork/tools/verify.sh            # bundled suite, about 2.5 minutes
#   fork/tools/verify.sh --strict   # a process a file, as upstream's CI: for a release
#
# A pass on a clean tree is remembered by commit, so pushing what was just checked
# doesn't check it again, nor does a later commit that only touches docs or fork/VERSION.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="$HOME/flutter/bin:$PATH"
cd "$ROOT"
STAMP="$(git rev-parse --path-format=absolute --git-common-dir)/fork-verified"
strict=
[[ "${1:-}" == --strict ]] && strict=1

clean() { [[ -z "$(git status --porcelain)" ]]; }

# Whether only docs changed since the last pass (never true for --strict).
already_checked() {
  [[ -z "$strict" ]] && clean && [[ -f "$STAMP" ]] || return 1
  local last
  last="$(cat "$STAMP")"
  git merge-base --is-ancestor "$last" HEAD 2>/dev/null || return 1
  ! git diff --name-only "$last" HEAD | grep -qvE '\.md$|^fork/VERSION$'
}

# git doesn't carry core.hooksPath over a clone: without it nothing guards fork/main.
if [[ -z "${CI:-}" && "$(git config core.hooksPath)" != fork/hooks ]]; then
  echo "verify: warning: the hooks are off in this clone; run fork/tools/install-hooks.sh" >&2
fi

if already_checked; then
  echo "verify: passed at $(git rev-parse --short "$(cat "$STAMP")"), and only docs changed since"
  exit 0
fi

if git grep -nE '^(<{7}|>{7}|\|{7})( |$)' -- . ':!test/fixture' ':!*.md'; then
  echo "verify: a conflict marker was left behind" >&2
  exit 1
fi
if git grep -nE '^(<{7}|>{7})( |$)' -- 'fork/*.md' '*.md'; then
  echo "verify: a conflict marker was left behind" >&2
  exit 1
fi
python3 fork/tools/seam_check.py
fork/tools/sibling_check.sh
flutter analyze lib test
if [[ -n "$strict" ]]; then
  flutter gen-l10n
  fork/tools/heavy.sh flutter test
else
  fork/tools/test-fast.sh
fi

if clean; then git rev-parse HEAD > "$STAMP"; fi
echo "verify: passed"
