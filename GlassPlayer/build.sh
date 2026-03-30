#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$PROJECT_DIR")"
BUILD_PROFILE="${BUILD_PROFILE:-optimized}"
BUILD_ROOT_DIR="$PROJECT_DIR/build"
BUILD_DIR="$BUILD_ROOT_DIR/$BUILD_PROFILE"
APP_NAME="Glass Player"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE_NAME="GlassPlayer"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
NO_INSTALL="${NO_INSTALL:-0}"
SKIP_SIGN="${SKIP_SIGN:-0}"
CREATE_DMG="${CREATE_DMG:-1}"
DMG_DIR="$BUILD_DIR/dmg"
DMG_OUTPUT="$BUILD_DIR/GlassPlayer.dmg"

echo "=== Building Glass Player (Vendored) ==="
echo "Project: $PROJECT_DIR"
echo "Profile: $BUILD_PROFILE"

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Point the compiler explicitly to the local vendor folder
COMMON_SWIFTC_FLAGS=(
    -import-objc-header "$PROJECT_DIR/BridgingHeader.h"
    -I "$PROJECT_DIR/vendor/include"
    -L "$PROJECT_DIR/vendor/lib"
    -lmpv
    -framework Cocoa
    -framework Metal
    -framework OpenGL
    -framework QuartzCore
    -framework CoreVideo
    -framework IOKit
    -framework IOSurface
    -framework AVFoundation
    -framework CoreAudio
    -framework Accelerate
    -target arm64-apple-macos14.0
)

PROFILE_SWIFTC_FLAGS=()
if [[ "$BUILD_PROFILE" == "optimized" ]]; then
    PROFILE_SWIFTC_FLAGS=(
        -O -whole-module-optimization -lto=llvm-thin
        -Xcc -arch -Xcc arm64 -Xcc -O3 -Xcc -flto=thin
        -Xcc -fno-math-errno -Xcc -ffast-math -Xlinker -dead_strip
    )
else
    PROFILE_SWIFTC_FLAGS=(-O)
fi

# ─── Compile Swift Sources ─────────────────────────────────────────────
echo "=== Compiling Swift sources ==="
swiftc "${COMMON_SWIFTC_FLAGS[@]}" "${PROFILE_SWIFTC_FLAGS[@]}" -o "$BUILD_DIR/$EXECUTABLE_NAME" "$PROJECT_DIR/Sources/"*.swift

# ─── Create App Bundle ─────────────────────────────────────────────────
echo "=== Creating app bundle ==="
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$FRAMEWORKS_DIR"
mkdir -p "$APP_BUNDLE/Contents/Resources/configs"
mkdir -p "$APP_BUNDLE/Contents/Resources/shaders"

# Compile Metal Shaders
METAL_SOURCE="$PROJECT_DIR/Sources/Shaders.metal"
if [ -f "$METAL_SOURCE" ] && xcrun --find metal >/dev/null 2>&1; then
    xcrun metal -c "$METAL_SOURCE" -o "$BUILD_DIR/Shaders.air" -std=metal3.0 -target air64-apple-macos14.0 2>/dev/null && \
    xcrun metallib "$BUILD_DIR/Shaders.air" -o "$BUILD_DIR/default.metallib" 2>/dev/null && \
    cp "$BUILD_DIR/default.metallib" "$APP_BUNDLE/Contents/Resources/"
    rm -f "$BUILD_DIR/Shaders.air"
fi

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

[ -f "$ROOT_DIR/configs/mpv.conf" ] && cp "$ROOT_DIR/configs/mpv.conf" "$APP_BUNDLE/Contents/Resources/configs/"
[ -d "$ROOT_DIR/shaders" ] && cp -R "$ROOT_DIR/shaders/." "$APP_BUNDLE/Contents/Resources/shaders/"

# ─── Bundle Vendored Dylibs ───────────────────────────────────────────
echo "=== Bundling vendored dylibs ==="
cp -a "$PROJECT_DIR/vendor/lib/." "$FRAMEWORKS_DIR/"
echo "  Copied all pre-patched libraries from vendor folder."

# ─── Sign ──────────────────────────────────────────────────────────────
echo "=== Signing ==="
if [[ "$SKIP_SIGN" != "1" ]]; then
    SIGN_ID="-"
    ENTITLEMENTS="$PROJECT_DIR/GlassPlayer.entitlements"
    
    find "$FRAMEWORKS_DIR" -type f -print0 | while IFS= read -r -d '' lib; do
        if file "$lib" | grep -qE 'Mach-O|universal binary'; then
            codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" -s "$SIGN_ID" "$lib" 2>/dev/null || true
        fi
    done

    codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" --deep -s "$SIGN_ID" "$APP_BUNDLE"
fi

# ─── DMG ───────────────────────────────────────────────────────────────
if [[ "$CREATE_DMG" == "1" ]]; then
    echo "=== Creating DMG ==="
    rm -rf "$DMG_DIR" "$DMG_OUTPUT"
    mkdir -p "$DMG_DIR"
    cp -R "$APP_BUNDLE" "$DMG_DIR/"
    ln -s /Applications "$DMG_DIR/Applications"
    hdiutil create -volname "Glass Player" -srcfolder "$DMG_DIR" -ov -format UDZO -imagekey zlib-level=9 "$DMG_OUTPUT"
    rm -rf "$DMG_DIR"
fi

# ─── Install ───────────────────────────────────────────────────────────
if [[ "$NO_INSTALL" != "1" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    xattr -cr "/Applications/$APP_NAME.app" 2>/dev/null || true
    echo "=== Installed to /Applications/$APP_NAME.app ==="
fi

echo "=== Build complete! ==="