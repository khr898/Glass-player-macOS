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
)

PROFILE_SWIFTC_FLAGS=()
if [[ "$BUILD_PROFILE" == "optimized" ]]; then
    # ═══════════════════════════════════════════════════════════════
    # Phase 2: Global Compiler Tuning (Universal Apple Silicon)
    #
    # -arch arm64:            Clean native ARM64 slice
    # -O3 -flto=thin:         Aggressive optimization + Thin LTO
    # -dead_strip:            Remove unused symbols for lean binary
    # -fno-math-errno:        Enable vectorized math (no errno checks)
    # -ffast-math:            NEON/AMX-friendly FP (safe for media player)
    # -whole-module-optimization: Cross-file inlining for Swift
    # ═══════════════════════════════════════════════════════════════
    PROFILE_SWIFTC_FLAGS=(
        -O
        -whole-module-optimization
        -lto=llvm-thin
        -Xcc -arch
        -Xcc arm64
        -Xcc -O3
        -Xcc -flto=thin
        -Xcc -fno-math-errno
        -Xcc -ffast-math
        -Xlinker -dead_strip
    )
else
    PROFILE_SWIFTC_FLAGS=(
        -O
    )
fi

# ─── Compile Swift Sources ─────────────────────────────────────────────
echo "=== Compiling Swift sources ==="
swiftc \
    "${COMMON_SWIFTC_FLAGS[@]}" \
    "${PROFILE_SWIFTC_FLAGS[@]}" \
    -o "$BUILD_DIR/$EXECUTABLE_NAME" \
    "$PROJECT_DIR/Sources/"*.swift

echo "=== Compilation successful ==="

# ─── Create App Bundle ─────────────────────────────────────────────────
echo "=== Creating app bundle ==="
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$FRAMEWORKS_DIR"
mkdir -p "$APP_BUNDLE/Contents/Resources/configs"
mkdir -p "$APP_BUNDLE/Contents/Resources/shaders"

# ─── Compile Metal Shaders (MSL 3.0 → metallib, optional) ────────────
# If the Metal toolchain is available, pre-compile shaders for faster startup.
# If not, the app falls back to runtime compilation from embedded MSL source.
echo "=== Compiling Metal shaders ==="

# 1. Compile display shaders (Shaders.metal)
METAL_SOURCE="$PROJECT_DIR/Sources/Shaders.metal"
if [ -f "$METAL_SOURCE" ] && xcrun --find metal >/dev/null 2>&1; then
    xcrun metal -c "$METAL_SOURCE" \
        -o "$BUILD_DIR/Shaders.air" \
        -std=metal3.0 \
        -target air64-apple-macos14.0 2>/dev/null && \
    xcrun metallib "$BUILD_DIR/Shaders.air" \
        -o "$BUILD_DIR/default.metallib" 2>/dev/null && \
    cp "$BUILD_DIR/default.metallib" "$APP_BUNDLE/Contents/Resources/" && \
    echo "  Compiled display shaders → default.metallib" || \
    echo "  Metal toolchain unavailable – shaders will compile at runtime"
    rm -f "$BUILD_DIR/Shaders.air"
else
    echo "  Skipping display metallib (runtime MSL compilation will be used)"
fi

