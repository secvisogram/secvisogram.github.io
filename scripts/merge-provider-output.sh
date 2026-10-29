#!/usr/bin/env bash
# Usage: merge-provider-output.sh <app-build-dir> <provider-checkout-dir>
#
# Overlays the CSAF trusted-provider `.well-known/csaf/` tree from a
# csaf-files gh-pages checkout onto the Secvisogram app build as an exact
# mirror. The provider tree is staged, validated and rewritten first; the app
# build is only touched once the staged output is valid.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <app-build-dir> <provider-checkout-dir>" >&2
  exit 2
fi

APP="$1"
PROVIDER="$2"
SUBTREE=".well-known/csaf"
OLD_PREFIX="https://secvisogram.github.io/csaf-files/.well-known/csaf"
NEW_PREFIX="https://secvisogram.github.io/.well-known/csaf"
OLD_BASE="https://secvisogram.github.io/csaf-files"
GENERATED_FILES=(
  provider-metadata.json
  service.json
  white/csaf-feed-tlp-white.json
)

die() {
  echo "error: $*" >&2
  exit 1
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[ -d "$APP" ] || die "app build directory not found: $APP"
[ -d "$PROVIDER/$SUBTREE" ] || die "provider output not found: $PROVIDER/$SUBTREE"

for f in "${GENERATED_FILES[@]}"; do
  [ -f "$PROVIDER/$SUBTREE/$f" ] || die "provider output incomplete, missing $SUBTREE/$f"
  jq -e . "$PROVIDER/$SUBTREE/$f" >/dev/null || die "invalid JSON in $SUBTREE/$f"
done

rsync -a "$PROVIDER/$SUBTREE/" "$STAGE/"

# TODO(csaf-action#canonical_url_prefix): temporary workaround. csaf-action derives
# the prefix from the csaf-files Pages URL, but the files are served from the
# site root. Remove once csaf-action supports a canonical_url_prefix input.
for f in "${GENERATED_FILES[@]}"; do
  # Rewriting would invalidate checksums/signatures, so fail instead.
  for ext in asc sha256 sha512; do
    [ ! -e "$STAGE/$f.$ext" ] || die "$SUBTREE/$f.$ext exists and would no longer match the rewritten $f"
  done
  sed -i "s|$OLD_PREFIX|$NEW_PREFIX|g" "$STAGE/$f"
done

# Warn about other files (e.g. signed advisories, left untouched) still using the old path.
if leftovers="$(grep -rIl --exclude='*.asc' --exclude='*.sha256' --exclude='*.sha512' -F "$OLD_BASE" "$STAGE")"; then
  while IFS= read -r file; do
    echo "::warning::${file#"$STAGE"/} still references $OLD_BASE"
  done <<< "$leftovers"
fi

mkdir -p "$APP/$SUBTREE"
rsync -a --delete "$STAGE/" "$APP/$SUBTREE/"
