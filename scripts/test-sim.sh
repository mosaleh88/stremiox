#!/usr/bin/env bash
set -e

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "▶ Checking Apple TV simulator..."
DEVICE_ID=$(xcrun simctl list devices tvOS | grep "Booted" | head -1 | grep -oE '[0-9A-F-]{36}')
if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(xcrun simctl list devices tvOS | grep "Apple TV" | head -1 | grep -oE '[0-9A-F-]{36}')
    echo "  Booting Apple TV ($DEVICE_ID)..."
    xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
fi

echo "▶ Compiling for tvOS Simulator..."
cd "$REPO_ROOT/app"
xcrun xcodebuild \
    -scheme Xtv \
    -destination "platform=tvOS Simulator,id=$DEVICE_ID" \
    -derivedDataPath build/sim \
    build -quiet

echo "▶ Deploying to simulator ($DEVICE_ID)..."
xcrun simctl install "$DEVICE_ID" "$REPO_ROOT/app/build/sim/Build/Products/Debug-appletvsimulator/Xtv.app"
xcrun simctl terminate "$DEVICE_ID" com.xtv.tv 2>/dev/null || true
xcrun simctl launch "$DEVICE_ID" com.xtv.tv

echo "✅ App updated and running on Apple TV Simulator!"

