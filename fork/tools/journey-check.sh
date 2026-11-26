#!/usr/bin/env bash
# The journeys' "Check" mode (fork/ux/JOURNEYS.md): each scripted journey tapped through on the
# emulator by fork/tools/journey-check.mjs, its end state checked and compared with the baseline
# kept on this machine. Run it after an upstream merge.
#
#   ANDROID_SERIAL=emulator-5556 fork/tools/journey-check.sh     # every scripted journey (J1 to J6)
#   fork/tools/journey-check.sh J2                               # this one only
#   fork/tools/journey-check.sh --build                          # build the journey APK, boot, install, then check
#   fork/tools/journey-check.sh --accept J2                      # the differences are meant: keep this run as J2's baseline
#   fork/tools/journey-check.sh --make-ux-profile                # (re)make ~/.cache/openbite/ux-profile.tar
#   fork/tools/journey-check.sh --make-owner-profile <csv>       # (re)make ~/.cache/openbite/owner-profile.tar
#
# Before anything it saves the app's own data and puts it back on every exit, a failure included.
# Nothing on the device is ever deleted: the profile and the snapshot are untarred over the app's
# folders, and a file the snapshot did not hold is named and the run exits 2, the file left alone.
# Baselines: ~/.cache/openbite/journeys/<J>.json; a journey without one keeps its first clean run.
# Exit 0 when clean, 1 on a FAIL or DIFF, 2 when it could not run. It refuses a profile with a path
# off the device on (a real AI key, an Open Food Facts account, Health Connect, auto-backup).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"  # emu names the owner after the repo it runs in
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export JAVA_HOME="${JAVA_HOME:-$HOME/.jdks/openjdk-24.0.1}"
export PATH="$HOME/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
export GRADLE_OPTS="-Dorg.gradle.java.installations.auto-detect=false -Dorg.gradle.java.installations.paths=$JAVA_HOME"
ADB="${ADB:-$ANDROID_HOME/platform-tools/adb}"
APP="${APP_ID:-io.github.lodepav.openbite.develop}"
export ADB APP_ID="$APP"
export JOURNEY_APK="$ROOT/build/app/outputs/flutter-apk/app-develop-debug.apk"
CACHE="$HOME/.cache/openbite"
UX_PROFILE="${UX_PROFILE:-$CACHE/ux-profile.tar}"
OWNER_PROFILE="${OWNER_PROFILE:-$CACHE/owner-profile.tar}"
BASES="${BASES:-$CACHE/journeys}"
# The app's data folders; the engine's own copy of the assets is rebuilt by every install.
DIRS=(app_flutter shared_prefs files databases no_backup)
BUILD= MAKE= CSV= ACCEPT=() JOURNEYS=()
usage() { echo "usage: journey-check.sh [--build] [--accept <J>] [J1 .. J6] | --make-ux-profile | --make-owner-profile <csv>" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build) BUILD=1 ;;
    --accept) [[ ${2:-} == J[1-6] ]] || usage; ACCEPT+=("$2"); JOURNEYS+=("$2"); shift ;;
    --make-ux-profile) MAKE=ux ;;
    --make-owner-profile) [[ -n ${2:-} ]] || usage; MAKE=owner CSV="$2"; shift ;;
    J[1-6]) JOURNEYS+=("$1") ;;
    *) usage ;;
  esac
  shift
