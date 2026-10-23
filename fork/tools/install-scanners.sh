#!/usr/bin/env bash
# Install the scanners release-check.sh uses, user-local (no sudo, no Docker):
#   gitleaks  -> ~/.local/opt/gitleaks/gitleaks
#   trivy     -> ~/.local/opt/trivy/trivy
#
# Versions and checksums are pinned here. To update: change the version, take the sha256 of the
# linux x64 archive from the release's checksums file, and say so in the commit (fork/tools/release-check.sh).
# Trivy is the version openGym-Hevier pins, so both forks scan alike.
set -euo pipefail

GITLEAKS_VERSION=8.30.1
GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
TRIVY_VERSION=0.74.0
TRIVY_SHA256=2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a

OPT="$HOME/.local/opt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

install_one() {   # name version url sha256 binary-in-archive
  local name=$1 version=$2 url=$3 sha=$4 bin=$5
  if "$OPT/$name/$name" --version 2>/dev/null | grep -q "$version"; then
    echo "$name $version already installed"; return
  fi
  echo "downloading $name $version"
  curl -fsSL "$url" -o "$TMP/$name.tgz"
  echo "$sha  $TMP/$name.tgz" | sha256sum -c --quiet || { echo "$name: checksum mismatch, not installed" >&2; exit 1; }
  mkdir -p "$TMP/$name" "$OPT/$name"
  tar -xzf "$TMP/$name.tgz" -C "$TMP/$name" "$bin"
  install -m 755 "$TMP/$name/$bin" "$OPT/$name/$name"
  echo "installed $OPT/$name/$name"
}

install_one gitleaks "$GITLEAKS_VERSION" \
  "https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
  "$GITLEAKS_SHA256" gitleaks
install_one trivy "$TRIVY_VERSION" \
  "https://github.com/aquasecurity/trivy/releases/download/v$TRIVY_VERSION/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
  "$TRIVY_SHA256" trivy
