#!/bin/bash
# bundle_linux.sh — Build and package TeSmart UI as a Linux AppImage
set -euo pipefail

APP_NAME="TeSmart_UI"
EXECUTABLE="tesmart-ui"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/zig-out"
APPDIR="$BUILD_DIR/${APP_NAME}.AppDir"

# ── Step 1: Build ──
echo "==> Building ${EXECUTABLE}..."
cd "$SCRIPT_DIR"
zig build -Doptimize=ReleaseFast

if [ ! -f "$BUILD_DIR/bin/$EXECUTABLE" ]; then
    echo "ERROR: Build failed — $BUILD_DIR/bin/$EXECUTABLE not found"
    exit 1
fi

# ── Step 2: Get appimagetool ──
TOOL="$BUILD_DIR/appimagetool"
if [ ! -x "$TOOL" ]; then
    echo "==> Downloading appimagetool..."
    ARCH=$(uname -m)
    URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage"
    curl -fSL "$URL" -o "$TOOL"
    chmod +x "$TOOL"
fi

# ── Step 3: Create AppDir structure ──
echo "==> Creating AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# ── Step 4: Copy executable ──
cp "$BUILD_DIR/bin/$EXECUTABLE" "$APPDIR/usr/bin/$EXECUTABLE"
chmod +x "$APPDIR/usr/bin/$EXECUTABLE"

# ── Step 5: Bundle required shared libraries ──
echo "==> Bundling shared libraries..."
# Copy libraries that may not be present on all systems
# Skip glibc libs (libc, libm, libdl, libpthread, ld-linux) — these must come from the host
SKIP_LIBS="linux-vdso|ld-linux|libc\.so|libm\.so|libdl\.so|libpthread\.so|librt\.so|libstdc\+\+"
ldd "$BUILD_DIR/bin/$EXECUTABLE" | grep "=> /" | awk '{print $3}' | \
    grep -Ev "$SKIP_LIBS" | while read -r lib; do
    cp -n "$lib" "$APPDIR/usr/lib/" 2>/dev/null || true
done

# ── Step 6: Create desktop entry ──
cat > "$APPDIR/${EXECUTABLE}.desktop" << EOF
[Desktop Entry]
Type=Application
Name=TeSmart UI
Comment=TeSmart 16-Port HDMI KVM Switch Controller
Exec=${EXECUTABLE}
Icon=${EXECUTABLE}
Categories=Utility;HardwareSettings;
Terminal=false
StartupNotify=true
EOF

# Also place it in the standard location
cp "$APPDIR/${EXECUTABLE}.desktop" "$APPDIR/usr/share/applications/${EXECUTABLE}.desktop" 2>/dev/null || true

# ── Step 7: Create icon ──
# Use AppIcon.png if available, otherwise generate a simple one
if [ -f "$SCRIPT_DIR/AppIcon.png" ]; then
    cp "$SCRIPT_DIR/AppIcon.png" "$APPDIR/${EXECUTABLE}.png"
    cp "$SCRIPT_DIR/AppIcon.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${EXECUTABLE}.png"
    echo "    Using existing AppIcon.png"
else
    # Generate a simple 256x256 icon with Python
    python3 -c "
import struct, zlib

def make_png(w, h):
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            bx = min(x, w - 1 - x)
            by = min(y, h - 1 - y)
            border = min(bx, by)
            if border < w // 16:
                raw += bytes([30, 30, 35, 255])
            elif border < w // 12:
                raw += bytes([0, 120, 255, 255])
            else:
                raw += bytes([45, 45, 55, 255])
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')

with open('$APPDIR/${EXECUTABLE}.png', 'wb') as f:
    f.write(make_png(256, 256))
" 2>/dev/null || echo "    Warning: Could not generate icon"
    if [ -f "$APPDIR/${EXECUTABLE}.png" ]; then
        cp "$APPDIR/${EXECUTABLE}.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${EXECUTABLE}.png"
    fi
fi

# ── Step 8: Create AppRun ──
cat > "$APPDIR/AppRun" << 'APPRUN'
#!/bin/bash
SELF="$(readlink -f "$0")"
HERE="${SELF%/*}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/usr/bin/EXECUTABLE_PLACEHOLDER" "$@"
APPRUN
sed -i "s/EXECUTABLE_PLACEHOLDER/${EXECUTABLE}/" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"

# ── Step 9: Build AppImage ──
echo "==> Building AppImage..."
ARCH=$(uname -m)
OUTPUT="$BUILD_DIR/${APP_NAME}-${VERSION}-${ARCH}.AppImage"
rm -f "$OUTPUT"

# appimagetool needs ARCH env var
ARCH="$ARCH" "$TOOL" "$APPDIR" "$OUTPUT" 2>&1 || {
    # If FUSE is not available, try with --appimage-extract-and-run
    echo "    Retrying without FUSE..."
    ARCH="$ARCH" "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUTPUT" 2>&1
}

# ── Step 10: Clean up ──
rm -rf "$APPDIR"

# ── Done ──
if [ -f "$OUTPUT" ]; then
    chmod +x "$OUTPUT"
    APP_SIZE=$(du -sh "$OUTPUT" | cut -f1)
    echo ""
    echo "==> Done! ${APP_NAME} AppImage ($APP_SIZE)"
    echo "    ${OUTPUT}"
    echo ""
    echo "    To run:     chmod +x \"${OUTPUT}\" && ./${OUTPUT##*/}"
    echo "    To install: cp \"${OUTPUT}\" ~/.local/bin/"
else
    echo "ERROR: AppImage creation failed"
    exit 1
fi
