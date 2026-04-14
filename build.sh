#!/bin/bash
set -e

APP_NAME="PortMonitor"
BUNDLE_IDENTIFIER="com.rahul.PortMonitor"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Cleaning old app bundle..."
rm -rf "${APP_DIR}"

echo "Creating bundle structure..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Writing Info.plist..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Compiling Swift files..."
swiftc \
    -parse-as-library \
    -framework SwiftUI \
    -o "${MACOS_DIR}/${APP_NAME}" \
    NetworkMonitor.swift \
    ContentView.swift \
    PortMonitorApp.swift

echo "Code signing application..."
codesign --force --deep --sign - "${APP_DIR}"

echo "Zipping application for Homebrew Cask..."
rm -f "${APP_NAME}.zip"
zip -r "${APP_NAME}.zip" "${APP_DIR}"

echo "Build successful! App bundled at: $(pwd)/${APP_DIR}"
echo "Zip archive ready at: $(pwd)/${APP_NAME}.zip"
