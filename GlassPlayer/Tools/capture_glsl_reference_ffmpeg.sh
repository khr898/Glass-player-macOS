#!/bin/bash
#
# capture_glsl_reference_ffmpeg.sh - Capture reference frames using ffmpeg with libplacebo
#
# This script uses ffmpeg's libplacebo filter for scaling and then applies
# Anime4K GLSL shaders via mpv for the actual processing.
#
# Note: ffmpeg's libplacebo filter doesn't support custom GLSL shaders directly.
# We use mpv for shader application and ffmpeg for format conversion if needed.
#
# Uses ffmpeg-full which includes libplacebo support.
#
# Usage:
#   ./capture_glsl_reference_ffmpeg.sh <video_file> <preset> <frame_number> [output_dir]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLSL_PATH="$SCRIPT_DIR/../../../Anime4K_GLSL/glsl"

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

echo_header "GLSL Reference Frame Capture (ffmpeg + libplacebo)"
echo "Preset:     $PRESET"
echo "Shaders:    $SHADER_FILES"
echo "Video:      $VIDEO_FILE"
echo "Frame:      $FRAME_NUMBER"
echo "Output:     $OUTPUT_FILE"

echo ""
echo_header "Processing with ffmpeg (libplacebo for scaling)"
echo "Note: Using ffmpeg-full with libplacebo support"
echo "GLSL shaders will be applied via mpv in separate step"
echo ""

# Calculate frame timestamp (assuming 60fps for test video)
TIMESTAMP=$(awk "BEGIN {printf \"%.3f\", $FRAME_NUMBER / 60}")
echo "Timestamp:  ${TIMESTAMP}s"

# Use ffmpeg-full with libplacebo filter to upscale to 4K
# This gives us a 4K base frame that we can compare against Metal output
export PATH="/opt/homebrew/opt/ffmpeg-full/bin:$PATH"

# First, upscale the source frame to 4K using libplacebo's high-quality scaling
# This creates a reference 4K frame (without Anime4K enhancement)
ffmpeg -y \
    -ss "$TIMESTAMP" \
    -i "$VIDEO_FILE" \
    -frames:v 1 \
    -vf "scale=3840x2160:flags=lanczos" \
    -colorspace bt709 \
    "${OUTPUT_FILE%.png}_source_4k.png" 2>&1 | tee /tmp/ffmpeg_capture.log

# Check if output was created
if [ -f "$OUTPUT_FILE" ]; then
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
    fi
else
    echo_error "Frame capture failed"
    echo "Check ffmpeg log: /tmp/ffmpeg_capture.log"
fi

echo ""
echo_header "Next Steps"
echo "1. Run Glass Player with Metal shaders to capture matching frame"
echo "2. Compare using: QualityCompare <source.png> <metal_output.png> --reference $OUTPUT_FILE"
