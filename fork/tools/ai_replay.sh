#!/usr/bin/env bash
# Move replay requests and answers between the emulator and a host folder
# (fork/eval/REPLAY.md). Needs a debug build, for run-as.
#
#   fork/tools/ai_replay.sh pull <dir>   # the app's requests into <dir>/requests
#   fork/tools/ai_replay.sh push <dir>   # <dir>/answers into the app
set -euo pipefail

APP_ID="${APP_ID:-io.github.lodepav.openbite.develop}"
export PATH="${ANDROID_HOME:-$HOME/Android/Sdk}/platform-tools:$PATH"
mode="${1:?pull or push}"
dir="${2:?host folder}"
mkdir -p "$dir"

case "$mode" in
  pull)
    adb exec-out run-as "$APP_ID" tar c -C files/ai-replay requests | tar x -C "$dir"
    ls "$dir/requests" | grep -c '\.json$' | xargs echo "requests:"
    ;;
  push)
    tar c -C "$dir" answers | adb exec-out run-as "$APP_ID" sh -c 'mkdir -p files/ai-replay && tar x -C files/ai-replay'
    echo "answers pushed: $(ls "$dir/answers" | wc -l)"
    ;;
  *) echo "pull or push" >&2; exit 1 ;;
esac
