#!/usr/bin/env bash
# Seam S31: the app calls itself OpenBite (D8) in every language. Rewrites the name in
# upstream's translation files, which `flutter gen-l10n` turns into lib/generated.
# Safe to re-run. After an upstream merge that touches these strings, take upstream's
# side of the conflict and run this again; test/fork/rebrand_test.dart fails until then.
set -euo pipefail
cd "$(dirname "$0")/../.."
sed -i 's/OpenNutriTracker/OpenBite/g' lib/l10n/intl_*.arb
