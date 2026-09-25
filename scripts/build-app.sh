#!/bin/bash
# Builds GymPass.app from the SwiftPM products and signs it (ad-hoc by default).
#
#   ./scripts/build-app.sh                 # debug-free release build, ad-hoc signed
#   CODESIGN_IDENTITY="Developer ID…" ./scripts/build-app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
DIST="$ROOT/dist"
APP="$DIST/GymPass.app"
BUNDLE_ID="com.jackwells.gympass"
AGENT_LABEL="com.jackwells.gympass.agent"

echo "==> Building products ($CONFIGURATION)"
swift build -c "$CONFIGURATION"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"

cp "$BIN_DIR/GymPassApp" "$APP/Contents/MacOS/GymPass"
cp "$BIN_DIR/GymPassAgent" "$APP/Contents/MacOS/GymPassAgent"

# App icon (drawn by script; converted with iconutil).
ICONSET="$(mktemp -d)/AppIcon.iconset"
swift "$ROOT/scripts/build-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Info.plist
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GymPass</string>
    <key>CFBundleDisplayName</key><string>GymPass</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>1.0.0</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>GymPass</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>GymPass</string>
</dict>
</plist>
PLIST

# Embedded agent LaunchAgent (used if a Team-ID-signed build switches to SMAppService).
cat > "$APP/Contents/Library/LaunchAgents/${AGENT_LABEL}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${AGENT_LABEL}</string>
    <key>BundleProgram</key><string>Contents/MacOS/GymPassAgent</string>
    <key>ProgramArguments</key>
    <array><string>GymPassAgent</string><string>--agent</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>ProcessType</key><string>Background</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST

echo "==> Signing (identity: $IDENTITY)"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP/Contents/MacOS/GymPassAgent"
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/GymPassAgent"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP" || true

# Zipped copy for distribution.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/GymPass.zip"

echo "==> Done: $APP"
echo "    Launch with: open \"$APP\""
echo "    Note: ad-hoc builds use the LaunchAgent fallback; a Team-ID-signed build can use SMAppService."
