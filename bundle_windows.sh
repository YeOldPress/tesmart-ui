#!/bin/bash
# bundle_windows.sh — Cross-compile TeSmart UI as a Windows x86_64 executable
set -euo pipefail

APP_NAME="TeSmart_UI"
EXECUTABLE="tesmart-ui"
VERSION="1.0.0"
TARGET="x86_64-windows-gnu"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/zig-out"
OUT_DIR="$BUILD_DIR/windows"

ensure_windows_icon() {
    if [ -f "$SCRIPT_DIR/AppIcon.ico" ]; then
        return 0
    fi

    if [ ! -f "$SCRIPT_DIR/AppIcon.png" ]; then
        echo "ERROR: AppIcon.png or AppIcon.ico is required for Windows bundle"
        exit 1
    fi

    if ! command -v magick >/dev/null 2>&1; then
        echo "ERROR: AppIcon.ico is missing and ImageMagick 'magick' is not available to generate it"
        exit 1
    fi

    echo "==> Generating AppIcon.ico from AppIcon.png..."
    magick "$SCRIPT_DIR/AppIcon.png" -background none -define icon:auto-resize=256,128,64,48,32,16 "$SCRIPT_DIR/AppIcon.ico"
}

ensure_windows_icon

# ── Step 1: Build ──
echo "==> Building ${EXECUTABLE} for Windows (${TARGET})..."
cd "$SCRIPT_DIR"
zig build -Dtarget="$TARGET" -Doptimize=ReleaseFast

EXE="$BUILD_DIR/bin/${EXECUTABLE}.exe"
if [ ! -f "$EXE" ]; then
    echo "ERROR: Build failed — $EXE not found"
    exit 1
fi

# ── Step 2: Assemble output directory ──
echo "==> Creating output directory..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cp "$EXE" "$OUT_DIR/${EXECUTABLE}.exe"

# Copy PDB if present (useful for debugging; omit to ship lean)
PDB="$BUILD_DIR/bin/${EXECUTABLE}.pdb"
if [ -f "$PDB" ]; then
    cp "$PDB" "$OUT_DIR/${EXECUTABLE}.pdb"
fi

# Copy AppIcon assets
if [ -f "$SCRIPT_DIR/AppIcon.png" ]; then
    cp "$SCRIPT_DIR/AppIcon.png" "$OUT_DIR/AppIcon.png"
fi
cp "$SCRIPT_DIR/AppIcon.ico" "$OUT_DIR/AppIcon.ico"

# ── Step 3: Summary ──
EXE_SIZE=$(du -sh "$OUT_DIR/${EXECUTABLE}.exe" | cut -f1)
echo ""
echo "==> Done! Windows build"
echo "    $OUT_DIR/${EXECUTABLE}.exe  ($EXE_SIZE)"
echo ""
echo "    To test in Wine:    wine \"$OUT_DIR/${EXECUTABLE}.exe\""
echo "    To test in Bottles: copy $OUT_DIR/ into your bottle and run ${EXECUTABLE}.exe"
