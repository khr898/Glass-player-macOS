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

echo "=== Building Glass Player (Native) ==="
echo "Project: $PROJECT_DIR"
echo "Root: $ROOT_DIR"
echo "Profile: $BUILD_PROFILE"

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

COMMON_SWIFTC_FLAGS=(
    -import-objc-header "$PROJECT_DIR/BridgingHeader.h"
    -I /opt/homebrew/include
    -L /opt/homebrew/lib
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
    -Xlinker -headerpad_max_install_names
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

# ─── Generate App Icon ─────────────────────────────────────────────────
echo "=== Generating app icon ==="
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

cat > "$BUILD_DIR/gen_icon.swift" << 'ICONSWIFT'
import Cocoa
let dir = CommandLine.arguments[1]
let pairs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in pairs {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
        let inset = s * 0.02
        let rr = r.insetBy(dx: inset, dy: inset)
        let cr = s * 0.22
        let p = NSBezierPath(roundedRect: rr, xRadius: cr, yRadius: cr)
        NSGradient(colors: [
            NSColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1),
            NSColor(red: 0.12, green: 0.10, blue: 0.22, alpha: 1),
        ])!.draw(in: p, angle: -45)
        NSColor.white.withAlphaComponent(0.12).setStroke()
        p.lineWidth = max(1, s * 0.008)
        p.stroke()
        let cy = s / 2, th = s * 0.34
        let tw = th * 0.866
        let leftX = s / 2 - tw / 3
        let rightX = s / 2 + 2 * tw / 3
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: leftX, y: cy + th / 2))
        tri.line(to: NSPoint(x: leftX, y: cy - th / 2))
        tri.line(to: NSPoint(x: rightX, y: cy))
        tri.close()
        NSColor.white.withAlphaComponent(0.9).setFill()
        tri.fill()
        return true
    }
    let tiff = img.tiffRepresentation!
    let bmp = NSBitmapImageRep(data: tiff)!
    let png = bmp.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
ICONSWIFT

swiftc -framework Cocoa -O -target arm64-apple-macos14.0 -o "$BUILD_DIR/gen_icon" "$BUILD_DIR/gen_icon.swift"
"$BUILD_DIR/gen_icon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$BUILD_DIR/gen_icon" "$BUILD_DIR/gen_icon.swift"

# ─── Bundle dylibs ────────────────────────────────────────────────────
echo "=== Bundling dylibs ==="

