#!/usr/bin/env bash
# Downloads what the iOS engine needs into Vendor/ (git-ignored):
#   Vendor/Python.xcframework  - CPython for iOS (BeeWare Python-Apple-support)
#   Vendor/app_packages        - pure-Python yt-dlp, gallery-dl and their deps
#
# Pick a release from https://github.com/beeware/Python-Apple-support/releases
# and pass its tag to change versions, e.g.: scripts/fetch-python-ios.sh 3.13-b16
set -euo pipefail

TAG="${1:-3.13-b16}"
PY_VERSION="${TAG%%-*}"
BUILD="${TAG#*-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
ARCHIVE="Python-$PY_VERSION-iOS-support.$BUILD.tar.gz"

mkdir -p "$VENDOR"
cd "$VENDOR"

if [ ! -d Python.xcframework ]; then
  curl -fL -o "$ARCHIVE" "https://github.com/beeware/Python-Apple-support/releases/download/$TAG/$ARCHIVE"
  mkdir -p python-support
  tar -xzf "$ARCHIVE" -C python-support
  mv python-support/Python.xcframework .
  rm -rf "$ARCHIVE" python-support
fi

# Only pure-Python wheels, so nothing needs compiling for iOS.
rm -rf app_packages
python3 -m pip install --quiet --target app_packages \
  --platform any --python-version "$PY_VERSION" --only-binary=:all: --no-deps \
  yt-dlp gallery-dl requests urllib3 idna charset-normalizer certifi
# Console scripts and man pages aren't needed inside the app.
rm -rf app_packages/bin app_packages/share

echo "Vendor/ is ready. Build the iOS app in Xcode."
