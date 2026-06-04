#!/usr/bin/env bash
# Build Pikard (Release, ad-hoc signed) and install it into /Applications.
# No Apple Developer account needed -- this is for personal local use.
#
# Usage:
#   ./install.sh            build, install, and relaunch
#   ./install.sh --no-open  build and install but don't launch
set -euo pipefail

cd "$(dirname "$0")"

SCHEME="Pikard"
APP_NAME="Pikard.app"
DEST="/Applications"
DD="$(mktemp -d /tmp/pikard-build.XXXXXX)"
OPEN_AFTER=1
[ "${1:-}" = "--no-open" ] && OPEN_AFTER=0

cleanup() { rm -rf "$DD"; }
trap cleanup EXIT

echo "[1/4] Building $SCHEME (Release, ad-hoc signed)..."
xcodebuild -scheme "$SCHEME" -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  build >/dev/null

APP="$DD/Build/Products/Release/$APP_NAME"
[ -d "$APP" ] || { echo "Build produced no $APP_NAME"; exit 1; }

echo "[2/4] Quitting any running copy..."
pkill -x Pikard 2>/dev/null || true
sleep 1

echo "[3/4] Installing to $DEST/$APP_NAME ..."
rm -rf "$DEST/$APP_NAME"
cp -R "$APP" "$DEST/"
codesign -dvv "$DEST/$APP_NAME" 2>&1 | grep -E "Identifier|Signature" | sed 's/^/      /'

if [ "$OPEN_AFTER" -eq 1 ]; then
  echo "[4/4] Launching..."
  open "$DEST/$APP_NAME"
else
  echo "[4/4] Skipped launch (--no-open)."
fi

echo "Done. Pikard is in the menu bar (top-right)."
echo "Enable 'Launch Pikard at login' in the menu -> Settings to auto-start."