done
[[ ${#JOURNEYS[@]} -gt 0 ]] || JOURNEYS=(J1 J2 J3 J4 J5 J6)
profile_of() { case $1 in J1|J3|J5) echo "$UX_PROFILE" ;; *) echo "$OWNER_PROFILE" ;; esac; }
accepted() { [[ " ${ACCEPT[*]} " == *" $1 "* ]]; }
command -v node >/dev/null && node -e 'process.exit(typeof WebSocket === "function" ? 0 : 1)' \
  || { echo "journey check: needs node 22 or later (its global WebSocket)" >&2; exit 2; }

if [[ -z "$MAKE" ]]; then
  for j in "${JOURNEYS[@]}"; do
    p="$(profile_of "$j")"
    [[ -s "$p" ]] || { echo "journey check: no profile for $j at $p (fork/ux/JOURNEYS.md says how to make it)" >&2; exit 2; }
    tar -tf "$p" >/dev/null || { echo "journey check: $p is not a readable archive" >&2; exit 2; }
  done
elif [[ $MAKE == owner ]]; then
  # read only: it is copied into the app's cache on the device, never into the repo
  [[ -s "$CSV" ]] || { echo "journey check: no CSV at $CSV" >&2; exit 2; }
fi

# The files under the app's data folders, one path a line, sorted: from the device, or from a tar.
# Hive's lock files come and go with every open box and hold no data.
device_files() {
  "$ADB" exec-out "run-as $APP sh -c 'find ${DIRS[*]} -type f 2>/dev/null'" \
    | tr -d '\r' | grep -v '^app_flutter/flutter_assets/' | grep -v '\.lock$' | LC_ALL=C sort || true
}
tar_files() { tar -tf "$1" | grep -v '/$' | sed 's|^\./||' | grep -v '\.lock$' | LC_ALL=C sort || true; }
# Files on the device that the archive $1 does not hold, printed; 1 when there are any.
no_extras() {   # $1: archive, $2: what it is
  local extra left
  extra="$(LC_ALL=C comm -23 <(device_files) <(tar_files "$1"))"
  # Meal photos a journey saved point at entries the restore took back, and the engine rewrites its
  # res_timestamp on every install: named, left alone, not a stop.
  left="$(grep -E '^app_flutter/(meal_images/|res_timestamp-)' <<<"$extra" || true)"
  extra="$(grep -vE '^app_flutter/(meal_images/|res_timestamp-)' <<<"$extra" || true)"
  [[ -z "$left" ]] || echo "journey check: $(wc -l <<<"$left") leftover photo or engine file(s) not in $2, left alone" >&2
  [[ -z "$extra" ]] && return 0
  echo "journey check: these files on the device are not in $2 (nothing was removed):" >&2
  sed 's/^/  /' <<<"$extra" >&2
  return 1
}
untar_over() { "$ADB" exec-in run-as "$APP" tar -xf - < "$1"; }

# The shared emulators (~/.claude/bin/emu): --build boots a free one unless ANDROID_SERIAL names
# one, and stops the one it booted on every exit.
BOOTED= RUN= SNAP= RESTORED=
restore() {
  [[ -n "$SNAP" && -s "${SNAP:?}/app.tar" && -z "$RESTORED" ]] || return 0
  RESTORED=1
  "$ADB" shell am force-stop "$APP" || true
  if ! untar_over "${SNAP:?}/app.tar"; then
    echo "journey check: COULD NOT put the app's data back; it is saved at ${SNAP:?}/app.tar (fork/ux/JOURNEYS.md, restore)" >&2
    return 2
  fi
  if ! no_extras "${SNAP:?}/app.tar" "the snapshot taken before this run"; then
    echo "journey check: the app's data is back, beside the files above; the snapshot stays at ${SNAP:?}/app.tar" >&2
    return 2
  fi
  echo "journey check: the app's own data is back" >&2
}
cleanup() {
  local code=$? r=0
  restore || r=$?
  [[ -z "$BOOTED" ]] || "$HOME/.claude/bin/emu" down "$ANDROID_SERIAL" >/dev/null 2>&1 || true
  [[ $r -eq 0 ]] || exit "$r"
  exit "$code"
}
trap cleanup EXIT
if [[ -z ${ANDROID_SERIAL:-} ]]; then
  [[ -n "$BUILD" ]] || { echo "journey check: set ANDROID_SERIAL to an emulator this repo booted (~/.claude/bin/emu list), or use --build" >&2; exit 2; }
  ANDROID_SERIAL="$("$HOME/.claude/bin/emu" up)" || { echo "journey check: no emulator could be booted (~/.claude/bin/emu list)" >&2; exit 2; }
  BOOTED=1
elif ! "$HOME/.claude/bin/emu" mine "$ANDROID_SERIAL"; then
  echo "journey check: $ANDROID_SERIAL was not booted from this repo (~/.claude/bin/emu list)" >&2; exit 2
fi
export ANDROID_SERIAL
"$ADB" wait-for-device
"$ADB" shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done'

RUN="$(mktemp -d -t openbite-journeys-XXXXXX)"
if [[ -n "$BUILD" ]]; then
  [[ -f .env ]] || cp .env.example .env
  [[ -f lib/core/utils/env.g.dart ]] || dart run build_runner build --delete-conflicting-outputs
  fork/tools/heavy.sh flutter build apk --flavor develop --debug -t lib/fork/dev/main_journey.dart \
      --dart-define=FORK_FAKE_AI=true >"${RUN:?}/build.log" 2>&1 \
    || { echo "journey check: the journey build failed, see ${RUN:?}/build.log" >&2; exit 2; }
  (cd android && ../fork/tools/heavy.sh ./gradlew --stop >/dev/null 2>&1) || true
  # -r keeps the app's data: the snapshot below is of the user's own
  "$ADB" install -r "$JOURNEY_APK" >/dev/null || { echo "journey check: could not install $JOURNEY_APK" >&2; exit 2; }
fi
"$ADB" shell pm path "$APP" >/dev/null 2>&1 || { echo "journey check: $APP is not installed (use --build)" >&2; exit 2; }

# The app's own data first (JOURNEYS.md, "Snapshot first"); kept outside RUN's work files.
SNAP="$(mktemp -d -t openbite-journeys-snap-XXXXXX)"
snapshot() {   # $1: the archive to write
  local have
  have="$("$ADB" exec-out "run-as $APP sh -c 'for d in ${DIRS[*]}; do [ -e \$d ] && echo \$d; done'" | tr -d '\r' | tr '\n' ' ')"
  [[ -n "$have" ]] || { echo "journey check: the app has no data folders to save" >&2; return 1; }
  "$ADB" exec-out "run-as $APP tar -cf - --exclude=app_flutter/flutter_assets $have 2>/dev/null" > "$1"
  tar -tf "$1" >/dev/null 2>&1
}
"$ADB" shell am force-stop "$APP"
snapshot "${SNAP:?}/app.tar" || { echo "journey check: the snapshot of the app is not a readable archive (is the debug app installed?)" >&2; SNAP=""; exit 2; }

# The core boxes' key sits in this AVD's Keystore: a profile opens only on the install it was made on.
avd_name() { "$ADB" emu avd name 2>/dev/null | head -1 | tr -d '\r'; }
load_profile() {   # $1: the archive
  if [[ -s "$1.avd" && "$(cat "$1.avd")" != "$(avd_name)" ]]; then
    echo "journey check: $1 was made on AVD $(cat "$1.avd"), this is $(avd_name): boot that one (ANDROID_SERIAL) or remake the profile" >&2; exit 2
  fi
  "$ADB" shell am force-stop "$APP"
  untar_over "$1" || { echo "journey check: could not put $1 into $APP" >&2; exit 2; }
  # files the profile does not hold would run with it: the user's, or a box made since
  no_extras "$1" "the profile $1" || exit 2
}
launch() {
  "$ADB" shell monkey -p "$APP" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 8
}
restart() { "$ADB" shell am force-stop "$APP"; launch; }
keep_profile() {   # $1: where
  sleep 3   # Hive's writes
  "$ADB" shell am force-stop "$APP"
  snapshot "${RUN:?}/profile.tar" || { echo "journey check: the profile is not a readable archive: not kept" >&2; exit 2; }
  mkdir -p "$CACHE"
  cp "${RUN:?}/profile.tar" "$1"
  avd_name > "$1.avd"
  echo "journey check: profile kept at $1 (AVD $(cat "$1.avd"))"
}

if [[ $MAKE == ux ]]; then
  # The demo data (DemoSeedOptions.dev) over the app as it is, then a restart past onboarding.
  launch
  node fork/tools/journey-check.mjs request '{"cmd":"seedDemo"}' || exit 2
  restart
  node fork/tools/journey-check.mjs network || exit 2
  node fork/tools/journey-check.mjs request '{"cmd":"openBoxes"}' || exit 2
  keep_profile "$UX_PROFILE"
  exit 0
fi
if [[ $MAKE == owner ]]; then
  # A new, empty profile, made active and past onboarding (the app's own use cases), restarted
  # into; then the owner's MacroFactor export through Settings → Data → Import history, and the
  # weigh-ins from the fake Health Connect. The CSV goes to the app's cache: the picker hands the
  # app that path. The app's other profiles stay in the archive, not active.
  "$ADB" exec-in "run-as $APP sh -c 'mkdir -p cache/journey-import && cat > cache/journey-import/owner.csv'" < "$CSV" \
    || { echo "journey check: could not copy $CSV into the app's cache" >&2; exit 2; }
  launch
  node fork/tools/journey-check.mjs request '{"cmd":"ownerProfile","name":"Owner"}' || exit 2
  sleep 2   # Hive's writes
  restart
  node fork/tools/journey-check.mjs import "/data/user/0/$APP/cache/journey-import/owner.csv" || exit 2
  node fork/tools/journey-check.mjs request '{"cmd":"weightImportOn"}' || exit 2
  node fork/tools/journey-check.mjs network || exit 2
  node fork/tools/journey-check.mjs request '{"cmd":"openBoxes"}' || exit 2
  keep_profile "$OWNER_PROFILE"
  exit 0
fi

mkdir -p "$BASES"
status=0
for j in "${JOURNEYS[@]}"; do
  load_profile "$(profile_of "$j")"
  launch
  base="$BASES/$j.json" out="${RUN:?}/$j.json"
  args=(run "$j" "$out")
  accepted "$j" || [[ ! -s "$base" ]] || args+=(--base "$base")
  code=0
  node fork/tools/journey-check.mjs "${args[@]}" || code=$?
  # where the app was when a step failed, before the restore takes it away
  [[ $code -eq 0 ]] || { "$ADB" exec-out screencap -p > "${RUN:?}/$j.png" && echo "journey check: $j's last screen: ${RUN:?}/$j.png" >&2; } || true
  [[ $code -ne 2 ]] || { echo "journey check: $j could not run" >&2; status=2; continue; }
  if accepted "$j" || [[ ! -s "$base" ]]; then
    # A first run keeps its facts only when every check passed; --accept keeps them anyway.
    if accepted "$j" || [[ $code -eq 0 ]]; then
      node -e 'const fs = require("fs"); fs.writeFileSync(process.argv[2], JSON.stringify(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).facts, null, 2) + "\n")' "$out" "$base"
      echo "journey check: $j's baseline kept at $base"
    fi
  fi
  [[ $code -eq 0 || $status -eq 2 ]] || status=1
done
[[ $status -ne 1 ]] || echo "journey check: a journey failed or differs. Meant? fork/tools/journey-check.sh --accept <J>" >&2
exit $status
