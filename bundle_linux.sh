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
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/metainfo"

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

# Improve compatibility with desktop category validators
sed -i 's|Categories=Utility;HardwareSettings;|Categories=Settings;HardwareSettings;|' "$APPDIR/${EXECUTABLE}.desktop"
cp "$APPDIR/${EXECUTABLE}.desktop" "$APPDIR/usr/share/applications/${EXECUTABLE}.desktop"

# ── Step 6b: Add AppStream metadata ──
cat > "$APPDIR/usr/share/metainfo/com.tesmart.ui.appdata.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
    <id>com.tesmart.ui</id>
    <name>TeSmart UI</name>
    <summary>Controller for TeSmart 16-port HDMI KVM switches</summary>
    <developer id="com.tesmart">
        <name>TeSmart UI</name>
    </developer>
    <metadata_license>CC0-1.0</metadata_license>
    <project_license>MIT</project_license>
    <launchable type="desktop-id">${EXECUTABLE}.desktop</launchable>
    <url type="homepage">https://github.com/</url>
    <description>
        <p>
            TeSmart UI provides a desktop control panel and tray interface for
            TeSmart 16-port HDMI KVM switches.
        </p>
    </description>
    <categories>
        <category>Utility</category>
        <category>Settings</category>
        <category>HardwareSettings</category>
    </categories>
</component>
EOF

# ── Step 7: Create icon ──
if [ ! -f "$SCRIPT_DIR/AppIcon.png" ]; then
    echo "ERROR: AppIcon.png is required for Linux bundle"
    exit 1
fi
cp "$SCRIPT_DIR/AppIcon.png" "$APPDIR/${EXECUTABLE}.png"
cp "$SCRIPT_DIR/AppIcon.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${EXECUTABLE}.png"
echo "    Using AppIcon.png"

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
