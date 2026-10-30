# Helpers for driving the app on the emulator by what is on screen, for UX
# reviews. Source it: `source fork/tools/ux-drive.sh`. Builds on
# tools/adb/adb-driver.sh (tap_id, id_exists, list_ids, dump_ui, press_back).
#
#   find_sub TEXT         centre "x y" of the first node whose text or
#                         content-desc contains TEXT, or nothing
#   tap_sub TEXT          tap it; fails when it is not on screen
#   scroll_to TEXT [N]    swipe up until TEXT is on screen, at most N times
#   scroll_up [N]         swipe down N times, back towards the top
#   settle [SECONDS]      wait until the app stops drawing, at most 3 s
#   shot NAME             settle, then a screenshot into $UX/NAME.png
#   look NAME             shot and labels from a new dump, side by side
#   labels [FILTER]       every text / content-desc on screen, one a line
#   nodes                 clickable nodes: bounds, size in dp, text, desc
#   font_scale X          system font scale (1.0 normal, 2.0 for A6)
#   night yes|no          dark theme on or off
#
# A dump takes about 3 s, so helpers reuse the last one, across calls, until
# something could have changed the screen: any adb command that isn't only a
# read, a sleep, or $UX_DUMP_MAX_AGE seconds (default 30). An app that changes
# by itself within that time, a load finishing, needs a sleep or a look.
#
# No sleep is needed after a tap: a dump takes long enough to see the new
# screen, and shot settles first. settle only watches the app's own frames, so
# on another app's screen, the system file picker, sleep instead.
#
# UX defaults to build/ux; set it before sourcing to put shots elsewhere.

export PATH="$HOME/Android/Sdk/platform-tools:$PATH"
_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$_ROOT/tools/adb/adb-driver.sh" >/dev/null 2>&1
UX="${UX:-$_ROOT/build/ux}"
mkdir -p "$UX"
LOCAL_DUMP="$UX/.window-dump.xml"

adb() {
  local args=("$@")
  [ "$1" = -s ] && args=("${@:3}")
  case "${args[*]}" in
    devices* | pull* | "exec-out screencap"* | "shell uiautomator dump"* | \
      logcat* | "shell dumpsys"* | "shell getprop"*) ;;
    *) rm -f "$LOCAL_DUMP" ;;
  esac
  command adb "$@"
}

sleep() {
  rm -f "$LOCAL_DUMP"
  command sleep "$@"
}

# Overrides the driver's: reuses a dump, and removes the last one first, so a
# failed dump is an error rather than the previous screen.
dump_ui() {
  if [ -s "$LOCAL_DUMP" ] &&
    [ $(($(date +%s) - $(stat -c %Y "$LOCAL_DUMP"))) -lt "${UX_DUMP_MAX_AGE:-30}" ]; then
    echo "$LOCAL_DUMP"
    return
  fi
  rm -f "$LOCAL_DUMP"
  command adb -s "$DEVICE" shell "rm -f $DUMP_PATH; uiautomator dump $DUMP_PATH" >/dev/null 2>&1
  command adb -s "$DEVICE" pull "$DUMP_PATH" "$LOCAL_DUMP" >/dev/null 2>&1
  touch -c "$LOCAL_DUMP"
  echo "$LOCAL_DUMP"
}

find_sub() {
  local f
  f=$(dump_ui)
  python3 - "$f" "$1" <<'PY'
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter():
    t = n.attrib.get('text', '') + '|' + n.attrib.get('content-desc', '')
    if sys.argv[2] in t:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.attrib['bounds'])
        x1, y1, x2, y2 = map(int, m.groups())
        print((x1 + x2) // 2, (y1 + y2) // 2)
        break
PY
}

tap_sub() {
  local c
  c=$(find_sub "$1")
  [ -n "$c" ] && adb -s "$DEVICE" shell input tap $c
}

scroll_to() {
  local c y
  for _ in $(seq 1 "${2:-12}"); do
    c=$(find_sub "$1")
    if [ -n "$c" ]; then
      y=${c#* }
      if [ "$y" -gt 300 ] && [ "$y" -lt 2000 ]; then return 0; fi
    fi
    adb -s "$DEVICE" shell input swipe 540 1700 540 900 400
  done
  return 1
}

scroll_up() {
  for _ in $(seq 1 "${1:-1}"); do
    adb -s "$DEVICE" shell input swipe 540 700 540 1700 400
    sleep 0.4
  done
}

# The time of the app's last frame, from SurfaceFlinger: about 20 ms, where a
# hash of the screen takes a second.
_last_frame() {
  command adb -s "$DEVICE" shell "dumpsys SurfaceFlinger --latency '$1'" </dev/null |
    tr -d '\r' | awk 'NF == 3 && $2 > 0 && $2 < 9e18 && $2 > m { m = $2 } END { printf "%.0f", m }'
}

settle() {
  local layer last frame still=0 end=$((SECONDS + ${1:-3}))
  layer=$(command adb -s "$DEVICE" shell dumpsys SurfaceFlinger --list </dev/null | tr -d '\r' |
    grep -oE '[0-9a-f]+ SurfaceView\[io\.github\.lodepav\.[^ ]*\(BLAST\)#[0-9]+' | head -1)
  if [ -z "$layer" ]; then
    command sleep 1
    return
  fi
  last=$(_last_frame "$layer")
  while [ "$still" -lt 3 ] && [ "$SECONDS" -lt "$end" ]; do
    command sleep 0.1
    frame=$(_last_frame "$layer")
    if [ "$frame" = "$last" ]; then still=$((still + 1)); else still=0; fi
    last=$frame
  done
}

shot() {
  settle
  screenshot "$UX/$1.png" >/dev/null && echo "$UX/$1.png"
}

look() {
  settle
  rm -f "$LOCAL_DUMP"
  screenshot "$UX/$1.png" >/dev/null && echo "$UX/$1.png" &
  labels
  wait
}

labels() {
  local f
  f=$(dump_ui)
  python3 - "$f" "${1:-}" <<'PY'
import sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter():
    for k in ('text', 'content-desc'):
        v = n.attrib.get(k, '')
        if v and sys.argv[2] in v:
            print(f'{k}: {v!r}')
PY
}

nodes() {
  local f
  f=$(dump_ui)
  python3 - "$f" <<'PY'
import re, sys, xml.etree.ElementTree as ET
dp = 420 / 160
for n in ET.parse(sys.argv[1]).getroot().iter():
    if n.attrib.get('clickable') != 'true':
        continue
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.attrib['bounds']))
    w, h = round((x2 - x1) / dp), round((y2 - y1) / dp)
    print(f"{n.attrib['bounds']} {w}x{h}dp text={n.attrib.get('text','')!r} "
          f"desc={n.attrib.get('content-desc','')!r} id={n.attrib.get('resource-id','')!r}")
PY
}

font_scale() { adb -s "$DEVICE" shell settings put system font_scale "$1"; }
night() { adb -s "$DEVICE" shell cmd uimode night "$1" >/dev/null; }
