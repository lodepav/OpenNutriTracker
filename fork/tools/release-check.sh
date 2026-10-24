#!/usr/bin/env bash
# Security gates before a build for daily use, after openGym-Hevier's release check (its D26,
# D38): leaked secrets, vulnerable dependencies, new Dart packages, and the APK's signing,
# debuggable flag, permissions, native libraries and exported components.
#
#   fork/tools/release-check.sh                   # sources only
#   fork/tools/release-check.sh --apk <file>      # also a signed release APK
#   fork/tools/release-check.sh --accept-packages # after reviewing pubspec.lock's changes
#
# Every gate runs even when one fails; exit 1 if any failed. A finding is fixed, or accepted
# with its reason in fork/security/ (a reviewed diff). Scanners: fork/tools/install-scanners.sh.
# Needs the network (Trivy's vulnerability database).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SEC="$ROOT/fork/security"
# The release key's pinned certificate lives beside the keystore, never in the repo. OpenBite
# shares Go Hevier's key (D16).
CERT="${FORK_CERT:-$HOME/.config/hevier/apk-cert.txt}"
# The fork's own id (D8, android/app/fork.gradle).
APP_ID="${FORK_APP_ID:-io.github.lodepav.openbite}"
export PATH="$HOME/.local/opt/gitleaks:$HOME/.local/opt/trivy:$PATH"
APK=""
cd "$ROOT"

# pubspec.lock as "name version source sha256", one package a line.
packages() {
  python3 - <<'PY'
import re
lock = open('pubspec.lock').read().split('\nsdks:')[0]
for m in re.finditer(r'(?m)^  (\S+):\n((?:    .*\n)+)', lock):
    body = m.group(2)
    get = lambda k: (re.search(rf'\b{k}: "?([^"\n]+)"?', body) or [None, '-'])[1]
    print(m.group(1), get('version'), get('source'), get('sha256')[:16])
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk) APK="$(realpath "$2")"; shift ;;
    --accept-packages)
      { echo "# pubspec.lock as reviewed: name version source sha256 (fork/tools/release-check.sh)."
        packages; } > "$SEC/packages.txt"
      echo "wrote fork/security/packages.txt: commit it with what was reviewed"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

for t in gitleaks trivy python3; do
  command -v "$t" >/dev/null || { echo "$t not found: run fork/tools/install-scanners.sh" >&2; exit 2; }
