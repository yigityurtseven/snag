#!/bin/sh
# Builds build/ipa/Snag.ipa for sideloading with AltStore or SideStore.
#
# The App Store won't take Snag (guideline 5.2.3), so the iPhone app is
# installed with AltStore or SideStore, which re-sign it with the user's own
# Apple ID. The build is signed for development with your team only because
# the Python install step signs every framework; that signature is replaced.
#
# Usage: scripts/build-ipa.sh
# Then: upload build/ipa/Snag.ipa to a GitHub release, and put the version,
# date and size this prints into the website's AltStore source.
set -eu
cd "$(dirname "$0")/.."

if [ ! -d Vendor/Python.xcframework ]; then
  echo "Python for iOS is missing. Run scripts/fetch-python-ios.sh first." >&2
  exit 1
fi

OUT=build/ipa
rm -rf "$OUT"
mkdir -p "$OUT"

xcodebuild archive \
  -project Snag.xcodeproj \
  -scheme Snag \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Snag.xcarchive" \
  -allowProvisioningUpdates \
  -quiet

mkdir -p "$OUT/Payload"
cp -R "$OUT/Snag.xcarchive/Products/Applications/Snag.app" "$OUT/Payload/"
(cd "$OUT" && zip -qry Snag.ipa Payload && rm -rf Payload)

INFO="$OUT/Snag.xcarchive/Products/Applications/Snag.app/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$INFO")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$INFO")
SIZE=$(stat -f %z "$OUT/Snag.ipa")

echo
echo "Built $OUT/Snag.ipa"
echo "  version: $VERSION"
echo "  buildVersion: $BUILD"
echo "  size: $SIZE"
echo "  date: $(date +%Y-%m-%d)"
