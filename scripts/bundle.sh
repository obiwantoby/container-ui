#!/bin/bash
# Wrap the ContainerUI executable into a proper macOS .app bundle.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Container.app"
BIN="$ROOT/.build/$CONFIG/ContainerUI"

if [ ! -x "$BIN" ]; then
    echo "Building ContainerUI ($CONFIG)…"
    (cd "$ROOT" && swift build -c "$CONFIG" --product ContainerUI)
fi

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Container"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Container</string>
    <key>CFBundleIdentifier</key><string>dev.local.container-ui</string>
    <key>CFBundleName</key><string>Container</string>
    <key>CFBundleDisplayName</key><string>Container</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS will run it locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Done: $APP"