done
if [[ -n "$APK" ]]; then
  BT="$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
  [[ -x "${BT}aapt2" && -x "${BT}apksigner" ]] || { echo "no Android build-tools with aapt2/apksigner" >&2; exit 2; }
  command -v java >/dev/null || { echo "java not found: apksigner needs a JDK" >&2; exit 2; }
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
NAMES=() PIDS=()
gate() {   # name, command... : started in the background, its output kept for report
  local n=${#NAMES[@]}
  NAMES+=("$1"); shift
  "$@" > "$TMP/gate-$n.log" 2>&1 &
  PIDS+=($!)
}
# The lists' lines are "value  # reason"; blank lines and comments skip.
listed() { [[ -f "$1" ]] || return 0; sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$1"; }
against() {   # list file, what (for the messages), entries on stdin
  local have allowed new gone
  have="$(sort -u)"
  allowed="$(listed "$1" | sed 's/[[:space:]]\{2,\}.*//' | sort -u)"
  new="$(comm -23 <(echo "$have") <(echo "$allowed") | sed '/^$/d')"
  gone="$(comm -13 <(echo "$have") <(echo "$allowed") | sed '/^$/d')"
  [[ -n "$gone" ]] && { echo "listed but no longer there (remove from the list):"; echo "$gone" | sed 's/^/  /'; }
  [[ -z "$new" ]] && { echo "$(echo "$have" | sed '/^$/d' | wc -l) $2, all listed"; return 0; }
  echo "not in ${1#"$ROOT/"}:"; echo "$new" | sed 's/^/  /'
  return 1
}

committed() {
  local dirty; dirty="$(git status --porcelain)"
  [[ -z "$dirty" ]] && { echo "clean"; return 0; }
  echo "uncommitted changes, so this is not a check of a commit:"; echo "$dirty" | head -20
  return 1
}
gate "working tree committed" committed

GL=(--no-banner --redact --verbose --log-level warn --gitleaks-ignore-path "$SEC/gitleaksignore")
gate "secrets: git history" gitleaks git . "${GL[@]}"
worktree_secrets() {
  local rc=0
  gitleaks git . --pre-commit "${GL[@]}" || rc=1
  gitleaks git . --staged "${GL[@]}" || rc=1
  mkdir -p "$TMP/untracked"
  git ls-files -z --others --exclude-standard | xargs -0 -r cp --parents -t "$TMP/untracked"
  gitleaks dir "$TMP/untracked" "${GL[@]}" || rc=1
  return $rc
}
gate "secrets: working tree" worktree_secrets

# Trivy refreshes its database when due, but a stale one would pass in silence: fail past a week.
vulns() {
  trivy fs . --scanners vuln --include-dev-deps --skip-dirs build --skip-dirs flutter \
    --ignorefile "$SEC/trivyignore.yaml" --exit-code 1 --quiet || return 1
  local meta="${TRIVY_CACHE_DIR:-$HOME/.cache/trivy}/db/metadata.json" at age
  at="$(python3 -c "import json; print(json.load(open('$meta'))['UpdatedAt'])" 2>/dev/null)" || { echo "no database metadata at $meta"; return 1; }
  age=$(( ( $(date +%s) - $(date -d "$at" +%s) ) / 86400 ))
  echo "vulnerability database updated $at ($age days ago)"
  (( age <= 7 )) || { echo "older than a week"; return 1; }
}
gate "dependencies: known vulnerabilities" vulns

# A package added, bumped or re-published since the last review (a changed sha256 at the same
# version is the one to worry about). Review each line, then --accept-packages.
dart_packages() { packages | against "$SEC/packages.txt" "Dart packages"; }
gate "supply chain: Dart packages" dart_packages

if [[ -n "$APK" ]]; then
  unzip -q "$APK" -d "$TMP/apk"
  # From inside it, so a finding's fingerprint has no temporary path.
  apk_secrets() { cd "$TMP/apk" && gitleaks dir . "${GL[@]}"; }
  gate "secrets: APK" apk_secrets
  # Signed by the fork's own key: a valid signature, not the debug key, the pinned certificate.
  apk_signature() {
    local out digest
    out="$("${BT}apksigner" verify --print-certs "$APK" 2>&1)" || { echo "$out" | grep -v '^WARNING' | head -5; echo "not signed, or the signature does not verify"; return 1; }
    if echo "$out" | grep -q 'CN=Android Debug'; then echo "signed with the debug key"; return 1; fi
    if [[ "$(echo "$out" | grep -c '^Signer #[0-9]* certificate DN:')" -ne 1 ]]; then echo "not exactly one signer"; return 1; fi
    digest="$(echo "$out" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
    if listed "$CERT" | grep -qx "$digest"; then echo "certificate $digest"; return 0; fi
    echo "certificate $digest is not pinned in $CERT"
    listed "$CERT" | grep -q . || echo "(nothing pinned yet: if this is the fork's release key, add the digest there)"
    return 1
  }
  # v2 or later: v1 alone leaves the zip's other bytes unsigned.
  apk_scheme() {
    local out schemes
    out="$("${BT}apksigner" verify -v "$APK" 2>/dev/null)" || { echo "the signature does not verify"; return 1; }
    schemes="$(echo "$out" | sed -n 's/^Verified using \(v[0-9.]*\) scheme.*: true$/\1/p' | tr '\n' ' ')"
    if echo "$out" | grep -Eq '^Verified using v(2|3|3\.1) scheme.*: true$'; then echo "schemes: $schemes"; return 0; fi
    echo "only ${schemes:-no scheme}: v2 or later is required"; return 1
  }
  # The release app id (not .develop) and not debuggable.
  apk_release() {
    local badging pkg rc=0
    badging="$("${BT}aapt2" dump badging "$APK")" || return 1
    pkg="$(echo "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
    [[ "$pkg" == "$APP_ID" ]] || { echo "app id $pkg, not $APP_ID"; rc=1; }
    if echo "$badging" | grep -q '^application-debuggable'; then echo "android:debuggable is set"; rc=1; fi
    [[ $rc == 0 ]] && echo "$pkg, not debuggable"
    return $rc
  }
  apk_permissions() {
    "${BT}aapt2" dump permissions "$APK" | sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" |
      sed "s/^$APP_ID\(\.develop\)\{0,1\}\./\$PKG./" | against "$SEC/apk-permissions.txt" "permissions"
  }
  apk_native() {
    unzip -Z1 "$APK" | sed -n 's|^lib/[^/]*/\([^/]*\.so\)$|\1|p' | against "$SEC/apk-native-libs.txt" "native libraries"
  }
  # What other apps can reach: "type name [permission]".
  apk_exported() {
    "${BT}aapt2" dump xmltree --file AndroidManifest.xml "$APK" | awk '
      function out() { if (t != "" && ex == "true") print t " " n (perm != "" ? " [" perm "]" : "") ; t = "" }
      /E: (activity|activity-alias|receiver|service|provider) / { out(); t = $2; n = ""; ex = ""; perm = ""; depth = index($0, "E:"); next }
      /E: / { if (t != "" && index($0, "E:") <= depth) out(); next }
      t != "" && /android:name\(/ && n == "" { match($0, /="[^"]*"/); n = substr($0, RSTART + 2, RLENGTH - 3) }
      t != "" && /android:exported\(/ { ex = ($0 ~ /=true/) ? "true" : "false" }
      t != "" && /android:permission\(/ { match($0, /="[^"]*"/); perm = substr($0, RSTART + 2, RLENGTH - 3) }
      END { out() }' | against "$SEC/apk-exported.txt" "exported components"
  }
  gate "APK: signing certificate" apk_signature
  gate "APK: signature scheme" apk_scheme
  gate "APK: release build" apk_release
  gate "APK: permissions" apk_permissions
  gate "APK: native libraries" apk_native
  gate "APK: exported components" apk_exported
fi

FAILED=()
for i in "${!NAMES[@]}"; do
  echo; echo "── ${NAMES[$i]}"
  if wait "${PIDS[$i]}"; then cat "$TMP/gate-$i.log"; echo "ok"
  else cat "$TMP/gate-$i.log"; FAILED+=("${NAMES[$i]}"); fi
done
echo
if [[ ${#FAILED[@]} -eq 0 ]]; then echo "release-check: all gates passed"; exit 0; fi
echo "release-check: ${#FAILED[@]} gate(s) failed:"; printf '  ✗ %s\n' "${FAILED[@]}"
exit 1