# 2. Compile Anime4K compute shaders (metal_compute/*.metal)
METAL_COMPUTE_DIR="$PROJECT_DIR/../metal_compute"
if [ -d "$METAL_COMPUTE_DIR" ] && xcrun --find metal >/dev/null 2>&1; then
    echo "  Compiling Anime4K compute shaders..."
    mkdir -p "$BUILD_DIR/anime4k_metallib"

    # Compile each .metal file to .air
    COMPILE_OK=true
    for metal_file in "$METAL_COMPUTE_DIR"/*.metal; do
        if [ -f "$metal_file" ]; then
            basename=$(basename "$metal_file" .metal)
            air_file="$BUILD_DIR/anime4k_metallib/${basename}.air"
            if xcrun metal -c "$metal_file" \
                -o "$air_file" \
                -std=metal3.0 \
                -target air64-apple-macos14.0 2>/dev/null; then
                echo "    ✓ $basename"
            else
                echo "    ✗ $basename (compilation failed)"
                COMPILE_OK=false
            fi
        fi
    done

    # Link all .air files into a single metallib
    if $COMPILE_OK && ls "$BUILD_DIR/anime4k_metallib"/*.air 1>/dev/null 2>&1; then
        if xcrun metallib "$BUILD_DIR/anime4k_metallib"/*.air \
            -o "$BUILD_DIR/Anime4K.metallib" 2>/dev/null; then
            cp "$BUILD_DIR/Anime4K.metallib" "$APP_BUNDLE/Contents/Resources/"
            echo "  ✓ Anime4K.metallib created"
        else
            echo "  ✗ Failed to link Anime4K.metallib"
        fi
    fi

    rm -rf "$BUILD_DIR/anime4k_metallib"
    rm -f "$BUILD_DIR/Shaders.air"
elif [ -d "$METAL_COMPUTE_DIR" ]; then
    echo "  Metal toolchain not found – Anime4K shaders will compile at runtime"
fi

# Copy executable
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy mpv.conf
if [ -f "$ROOT_DIR/configs/mpv.conf" ]; then
    cp "$ROOT_DIR/configs/mpv.conf" "$APP_BUNDLE/Contents/Resources/configs/"
    echo "  Copied mpv.conf"
fi

# Copy shaders
if [ -d "$ROOT_DIR/shaders" ]; then
    cp -R "$ROOT_DIR/shaders/." "$APP_BUNDLE/Contents/Resources/shaders/"
    echo "  Copied shaders"
fi

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
echo "  Generated AppIcon.icns"

# ─── Bundle dylibs ────────────────────────────────────────────────────
echo "=== Bundling dylibs ==="

resolve_rpath() {
    local lib="$1"
    local source_binary="$2"
    
    if [[ "$lib" == @rpath/* ]]; then
        local name="${lib#@rpath/}"
        # Try common rpath locations
        for dir in /opt/homebrew/lib /usr/local/lib; do
            if [ -f "$dir/$name" ]; then
                echo "$dir/$name"
                return
            fi
        done
        # Try to get rpaths from the source binary
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
    fi
    echo ""
}

bundle_lib() {
    local lib_path="$1"
    
    # Resolve symlinks
    local real_path=$(realpath "$lib_path" 2>/dev/null || echo "$lib_path")
    local real_name=$(basename "$real_path")
    
    # Skip if already bundled
    [ -f "$FRAMEWORKS_DIR/$real_name" ] && return
    
    # Skip if not found
    [ ! -f "$real_path" ] && return
    
    echo "  Bundling: $real_name"
    cp "$real_path" "$FRAMEWORKS_DIR/$real_name"
    chmod 755 "$FRAMEWORKS_DIR/$real_name"
    install_name_tool -id "@executable_path/../Frameworks/$real_name" "$FRAMEWORKS_DIR/$real_name" 2>/dev/null || true
    
    # Also copy the symlink name if different
    local orig_name=$(basename "$lib_path")
    if [[ "$orig_name" != "$real_name" ]] && [ ! -f "$FRAMEWORKS_DIR/$orig_name" ]; then
        ln -sf "$real_name" "$FRAMEWORKS_DIR/$orig_name"
    fi
    
    # Recursively bundle dependencies
    process_deps "$FRAMEWORKS_DIR/$real_name"
}

process_deps() {
    local binary="$1"
    
    otool -L "$binary" 2>/dev/null | tail -n +2 | awk '{print $1}' | while read dep; do
        # Skip system frameworks and already-fixed paths
        case "$dep" in
            /usr/lib/*|/System/*|@executable_path/*|@loader_path/*) continue ;;
        esac
        
        local resolved=$(resolve_rpath "$dep" "$binary")
        if [ -n "$resolved" ] && [ -f "$resolved" ]; then
            local resolved_real=$(realpath "$resolved" 2>/dev/null || echo "$resolved")
            local resolved_name=$(basename "$resolved_real")
            
            # Fix reference in binary
            install_name_tool -change "$dep" "@executable_path/../Frameworks/$resolved_name" "$binary" 2>/dev/null || true
            
            # Bundle the dependency
            bundle_lib "$resolved"
        fi
    done
}

# Start with the executable
process_deps "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "  Bundled $(ls -1 "$FRAMEWORKS_DIR" | wc -l | tr -d ' ') libraries"

# ─── Sign ──────────────────────────────────────────────────────────────
# Auto-detects your best signing identity:
#   1. CODESIGN_IDENTITY env var (if set)
#   2. "Developer ID Application" cert (Gatekeeper-trusted)
#   3. "Apple Development" cert (right-click → Open to trust)
#   4. Ad-hoc "-" (fallback)
# ───────────────────────────────────────────────────────────────────────
echo "=== Signing ==="
if [[ "$SKIP_SIGN" == "1" ]]; then
    echo "  Skipping codesign (SKIP_SIGN=1)"
else
    # Resolve best identity
    if [[ -n "$CODESIGN_IDENTITY" ]]; then
        SIGN_ID="$CODESIGN_IDENTITY"
        echo "  Using explicit identity: $SIGN_ID"
    else
        DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep '"Developer ID Application' | head -1 \
            | sed 's/.*"\(Developer ID Application[^"]*\)".*/\1/')
        APPLE_DEV=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep '"Apple Development' | head -1 \
            | sed 's/.*"\(Apple Development[^"]*\)".*/\1/')
        if [[ -n "$DEV_ID" ]]; then
            SIGN_ID="$DEV_ID"
            echo "  Using Developer ID: $SIGN_ID"
        elif [[ -n "$APPLE_DEV" ]]; then
            SIGN_ID="$APPLE_DEV"
            echo "  Using Apple Development: $SIGN_ID"
        else
            SIGN_ID="-"
            echo "  No certificate found, using ad-hoc signing"
        fi
    fi

    # Sign every Mach-O binary in Frameworks (dylib, so, and bare executables like Python)
    ENTITLEMENTS="$PROJECT_DIR/GlassPlayer.entitlements"
    echo "  Signing bundled frameworks..."
    SIGNED_COUNT=0
    find "$FRAMEWORKS_DIR" -type f -print0 | while IFS= read -r -d '' lib; do
        # Only sign Mach-O binaries (skip symlinks, text files, etc.)
        if file "$lib" | grep -qE 'Mach-O|universal binary'; then
            codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" -s "$SIGN_ID" "$lib" 2>/dev/null || true
            SIGNED_COUNT=$((SIGNED_COUNT + 1))
        fi
    done
    echo "  Signed framework binaries"

    # Sign the main app bundle (must come after all subcomponents)
    echo "  Signing app bundle..."
    codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" --deep -s "$SIGN_ID" "$APP_BUNDLE"
    codesign --verify --strict "$APP_BUNDLE" && echo "  ✓ Signature valid" || echo "  ✗ Signature verification failed"
