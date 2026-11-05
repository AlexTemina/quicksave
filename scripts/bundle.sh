#!/bin/bash
# Build Quicksave.app, install it in /Applications and (re)launch it. QUICKSAVE_NO_LAUNCH=1 builds without launching.
set -euo pipefail
cd "$(dirname "$0")/../app"
swift build -c release
app="/Applications/Quicksave.app"
[ "${QUICKSAVE_NO_LAUNCH:-}" = 1 ] || pkill -x Quicksave 2>/dev/null || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Quicksave "$app/Contents/MacOS/Quicksave"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Quicksave</string>
  <key>CFBundleIdentifier</key><string>com.alextemina.quicksave</string>
  <key>CFBundleExecutable</key><string>Quicksave</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
</dict>
</plist>
PLIST
# A stable identity keeps macOS permissions (App Management, Automation) across rebuilds; ad-hoc signing resets them every build.
identity="${QUICKSAVE_SIGN_IDENTITY:-Hearthian Local Signing}"
if security find-identity -v -p codesigning | grep -q "\"$identity\""; then
  codesign --force --sign "$identity" "$app"
else
  echo "no '$identity' signing identity, signing ad-hoc (macOS will ask for permissions again after every build)" >&2
  codesign --force --sign - "$app"
fi
[ "${QUICKSAVE_NO_LAUNCH:-}" = 1 ] || open "$app"
echo "$app"
