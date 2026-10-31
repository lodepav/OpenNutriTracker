#!/usr/bin/env bash
# Once a clone: git runs fork/hooks (pre-push: verify.sh; commit-msg: merge subjects).
# A branch without fork/hooks (an upstream PR's, off develop) simply has no hooks.
set -euo pipefail
git config core.hooksPath fork/hooks
echo "hooks on: $(git config core.hooksPath)"
