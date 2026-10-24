#!/usr/bin/env bash
# Build, sign and check OpenBite's release APK, then publish it as a GitHub release (D16), after
# openGym-Hevier's hevier/tools/release-apk.sh.
#
#   fork/tools/release-apk.sh
#
# Signs with Go Hevier's release key (~/.config/hevier/release.keystore, alias hevier), shared on
# purpose, and asks for its password when signing; the key's certificate is pinned beside it in
# ~/.config/hevier/apk-cert.txt. Nothing about the key is committed or pushed.
#
# It numbers the release from what was merged since the last one (fork/tools/release_notes.dart):
# a merge that adds a decision raises the minor, anything else the patch; it shows the notes and
# asks only to go ahead or make it a major. It writes fork/VERSION and fork/CHANGELOG.md and
# commits them, and once the APK has passed fork/tools/release-check.sh tags the commit
# openbite-vX.Y.Z (upstream's vX.Y.Z tags share the repo) and publishes it: pushes fork/main and
# the tag, and creates the GitHub release with the APK and its .sha256, which is what the app's
# updater (lib/fork/update/) downloads and verifies. The APK is built in a temporary folder,
# deleted at the end. A publish that fails takes the tag back, so the same version can be run
# again.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KS="${KS:-$HOME/.config/hevier/release.keystore}"
ALIAS="${ALIAS:-hevier}"
CERT="${FORK_CERT:-$(dirname "$KS")/apk-cert.txt}"
export FORK_CERT="$CERT"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$HOME/flutter/bin:$PATH"
BT="$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -1)"
REPO="lodepav/OpenNutriTracker"
cd "$ROOT"

notes_tool() { dart fork/tools/release_notes.dart "$@"; }
json() { python3 -c 'import json, sys; print(json.loads(sys.argv[1])[sys.argv[2]] or "")' "$@"; }

publish() {  # version, apk
  local ver="$1" apk="$2" tag="openbite-v$1" name="openbite-$1.apk" dir up notes digest
  digest="$("${BT}apksigner" verify --print-certs "$apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
  grep -v '^#' "$CERT" 2>/dev/null | grep -q "^$digest" \
    || { echo "$apk is not signed with the pinned release key" >&2; return 1; }
  dir="$(mktemp -d)"
  cp "$apk" "$dir/$name"
  (cd "$dir" && sha256sum "$name" > "$name.sha256")
  up="$(git show "$tag:pubspec.yaml" | sed -n 's/^version: \([^+]*\).*/\1/p')"
  notes="OpenBite $ver, based on OpenNutriTracker $up."$'\n\n'"$(notes_tool notes "$tag")"
  notes+=$'\n\nInstall the APK, or update from the app when it offers it. The download is checked against '"$name"'.sha256.'
  echo; echo "$notes"; echo
  [[ "$(git branch --show-current)" == fork/main ]] && git push -q origin fork/main
  if git push -q origin "$tag" && gh release create "$tag" "$dir/$name" "$dir/$name.sha256" -R "$REPO" \
      --verify-tag --latest --title "OpenBite $ver" --notes "$notes"; then
    rm -rf "$dir"
    return 0
  fi
  rm -rf "$dir"
  echo "publishing failed: the tag is taken back; run again and keep $ver" >&2
  git push -q origin ":refs/tags/$tag" 2>/dev/null || true
  git tag -d "$tag" >/dev/null
  return 1
}

[[ -f "$KS" ]] || { echo "no keystore at $KS" >&2; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo "uncommitted changes: a release is built from a commit" >&2; exit 2; }
# release_notes.dart numbers the release and writes its notes: its tests first.
flutter test test/fork/tools/ >/dev/null || { echo "the release tools' tests fail: flutter test test/fork/tools/" >&2; exit 2; }

# The version: from the merges since the last release, or the one fork/VERSION holds when it has no
# tag yet (the first release, or a run that did not get published), which is released as it is.
VER="$(tr -d '[:space:]' < fork/VERSION)"
UP="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
if ! git rev-parse -q --verify "refs/tags/openbite-v$VER" >/dev/null; then
  echo "OpenBite $VER is not released yet: releasing it as it is"
  NOTES="$(notes_tool notes HEAD)"
  echo "$NOTES"
  if [[ ! -f fork/CHANGELOG.md ]] || ! grep -q "^## $VER " fork/CHANGELOG.md; then
    NF="$(mktemp)"
    echo "$NOTES" > "$NF"
    notes_tool changelog "$VER" "$(date +%F)" "$UP" "$NF"
    rm -f "$NF"
    git add fork/CHANGELOG.md
    git commit -q -m "chore(fork): OpenBite $VER" -- fork/CHANGELOG.md
  fi
else
  NEXT="$(notes_tool next)"
  NEW="$(json "$NEXT" version)"
  [[ -n "$NEW" ]] || { echo "nothing merged since openbite-v$VER: nothing to release" >&2; exit 2; }
  echo; echo "OpenBite $NEW (was $VER), based on OpenNutriTracker $UP"; echo
  json "$NEXT" notes; echo
  IFS=. read -r MA _ _ <<< "$VER"
  read -rp "Release $NEW? [Enter] yes · [M] make it $((MA+1)).0.0 · [q] quit: " go
  case "$go" in
    '') ;;
    M) NEXT="$(notes_tool next --major)"; NEW="$((MA+1)).0.0" ;;
    *) echo "nothing released" >&2; exit 2 ;;
  esac
  git rev-parse -q --verify "refs/tags/openbite-v$NEW" >/dev/null && { echo "openbite-v$NEW is already tagged" >&2; exit 2; }
  echo "$NEW" > fork/VERSION
  NF="$(mktemp)"
  json "$NEXT" notes > "$NF"
  notes_tool changelog "$NEW" "$(date +%F)" "$UP" "$NF"
  rm -f "$NF"
  git add fork/VERSION fork/CHANGELOG.md
  git commit -q -m "chore(fork): OpenBite $NEW" -- fork/VERSION fork/CHANGELOG.md
  VER="$NEW"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/openbite-$VER.apk"

# The full flavour's release build, unsigned (no android/key.properties: the key never enters
# Gradle). nice: a full-speed build has hung this machine.
nice -n 19 flutter build apk --flavor full --release
UNSIGNED=build/app/outputs/flutter-apk/app-full-release.apk
"${BT}zipalign" -f -p 4 "$UNSIGNED" "$TMP/aligned.apk"
echo "signing with $KS ($ALIAS)"
"${BT}apksigner" sign --ks "$KS" --ks-key-alias "$ALIAS" --out "$OUT" "$TMP/aligned.apk"
rm -f "$OUT.idsig"
echo "signed"

DIGEST="$("${BT}apksigner" verify --print-certs "$OUT" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
if ! { [[ -f "$CERT" ]] && grep -v '^#' "$CERT" | grep -q .; }; then
  echo; echo "no certificate pinned yet. This APK's: $DIGEST"
  read -rp "Pin it as the release key in $CERT? [y/N] " yn
  if [[ $yn == [yY]* ]]; then
    echo "$DIGEST  # release key ($ALIAS, $(date +%F))" >> "$CERT"
    chmod 600 "$CERT"
    echo "pinned in $CERT (not in the repo)"
  fi
fi

fork/tools/release-check.sh --apk "$OUT" || {
  echo; echo "release check failed: nothing tagged or published" >&2; exit 1; }

git tag -a "openbite-v$VER" -m "OpenBite $VER" && echo "tagged openbite-v$VER"
publish "$VER" "$OUT"
echo "published: https://github.com/$REPO/releases/tag/openbite-v$VER"