fi
echo "=== Signed ==="

# ─── DMG ───────────────────────────────────────────────────────────────
# Creates a distributable DMG with:
#   - Drag-to-Applications layout
#   - "Install Glass Player" helper script that strips quarantine
#   - README for manual workaround
# ───────────────────────────────────────────────────────────────────────
if [[ "$CREATE_DMG" == "1" ]]; then
    echo "=== Creating DMG ==="
    rm -rf "$DMG_DIR" "$DMG_OUTPUT"
    mkdir -p "$DMG_DIR"

    # Copy app bundle into DMG staging
    cp -R "$APP_BUNDLE" "$DMG_DIR/"

    # Create Applications symlink for drag-and-drop
    ln -s /Applications "$DMG_DIR/Applications"

    # Create the quarantine-strip install helper
    cat > "$DMG_DIR/Install Glass Player.command" <<'INSTALLSCRIPT'
#!/bin/zsh
# ─────────────────────────────────────────────────────────
# Glass Player Installer
# Copies the app to /Applications and removes the
# quarantine flag so macOS doesn't block it.
# ─────────────────────────────────────────────────────────
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/Glass Player.app"

if [ ! -d "$APP" ]; then
    echo "❌ Glass Player.app not found next to this script."
    exit 1
fi

echo "Installing Glass Player..."
rm -rf "/Applications/Glass Player.app"
cp -R "$APP" "/Applications/Glass Player.app"

# Strip quarantine flag so Gatekeeper won't block it
xattr -cr "/Applications/Glass Player.app" 2>/dev/null || true

echo "✅ Glass Player installed to /Applications"
echo "   You can now open it from Launchpad or Spotlight."
echo ""
echo "Press any key to close..."
read -k 1
INSTALLSCRIPT
    chmod +x "$DMG_DIR/Install Glass Player.command"

    # Create README
    cat > "$DMG_DIR/README.txt" <<'README'
Glass Player — Installation
═══════════════════════════

Option 1 (Recommended):
  Double-click "Install Glass Player.command"
  It copies the app to /Applications and clears the quarantine flag.

Option 2 (Manual):
  1. Drag "Glass Player.app" to the Applications folder
  2. Open Terminal and run:
     xattr -cr "/Applications/Glass Player.app"
  3. Open Glass Player normally

Option 3 (No Terminal):
  1. Drag "Glass Player.app" to Applications
  2. Right-click the app → Open → click Open in the dialog
  3. After the first launch, it opens normally

README

    # Build DMG
    hdiutil create -volname "Glass Player" \
        -srcfolder "$DMG_DIR" \
        -ov -format UDZO \
        -imagekey zlib-level=9 \
        "$DMG_OUTPUT"

    # Sign the DMG itself
    if [[ "$SKIP_SIGN" != "1" ]] && [[ -n "$SIGN_ID" ]] && [[ "$SIGN_ID" != "-" ]]; then
        codesign --force --timestamp -s "$SIGN_ID" "$DMG_OUTPUT" 2>/dev/null || true
    fi

    DMG_SIZE=$(du -sh "$DMG_OUTPUT" | cut -f1)
    echo "  ✓ DMG created: $DMG_OUTPUT ($DMG_SIZE)"

    # Clean up staging directory
    rm -rf "$DMG_DIR"

    echo "=== DMG Ready ==="
else
    echo "  Skipping DMG (CREATE_DMG=0)"
fi

# ─── Install ───────────────────────────────────────────────────────────
echo "=== Installing ==="
if [[ "$NO_INSTALL" == "1" ]]; then
    echo "  Skipping install (NO_INSTALL=1)"
else
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    xattr -cr "/Applications/$APP_NAME.app" 2>/dev/null || true
    echo "=== Installed to /Applications/$APP_NAME.app ==="
fi

echo ""
echo "=== Build complete! ==="
echo "Bundle: $APP_BUNDLE"
if [[ "$CREATE_DMG" == "1" ]]; then
    echo "DMG:    $DMG_OUTPUT"
fi
if [[ "$NO_INSTALL" != "1" ]]; then
    echo "Run: open '/Applications/$APP_NAME.app'"
    echo "Or:  open '/Applications/$APP_NAME.app' --args /path/to/video.mp4"
fi
