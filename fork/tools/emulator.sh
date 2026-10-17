#!/usr/bin/env bash
# Build the fork's debug APK, boot the Android 16 emulator, install and launch the app.
#
#   fork/tools/emulator.sh             # build + boot + install + launch
#   fork/tools/emulator.sh --no-build  # reinstall the last APK
#   SEED=1 fork/tools/emulator.sh      # build the demo-data entry point (lib/dev/main_dev.dart):
#                                      # wipes the profile, seeds a year of data, skips onboarding
#   WINDOW=1 ...                       # show the emulator window (headless by default)
#
# One-time setup this expects (user-local, no sudo):
#   Flutter 3.44.6  ~/flutter          (the version in .fvmrc)
#   JDK             ~/.jdks/openjdk-24.0.1 (needs javac and jlink; Java 25 is too new for Gradle 8.14)
#   Android SDK     ~/Android/Sdk with platform-tools, emulator, system-images;android-36
#   AVD             xperia1vi_api36 (1080x2340, 420 dpi), shared with openGym-Hevier
#   .env            copied from .env.example (placeholders build; the USDA/BLS search needs real values)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export JAVA_HOME="${JAVA_HOME:-$HOME/.jdks/openjdk-24.0.1}"
export PATH="$HOME/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
# Keep Gradle off the system JRE, which has no compiler.
export GRADLE_OPTS="-Dorg.gradle.java.installations.auto-detect=false -Dorg.gradle.java.installations.paths=$JAVA_HOME"
AVD="${AVD:-xperia1vi_api36}"
APP_ID="${APP_ID:-com.opennutritracker.ont.opennutritracker.develop}"
APK="$ROOT/build/app/outputs/flutter-apk/app-develop-debug.apk"

if [[ "${1:-}" != "--no-build" ]]; then
  cd "$ROOT"
  [[ -f .env ]] || cp .env.example .env
  [[ -f lib/core/utils/env.g.dart ]] || dart run build_runner build --delete-conflicting-outputs
  target=()
  [[ -n "${SEED:-}" ]] && target=(-t lib/dev/main_dev.dart)
  flutter build apk --flavor develop --debug "${target[@]}"
fi

if ! adb get-state >/dev/null 2>&1; then
  echo "booting $AVD..."
  setsid nohup "$ANDROID_HOME/emulator/emulator" -avd "$AVD" -no-audio -no-boot-anim \
    $([[ -n "${WINDOW:-}" ]] || echo -no-window) -gpu swiftshader_indirect >/tmp/ont-fork-emulator.log 2>&1 &
  adb wait-for-device
fi
adb shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done'

adb install -r "$APK"
adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "launched $APP_ID; drive it with: source tools/adb/adb-driver.sh"
