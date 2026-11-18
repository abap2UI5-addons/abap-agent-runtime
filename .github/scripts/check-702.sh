#!/usr/bin/env bash
# The 7.02 gate of a pull request (CI: `npm run check:702`, a job of ci.yaml).
# Downports a scratch copy of src/ in build/702 with
# .github/abaplint/abap_702.jsonc and lints the result - src/ itself is never
# rewritten, so it is safe on a laptop too. ci-702 does the same on main
# (`npm run auto_downport`) and publishes the result to the branch 702.
# headless-frontend and abap2UI5 resolve from their own 702 branches
# (build/702/.abaplint-deps, cloned on the first run).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$root/build/702"

rm -rf "$build/src" "$build/.github"
mkdir -p "$build/.github/abaplint"
cp -r "$root/src" "$build/src"
cp "$root/.github/abaplint/abap_702.jsonc" "$build/.github/abaplint/abap_702.jsonc"

cd "$build"
# --fix exits non-zero while findings remain; the lint below decides
npx abaplint --fix .github/abaplint/abap_702.jsonc > /dev/null 2>&1 || true
# the same fix-up as npm run syfixes
find src -type f -name '*.abap' -exec sed -i -e 's/ RAISE EXCEPTION TYPE cx_sy_itab_line_not_found/ ASSERT 1 = 0/g' {} +
npx abaplint .github/abaplint/abap_702.jsonc
