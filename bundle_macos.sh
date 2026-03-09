#!/bin/bash
# bundle_macos.sh — Build and package TeSmart UI as a macOS .app bundle
set -euo pipefail

APP_NAME="TeSmart UI"
BUNDLE_ID="com.tesmart.ui"
VERSION="1.0.0"
EXECUTABLE="tesmart-ui"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/zig-out"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# ── Step 1: Build ──
echo "==> Building ${EXECUTABLE}..."
cd "$SCRIPT_DIR"
zig build -Doptimize=ReleaseFast

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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

# ── Step 5: Generate app icon ──
# If an AppIcon.icns already exists in the project, use it
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    echo "    Using existing AppIcon.icns"
elif [ -f "$SCRIPT_DIR/AppIcon.png" ]; then
    # Convert PNG to icns via iconset
    echo "    Converting AppIcon.png to icns..."
    ICONSET="$RESOURCES/AppIcon.iconset"
    mkdir -p "$ICONSET"
    cp "$SCRIPT_DIR/AppIcon.png" "$ICONSET/icon_512x512@2x.png"
    for size in 16 32 64 128 256 512; do
        sips -z $size $size "$SCRIPT_DIR/AppIcon.png" \
            --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1 || true
    done
    for size in 16 32 128 256; do
        double=$((size * 2))
        cp "$ICONSET/icon_${double}x${double}.png" \
           "$ICONSET/icon_${size}x${size}@2x.png" 2>/dev/null || true
    done
    iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns" 2>/dev/null || true
    rm -rf "$ICONSET"
    if [ -f "$RESOURCES/AppIcon.icns" ]; then
        echo "    Converted AppIcon.png -> AppIcon.icns"
    else
        echo "    Warning: Conversion failed (app will use default icon)"
    fi
else
    # Generate a simple icon using sips (ships with macOS)
    echo "    Generating placeholder icon..."
    ICONSET="$RESOURCES/AppIcon.iconset"
    mkdir -p "$ICONSET"

    # Create a simple 1024x1024 PNG with a colored background using Python
    python3 -c "
import struct, zlib

def make_png(w, h, r, g, b):
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            # Simple gradient KVM icon: dark border + blue center
            bx = min(x, w - 1 - x)
            by = min(y, h - 1 - y)
            border = min(bx, by)
            if border < w // 16:
                raw += bytes([30, 30, 35, 255])
            elif border < w // 12:
                raw += bytes([0, 120, 255, 255])
            else:
                raw += bytes([45, 45, 55, 255])
    # PNG chunks
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

with open('$ICONSET/icon_512x512@2x.png', 'wb') as f:
    f.write(make_png(1024, 1024, 0, 120, 255))
" 2>/dev/null || true

    # Generate remaining sizes from the 1024 source
    if [ -f "$ICONSET/icon_512x512@2x.png" ]; then
        for size in 16 32 64 128 256 512; do
            sips -z $size $size "$ICONSET/icon_512x512@2x.png" \
                --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1 || true
        done
        # @2x variants
        for size in 16 32 128 256; do
            double=$((size * 2))
            cp "$ICONSET/icon_${double}x${double}.png" \
               "$ICONSET/icon_${size}x${size}@2x.png" 2>/dev/null || true
        done
        # Convert iconset to icns
        iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns" 2>/dev/null || true
    fi

    rm -rf "$ICONSET"

    if [ ! -f "$RESOURCES/AppIcon.icns" ]; then
        echo "    Warning: Could not generate icon (app will use default icon)"
    fi
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
echo "    ${APP_DIR}"
echo ""
echo "    To install:  cp -r \"${APP_DIR}\" /Applications/"
echo "    To run:      open \"${APP_DIR}\""
