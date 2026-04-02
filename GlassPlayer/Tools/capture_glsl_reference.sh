#!/bin/bash
#
# capture_glsl_reference.sh - Capture reference frames using mpv with GLSL shaders
#
# This script renders frames using the original Anime4K GLSL shaders via mpv.
# The output is captured using mpv's screenshot functionality.
#
# CRITICAL: Requires libplacebo v7.351 for correct shader compilation.
# Do NOT use newer libplacebo versions - they produce different output.
#
# Usage:
#   ./capture_glsl_reference.sh <video_file> <preset> <frame_number> [output_dir]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLSL_PATH="/Users/user/Glass-player-macOS/Anime4K_GLSL/glsl"

# Default values
FRAME_NUMBER="${3:-30}"
OUTPUT_DIR="${4:-/tmp/glass-player-captures}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

echo_success() { echo -e "${GREEN}✓ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
echo_error() { echo -e "${RED}✗ $1${NC}"; }

# Parse preset to shader files
parse_preset() {
    local preset="$1"
    local shaders=""

    case "$preset" in
        *"Mode A (Fast)"*)
            shaders="Restore/Anime4K_Restore_CNN_M.glsl:Upscale/Anime4K_Upscale_CNN_x2_M.glsl"
            ;;
        *"Mode B (Fast)"*)
            shaders="Restore/Anime4K_Restore_CNN_Soft_M.glsl:Upscale/Anime4K_Upscale_CNN_x2_M.glsl"
            ;;
        *"Mode C (Fast)"*)
            shaders="Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_M.glsl"
            ;;
        *"Mode A (HQ)"*)
            shaders="Restore/Anime4K_Restore_CNN_VL.glsl:Upscale/Anime4K_Upscale_CNN_x2_VL.glsl"
            ;;
        *"Mode B (HQ)"*)
            shaders="Restore/Anime4K_Restore_CNN_Soft_VL.glsl:Upscale/Anime4K_Upscale_CNN_x2_VL.glsl"
            ;;
        *"Mode C (HQ)"*)
            shaders="Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl"
            ;;
        *)
            echo "Unknown preset: $preset"
            echo "Available presets:"
            echo "  Mode A (Fast), Mode B (Fast), Mode C (Fast)"
            echo "  Mode A (HQ), Mode B (HQ), Mode C (HQ)"
            exit 1
            ;;
    esac

    echo "$shaders"
}

# Check arguments
if [ $# -lt 3 ]; then
    echo "Usage: $0 <video_file> <preset> <frame_number> [output_dir]"
    echo ""
    echo "Arguments:"
    echo "  video_file   Path to input video"
    echo "  preset       Anime4K preset name"
    echo "  frame_number Frame number to capture (default: 30)"
    echo "  output_dir   Output directory (default: /tmp/glass-player-captures)"
    exit 1
fi

VIDEO_FILE="$1"
PRESET="$2"

# Validate video file exists
if [ ! -f "$VIDEO_FILE" ]; then
    echo_error "Video file not found: $VIDEO_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get shader files for preset
SHADER_FILES=$(parse_preset "$PRESET")
SAFE_PRESET=$(echo "$PRESET" | tr ' ' '_' | tr -d '()')
OUTPUT_FILE="$OUTPUT_DIR/frame_${FRAME_NUMBER}_glsl_${SAFE_PRESET}.png"

echo_header "GLSL Reference Frame Capture"
echo "Preset:     $PRESET"
echo "Shaders:    $SHADER_FILES"
echo "Video:      $VIDEO_FILE"
echo "Frame:      $FRAME_NUMBER"
echo "Output:     $OUTPUT_FILE"

# Calculate timestamp for frame (assuming 60fps for test video)
TIMESTAMP=$(awk "BEGIN {printf \"%.3f\", $FRAME_NUMBER / 60}")
echo "Timestamp:  ${TIMESTAMP}s"

# Build shader paths
SHADER_ARGS=""
IFS=':' read -ra SHADER_ARRAY <<< "$SHADER_FILES"
for shader in "${SHADER_ARRAY[@]}"; do
    shader_path="$GLSL_PATH/$shader"
    if [ -f "$shader_path" ]; then
        SHADER_ARGS="$SHADER_ARGS --glsl-shaders=$shader_path"
    else
        echo_warning "Shader not found: $shader_path"
    fi
done

echo ""
echo_header "Rendering with mpv (libplacebo backend)"
echo "Note: libplacebo v7.351 required for correct results"
echo ""

# Run mpv with keep-open and pause, then trigger screenshot
# Anime4K shaders upscale 2x internally (1080p -> 4K)
# mpv displays at window resolution but screenshot captures the rendered content
# Using --no-border and fixed window size for consistent capture
mpv --no-config \
    --gpu-api=vulkan \
    --start="$TIMESTAMP" \
    --keep-open=yes \
    --pause \
    --screenshot-format=png \
    --screenshot-directory="$OUTPUT_DIR" \
    --screenshot-sw=no \
    --no-border \
    --geometry=3840x2160 \
    --on-all-workspaces \
    $SHADER_ARGS \
    "$VIDEO_FILE" &

MPV_PID=$!
echo "mpv PID: $MPV_PID"

# Wait for mpv to load and pause
sleep 4

# Send 's' key to take screenshot via AppleScript
osascript << APPLESCRIPT
tell application "System Events"
    tell process "mpv"
        keystroke "s"
    end tell
end tell
APPLESCRIPT

echo "Screenshot command sent..."

# Wait for screenshot to be written
sleep 2

# Kill mpv
kill $MPV_PID 2>/dev/null || true

# Find the screenshot
LATEST_SCREENSHOT=$(ls -t "$OUTPUT_DIR"/mpv-shot*.png 2>/dev/null | head -1)

if [ -n "$LATEST_SCREENSHOT" ] && [ -f "$LATEST_SCREENSHOT" ]; then
    # Move to expected location
    mv "$LATEST_SCREENSHOT" "$OUTPUT_FILE"

    echo_success "GLSL reference captured: $OUTPUT_FILE"

    # Verify resolution
    RES_WIDTH=$(sips -g pixelWidth "$OUTPUT_FILE" 2>/dev/null | grep pixelWidth | awk '{print $2}')
    RES_HEIGHT=$(sips -g pixelHeight "$OUTPUT_FILE" 2>/dev/null | grep pixelHeight | awk '{print $2}')
    echo "Output resolution: ${RES_WIDTH}x${RES_HEIGHT}"

    # Check if upscaling worked (should be 2x for 2x upscale presets)
    if [ "$RES_WIDTH" -gt 1920 ] || [ "$RES_HEIGHT" -gt 1080 ]; then
        echo_success "Upscaling detected: ${RES_WIDTH}x${RES_HEIGHT}"
    else
        echo_warning "Output is same as source resolution - shaders may not be upscaling"
        echo "Note: mpv screenshot captures display output, not internal shader resolution"
    fi
else
    echo_error "Screenshot capture failed"
    echo "Try running mpv manually and press 's' to screenshot"
fi

echo ""
echo_header "Next Steps"
echo "1. Run Glass Player with Metal shaders to capture matching frame"
echo "2. Compare using: QualityCompare <source.png> <metal_output.png> --reference $OUTPUT_FILE"