resolve_rpath() {
    local lib="$1"
    local source_binary="$2"
    
    if [[ "$lib" == *'*'* ]]; then
        local expanded=( $lib )
        for exp in "${expanded[@]}"; do
            if [ -f "$exp" ]; then
                echo "$exp"
                return
            fi
        done
    fi

    if [[ "$lib" == @rpath/* ]]; then
        local name="${lib#@rpath/}"
        for dir in /opt/homebrew/lib /usr/local/lib; do
            if [ -f "$dir/$name" ]; then
                echo "$dir/$name"
                return
            fi
        done
        local rpaths=($(otool -l "$source_binary" 2>/dev/null | grep -A2 LC_RPATH | grep path | awk '{print $2}'))
        for rpath in "${rpaths[@]}"; do
            local resolved="${rpath}/${name}"
            if [ -f "$resolved" ]; then
                echo "$resolved"
                return
            fi
        done
    elif [[ "$lib" == /opt/homebrew/* ]] || [[ "$lib" == /usr/local/* ]]; then
        echo "$lib"
        return
    elif [[ "$lib" != /* ]] && [[ "$lib" != @* ]]; then
        for dir in /opt/homebrew/lib /usr/local/lib; do
            if [ -f "$dir/$lib" ]; then
                echo "$dir/$lib"
                return
            fi
        done
    fi
    echo ""
}

bundle_lib() {
    local lib_path="$1"
    
    local real_path=$(realpath "$lib_path" 2>/dev/null || echo "$lib_path")
    local real_name=$(basename "$real_path")
    
    [ -f "$FRAMEWORKS_DIR/$real_name" ] && return
    [ ! -f "$real_path" ] && return
    
    echo "  Bundling: $real_name"
    cp "$real_path" "$FRAMEWORKS_DIR/$real_name"
    chmod 755 "$FRAMEWORKS_DIR/$real_name"
    install_name_tool -id "@executable_path/../Frameworks/$real_name" "$FRAMEWORKS_DIR/$real_name" 2>/dev/null || true
    
    local orig_name=$(basename "$lib_path")
    if [[ "$orig_name" != "$real_name" ]] && [ ! -f "$FRAMEWORKS_DIR/$orig_name" ]; then
        ln -sf "$real_name" "$FRAMEWORKS_DIR/$orig_name"
    fi
    
    process_deps "$FRAMEWORKS_DIR/$real_name"
}

process_deps() {
    local binary="$1"
    
    local is_main_exec=0
    if [[ "$binary" == *"/MacOS/"* ]]; then
        is_main_exec=1
    fi
    
    otool -L "$binary" 2>/dev/null | tail -n +2 | awk '{print $1}' | while read dep; do
        case "$dep" in
            /usr/lib/*|/System/*|@executable_path/*|@loader_path/*) continue ;;
        esac
        
        local original_dep="$dep"
        
        # 🚨 STRICT LOCK: Grab libplacebo straight from the repository vendor folder
        if [[ "$dep" == *"libplacebo."* ]]; then
            echo "  🔒 STRICT RULE: Hard-locking libplacebo to version 351."
            local strict_placebo="$ROOT_DIR/vendor/libplacebo.351.dylib"
            
            if [ ! -f "$strict_placebo" ]; then
                echo "  ❌ ERROR: Strict dependency $strict_placebo not found in repository!"
                exit 1
            fi
            
            dep="$strict_placebo"
        fi
        
        local resolved=$(resolve_rpath "$dep" "$binary")
        if [ -n "$resolved" ] && [ -f "$resolved" ]; then
            local resolved_real=$(realpath "$resolved" 2>/dev/null || echo "$resolved")
            local resolved_name=$(basename "$resolved_real")
            
            local new_path=""
            if [[ $is_main_exec == 1 ]]; then
                new_path="@executable_path/../Frameworks/$resolved_name"
            else
                new_path="@loader_path/$resolved_name"
            fi
            
            install_name_tool -change "$original_dep" "$new_path" "$binary" 2>/dev/null || \
                echo "  ⚠️ Warning: Failed to patch $original_dep in $(basename "$binary")"
            
            bundle_lib "$resolved"
        fi
    done
}

# Start with the executable
process_deps "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo "  Bundled $(ls -1 "$FRAMEWORKS_DIR" | wc -l | tr -d ' ') libraries"

# ─── Sign ──────────────────────────────────────────────────────────────
echo "=== Signing ==="
if [[ "$SKIP_SIGN" == "1" ]]; then
    echo "  Skipping codesign (SKIP_SIGN=1)"
else
    if [[ -n "$CODESIGN_IDENTITY" ]]; then
        SIGN_ID="$CODESIGN_IDENTITY"
    else
        DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep '"Developer ID Application' | head -1 \
            | sed 's/.*"\(Developer ID Application[^"]*\)".*/\1/')
        APPLE_DEV=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep '"Apple Development' | head -1 \
            | sed 's/.*"\(Apple Development[^"]*\)".*/\1/')
        if [[ -n "$DEV_ID" ]]; then
            SIGN_ID="$DEV_ID"
        elif [[ -n "$APPLE_DEV" ]]; then
            SIGN_ID="$APPLE_DEV"
        else
            SIGN_ID="-"
        fi
    fi

    ENTITLEMENTS="$PROJECT_DIR/GlassPlayer.entitlements"
    SIGNED_COUNT=0
    find "$FRAMEWORKS_DIR" -type f -print0 | while IFS= read -r -d '' lib; do
        if file "$lib" | grep -qE 'Mach-O|universal binary'; then
            codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" -s "$SIGN_ID" "$lib" 2>/dev/null || true
            SIGNED_COUNT=$((SIGNED_COUNT + 1))
        fi
    done

    codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" --deep -s "$SIGN_ID" "$APP_BUNDLE"
    codesign --verify --strict "$APP_BUNDLE" && echo "  ✓ Signature valid" || echo "  ✗ Signature verification failed"
fi

# ─── DMG (Simplified) ──────────────────────────────────────────────────
if [[ "$CREATE_DMG" == "1" ]]; then
    echo "=== Creating DMG ==="
    rm -rf "$DMG_DIR" "$DMG_OUTPUT"
    mkdir -p "$DMG_DIR"

    cp -R "$APP_BUNDLE" "$DMG_DIR/"
    ln -s /Applications "$DMG_DIR/Applications"

    hdiutil create -volname "Glass Player" \
        -srcfolder "$DMG_DIR" \
        -ov -format UDZO \
        -imagekey zlib-level=9 \
        "$DMG_OUTPUT"

    if [[ "$SKIP_SIGN" != "1" ]] && [[ -n "$SIGN_ID" ]] && [[ "$SIGN_ID" != "-" ]]; then
        codesign --force --timestamp -s "$SIGN_ID" "$DMG_OUTPUT" 2>/dev/null || true
    fi

    echo "  ✓ DMG created: $DMG_OUTPUT"
    rm -rf "$DMG_DIR"
fi

# ─── Install ───────────────────────────────────────────────────────────
if [[ "$NO_INSTALL" == "1" ]]; then
    echo "  Skipping install (NO_INSTALL=1)"
else
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    xattr -cr "/Applications/$APP_NAME.app" 2>/dev/null || true
    echo "=== Installed to /Applications/$APP_NAME.app ==="
fi

echo "=== Build complete! ==="