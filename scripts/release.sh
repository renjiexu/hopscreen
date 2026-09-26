#!/bin/bash
# Builds a signed + notarized release zip in build/, and optionally publishes it.
#
# One-time setup:
#   1. Install a "Developer ID Application" certificate (Xcode > Settings > Accounts > Manage Certificates).
#   2. xcrun notarytool store-credentials hopscreen-notary --apple-id <you> --team-id <TEAMID>
#
#   scripts/release.sh             build, sign, notarize -> build/Hopscreen-<version>.zip
#   scripts/release.sh --publish   also create the GitHub release and update the Netlify download page
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
ZIP="build/Hopscreen-$VERSION.zip"

export SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "No Developer ID Application certificate found; see setup notes at the top of this script." >&2
  exit 1
fi

scripts/build.sh
rm -f "$ZIP"
ditto -c -k --keepParent build/Hopscreen.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-hopscreen-notary}" --wait
xcrun stapler staple build/Hopscreen.app
rm -f "$ZIP"
ditto -c -k --keepParent build/Hopscreen.app "$ZIP"
spctl --assess --type execute -v build/Hopscreen.app
echo "Release ready: $ZIP"

if [[ "${1:-}" == "--publish" ]]; then
  gh release create "v$VERSION" "$ZIP" --title "Hopscreen $VERSION" --generate-notes
  cp "$ZIP" site/Hopscreen.zip
  npx -y netlify-cli deploy --prod --dir site
fi
