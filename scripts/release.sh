#!/usr/bin/env bash
# Mullion release pipeline.
#
# Usage:
#   VERSION=0.2.0 \
#   DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_KEYCHAIN_PROFILE=mullion-notary \
#   make release
#
# Output: release-build/Mullion-<VERSION>.dmg, signed/notarized/stapled,
# plus an appcast <item> snippet printed to stdout for you to paste into
# the appcast.xml feed.
#
# Idempotent within a single VERSION (rerun safely after a transient
# notarization failure); destructive within release-build/ each invocation.

set -euo pipefail

APP="Mullion"
SCHEME="Mullion"
PROJECT="Mullion.xcodeproj"
RELEASE_DIR="release-build"
ARCHIVE_PATH="$RELEASE_DIR/$APP.xcarchive"
EXPORT_DIR="$RELEASE_DIR/export"
APP_BUNDLE="$EXPORT_DIR/$APP.app"

# --- input validation -----------------------------------------------------

: "${DEVELOPER_ID_APP:?DEVELOPER_ID_APP is required (set the full \"Developer ID Application: Name (TEAMID)\" string)}"
: "${NOTARY_KEYCHAIN_PROFILE:?NOTARY_KEYCHAIN_PROFILE is required (store credentials with: xcrun notarytool store-credentials <profile-name>)}"

if [[ -z "${VERSION:-}" ]]; then
  # Default to the most recent git tag, stripping a leading "v" if present.
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed -E 's/^v//' || true)"
  if [[ -z "$VERSION" ]]; then
    echo "ERROR: VERSION not set and no git tags found. Pass VERSION=x.y.z explicitly." >&2
    exit 1
  fi
fi

DMG_NAME="$APP-$VERSION.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"

echo "==> Release $APP $VERSION"
echo "    signing identity:    $DEVELOPER_ID_APP"
echo "    notary profile:      $NOTARY_KEYCHAIN_PROFILE"

# --- guard against placeholder Info.plist ---------------------------------

PLIST="Mullion/Resources/Info.plist"
if grep -q "CHANGE_ME" "$PLIST"; then
  echo "ERROR: $PLIST still contains CHANGE_ME placeholders." >&2
  echo "       Edit SUFeedURL and SUPublicEDKey before cutting a release — see docs/release.md." >&2
  exit 1
fi

# --- generate project (xcodegen) ------------------------------------------

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen not found. brew install xcodegen." >&2
  exit 1
fi

xcodegen generate

# --- clean release dir ----------------------------------------------------

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR" "$EXPORT_DIR"

# --- archive --------------------------------------------------------------

echo "==> Archiving"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APP" \
  archive | xcpretty || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "ERROR: archive failed (no $ARCHIVE_PATH)." >&2
  exit 1
fi

# --- export ---------------------------------------------------------------

echo "==> Exporting"
EXPORT_OPTIONS="$RELEASE_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$DEVELOPER_ID_APP</string>
</dict>
</plist>
EOF

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: export failed (no $APP_BUNDLE)." >&2
  exit 1
fi

# --- verify codesign ------------------------------------------------------

echo "==> Verifying codesign"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# --- DMG ------------------------------------------------------------------

echo "==> Building DMG"
DMG_STAGE="$RELEASE_DIR/dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
  -volname "$APP $VERSION" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# --- notarize -------------------------------------------------------------

echo "==> Submitting to notary service"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# --- Sparkle signing ------------------------------------------------------

echo "==> Sparkle-signing DMG"
SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData -name sign_update -type f 2>/dev/null | head -n 1 || true)"
if [[ -z "$SIGN_UPDATE" ]]; then
  SIGN_UPDATE="$(find ./DerivedData -name sign_update -type f 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$SIGN_UPDATE" ]] && command -v sign_update >/dev/null 2>&1; then
  SIGN_UPDATE="$(command -v sign_update)"
fi
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "ERROR: sign_update not found. Either build the project once so Sparkle's tools" >&2
  echo "       land in DerivedData, or 'brew install sparkle' for the system-wide CLI." >&2
  exit 1
fi

SPARKLE_SIG_LINE="$("$SIGN_UPDATE" "$DMG_PATH")"

# --- appcast snippet ------------------------------------------------------

SIZE_BYTES="$(stat -f %z "$DMG_PATH")"
PUBDATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"
RELEASE_FILENAME="$(basename "$DMG_PATH")"

cat <<EOF

==> DONE. Signed, notarized, stapled, Sparkle-signed.

DMG:  $DMG_PATH
Size: $SIZE_BYTES bytes

Paste this <item> into docs/appcast.xml (and update the enclosure URL to
the real GitHub Releases asset URL once you've uploaded the DMG):

<item>
  <title>$APP $VERSION</title>
  <pubDate>$PUBDATE</pubDate>
  <sparkle:version>$VERSION</sparkle:version>
  <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
  <enclosure
    url="https://github.com/OWNER/REPO/releases/download/v$VERSION/$RELEASE_FILENAME"
    length="$SIZE_BYTES"
    type="application/octet-stream"
    $SPARKLE_SIG_LINE />
</item>

EOF
