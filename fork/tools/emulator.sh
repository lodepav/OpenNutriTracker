#!/usr/bin/env bash
# Build the fork's debug APK, boot the Android 16 emulator, install and launch the app.
#
#   fork/tools/emulator.sh             # build + boot + install + launch
#   fork/tools/emulator.sh --no-build  # reinstall the last APK
#   SEED=1 fork/tools/emulator.sh      # build the demo-data entry point (lib/dev/main_dev.dart):
#                                      # wipes the profile, seeds a year of data, skips onboarding
#   ANDROID_SERIAL=emulator-5558 ...   # use that running emulator (default: boot a free one)
#   AVD=xperia1vi_api36 ...            # boot this AVD instead of a free light one
#   FAKE_AI=true|replay ...            # no model key: canned answers, or replayed ones (fork/eval/REPLAY.md)
#
# One-time setup this expects (user-local, no sudo):
#   Flutter 3.44.6  ~/flutter          (the version in .fvmrc)
#   JDK             ~/.jdks/openjdk-24.0.1 (needs javac and jlink; Java 25 is too new for Gradle 8.14)
#   Android SDK     ~/Android/Sdk with platform-tools, emulator, system-images;android-36
#   AVDs            booted headless by ~/.claude/bin/emu, shared with openGym-Hevier: the light
#                   openbite_lite, _lite2, _lite3 (2 GB) and xperia1vi_api36 (3 GB), all 1080x2340, 420 dpi
#   .env            copied from .env.example (placeholders build; the USDA/BLS search needs real values)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export JAVA_HOME="${JAVA_HOME:-$HOME/.jdks/openjdk-24.0.1}"
export PATH="$HOME/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
# Keep Gradle off the system JRE, which has no compiler.
export GRADLE_OPTS="-Dorg.gradle.java.installations.auto-detect=false -Dorg.gradle.java.installations.paths=$JAVA_HOME"
APP_ID="${APP_ID:-io.github.lodepav.openbite.develop}"
APK="$ROOT/build/app/outputs/flutter-apk/app-develop-debug.apk"

cd "$ROOT"  # the build runs here, and emu names the owner after the repo it runs in
if [[ "${1:-}" != "--no-build" ]]; then
  [[ -f .env ]] || cp .env.example .env
  [[ -f lib/core/utils/env.g.dart ]] || dart run build_runner build --delete-conflicting-outputs
  target=()
  [[ -n "${SEED:-}" ]] && target=(-t lib/dev/main_dev.dart)
  [[ -n "${FAKE_AI:-}" ]] && target+=(--dart-define=FORK_FAKE_AI="$FAKE_AI")
  fork/tools/heavy.sh flutter build apk --flavor develop --debug "${target[@]}"
  # An idle daemon holds over a gigabyte that the emulators need. Under the lock:
  # --stop ends every daemon of this Gradle version, a running build's too.
  (cd android && ../fork/tools/heavy.sh ./gradlew --stop >/dev/null)
fi

# Every adb call below goes to this one device, never another session's emulator.
if [[ -z "${ANDROID_SERIAL:-}" ]]; then
  ANDROID_SERIAL="$("$HOME/.claude/bin/emu" up ${AVD:-})"
elif ! "$HOME/.claude/bin/emu" mine "$ANDROID_SERIAL"; then
  echo "emulator.sh: $ANDROID_SERIAL was not booted from this repo (emu list)" >&2; exit 1
fi
export ANDROID_SERIAL
adb shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done'

adb install -r "$APK"
adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "launched $APP_ID on $ANDROID_SERIAL; drive it with: export ANDROID_SERIAL=$ANDROID_SERIAL; source fork/tools/ux-drive.sh"
