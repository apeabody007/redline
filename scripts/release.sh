#!/bin/bash
# Builds, signs, notarizes and staples a distributable Redline DMG.
#
#   ./scripts/release.sh 1.2
#
# ---------------------------------------------------------------------------
# UNTESTED. This was written on a Mac with no Developer ID certificate
# installed, so every step from `codesign` onward has never actually run.
# Treat the first real run as a debugging session rather than a release.
# The preflight below is deliberately loud so it fails on the setup rather
# than halfway through a notarization.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="Redline"
BUNDLE_ID="dev.aaronpeabody.redline"
NOTARY_PROFILE="${NOTARY_PROFILE:-redline-notary}"
VERSION="${1:-}"
DIST="build/dist"
DMG="$DIST/$NAME-$VERSION.dmg"

if [[ -z "$VERSION" ]]; then
  echo "usage: ./scripts/release.sh <version>    e.g. ./scripts/release.sh 1.2" >&2
  exit 2
fi

# --- Preflight ---------------------------------------------------------------

fail() { echo; echo "FAILED: $1" >&2; echo; shift; printf '%s\n' "$@" >&2; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/') || true

if [[ -z "${IDENTITY:-}" ]]; then
  fail "no Developer ID Application certificate in the keychain" \
    "This is the one thing that cannot be scripted around. With an Apple" \
    "Developer membership:" \
    "" \
    "  1. developer.apple.com/account -> Certificates -> +" \
    "  2. Choose 'Developer ID Application'" \
    "  3. Follow the prompts to upload a CSR from Keychain Access" \
    "     (Keychain Access -> Certificate Assistant -> Request a Certificate" \
    "      from a Certificate Authority, saved to disk)" \
    "  4. Download the .cer and double-click it to install" \
    "" \
    "Then check it landed:" \
    "  security find-identity -v -p codesigning"
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  fail "no stored notary credentials under profile '$NOTARY_PROFILE'" \
    "Create an app-specific password at appleid.apple.com (Sign-In and" \
    "Security -> App-Specific Passwords), then store it once:" \
    "" \
    "  xcrun notarytool store-credentials $NOTARY_PROFILE \\" \
    "    --apple-id <your-apple-id-email> \\" \
    "    --team-id <YOUR_TEAM_ID> \\" \
    "    --password <app-specific-password>" \
    "" \
    "The team id is on developer.apple.com/account under Membership."
fi

echo "Signing identity: $IDENTITY"
echo "Notary profile:   $NOTARY_PROFILE"
echo

# --- Build -------------------------------------------------------------------

./build.sh test
./build.sh

APP="build/$NAME.app"
rm -rf "$DIST" build/dmg
mkdir -p "$DIST" build/dmg

# --- Sign --------------------------------------------------------------------

# The hardened runtime is required for notarization. Redline resolves IOKit
# symbols with dlopen, which is fine under it: IOKit is Apple-signed and comes
# out of the shared cache, so no library-validation exception is needed.
echo "==> Signing the app"
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

# --- Package -----------------------------------------------------------------

echo "==> Building the disk image"
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "$NAME" -srcfolder build/dmg -ov -format UDZO "$DMG"

echo "==> Signing the disk image"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# --- Notarize ----------------------------------------------------------------

# --wait blocks until Apple returns a verdict, usually a couple of minutes.
# On rejection, the log URL in the output says exactly which file failed.
echo "==> Submitting to Apple for notarization"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# --- Verify ------------------------------------------------------------------

# This is the check that matters: it is what Gatekeeper will do on a machine
# that has never seen this app before.
echo "==> Verifying as Gatekeeper would"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo
echo "Done: $DMG"
echo
echo "Attach it to the release:"
echo "  gh release upload v$VERSION \"$DMG\" --clobber"
