#!/bin/bash
# bundle_macos.sh — Build and package TeSmart UI as a macOS .app bundle
set -euo pipefail

APP_NAME="TeSmart UI"
BUNDLE_ID="com.tesmart.ui"
VERSION="1.0.0"
EXECUTABLE="tesmart-ui"

TARGET_INPUT="${1:-${MACOS_TARGET:-}}"

if [ -z "$TARGET_INPUT" ]; then
    echo "Select macOS target:"
    echo "  1) Apple Silicon (arm64)"
    echo "  2) Intel (x86_64)"
    printf "Choice [1]: "
    read -r MENU_CHOICE

    case "${MENU_CHOICE:-1}" in
        1)
            TARGET_INPUT="arm64"
            ;;
        2)
            TARGET_INPUT="x86_64"
            ;;
        *)
            echo "Invalid choice: ${MENU_CHOICE}"
            exit 1
            ;;
    esac
fi

case "$TARGET_INPUT" in
    arm64|apple-silicon|apple_silicon|aarch64)
        TARGET="aarch64-macos"
        ARCH_LABEL="Apple Silicon"
        ;;
    x86_64|x64|intel)
        TARGET="x86_64-macos"
        ARCH_LABEL="Intel"
        ;;
    *)
        echo "Usage: $0 [arm64|x86_64]"
        echo ""
        echo "  arm64   Build for Apple Silicon (default)"
        echo "  x86_64  Build for Intel Macs"
        echo ""
        echo "You can also set MACOS_TARGET=arm64 or MACOS_TARGET=x86_64"
        exit 1
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/zig-out"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [ ! -f "$SCRIPT_DIR/AppIcon.icns" ] && [ ! -f "$SCRIPT_DIR/AppIcon.png" ]; then
    echo "ERROR: AppIcon.icns or AppIcon.png is required for macOS bundle"
    exit 1
fi

ICON_BUNDLE_FILE="AppIcon"
if [ ! -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    ICON_BUNDLE_FILE="AppIcon.png"
fi

# ── Step 1: Build ──
echo "==> Building ${EXECUTABLE} for macOS (${ARCH_LABEL}, ${TARGET})..."
cd "$SCRIPT_DIR"
zig build -Dtarget="$TARGET" -Doptimize=ReleaseFast

if [ ! -f "$BUILD_DIR/bin/$EXECUTABLE" ]; then
    echo "ERROR: Build failed — $BUILD_DIR/bin/$EXECUTABLE not found"
    exit 1
fi

# ── Step 2: Create .app structure ──
echo "==> Creating ${APP_NAME}.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES"

# ── Step 3: Copy executable ──
cp "$BUILD_DIR/bin/$EXECUTABLE" "$MACOS_DIR/$EXECUTABLE"
chmod +x "$MACOS_DIR/$EXECUTABLE"

# ── Step 4: Generate Info.plist ──
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>${TARGET%%-*}</string>
    </array>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIconFile</key>
    <string>${ICON_BUNDLE_FILE}</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# ── Step 5: Copy app icon ──
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    echo "    Using AppIcon.icns"
elif [ -f "$SCRIPT_DIR/AppIcon.png" ]; then
    cp "$SCRIPT_DIR/AppIcon.png" "$RESOURCES/AppIcon.png"
    echo "    Using AppIcon.png"
fi

# ── Step 6: Ad-hoc code sign ──
echo "==> Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || {
    echo "    Warning: Code signing failed (app may still work)"
}

# ── Done ──
APP_SIZE=$(du -sh "$APP_DIR" | cut -f1)
echo ""
echo "==> Done! ${APP_NAME}.app ($APP_SIZE)"
echo "    Architecture: ${ARCH_LABEL} (${TARGET})"
echo "    ${APP_DIR}"
echo ""
echo "    To install:  cp -r \"${APP_DIR}\" /Applications/"
echo "    To run:      open \"${APP_DIR}\""
