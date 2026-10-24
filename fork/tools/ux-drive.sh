# Helpers for driving the app on the emulator by what is on screen, for UX
# reviews. Source it: `source fork/tools/ux-drive.sh`. Builds on
# tools/adb/adb-driver.sh (tap_id, id_exists, list_ids, dump_ui, press_back).
#
#   find_sub TEXT         centre "x y" of the first node whose text or
#                         content-desc contains TEXT, or nothing
#   tap_sub TEXT          tap it; fails when it is not on screen
#   scroll_to TEXT [N]    swipe up until TEXT is on screen, at most N times
#   scroll_up [N]         swipe down N times, back towards the top
#   shot NAME             screenshot into $UX/NAME.png
#   labels [FILTER]       every text / content-desc on screen, one a line
#   nodes                 clickable nodes: bounds, size in dp, text, desc
#   font_scale X          system font scale (1.0 normal, 2.0 for A6)
#   night yes|no          dark theme on or off
#
# UX defaults to build/ux; set it before sourcing to put shots elsewhere.

export PATH="$HOME/Android/Sdk/platform-tools:$PATH"
_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$_ROOT/tools/adb/adb-driver.sh" >/dev/null 2>&1
UX="${UX:-$_ROOT/build/ux}"
mkdir -p "$UX"

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
    sleep 0.6
  done
  return 1
}

scroll_up() {
  for _ in $(seq 1 "${1:-1}"); do
    adb -s "$DEVICE" shell input swipe 540 700 540 1700 400
    sleep 0.4
  done
}

shot() { screenshot "$UX/$1.png" >/dev/null && echo "$UX/$1.png"; }

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
