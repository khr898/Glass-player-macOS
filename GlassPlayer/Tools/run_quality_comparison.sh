#!/bin/bash
#
# run_quality_comparison.sh - Full quality comparison pipeline
#
# This script orchestrates the complete quality verification workflow:
# 1. Captures source frame from video
# 2. Captures Metal output frame (requires Glass Player running with capture enabled)
# 3. Captures GLSL reference frame using mpv
# 4. Runs SSIM/PSNR comparison
# 5. Generates JSON report with heatmap
#
# Usage:
#   ./run_quality_comparison.sh <video_file> <preset> <frame_number>
#
# Prerequisites:
#   - Build FrameCapture tool: swiftc -o build/FrameCapture Tools/FrameCapture/*.swift ...
#   - Build QualityCompare tool: swiftc -o build/QualityCompare Tools/QualityCompare/*.swift ...
#   - Glass Player app with frame capture enabled
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/../build"
OUTPUT_DIR="/tmp/glass-player-captures"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

echo_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

echo_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check arguments
if [ $# -lt 3 ]; then
    echo "Usage: $0 <video_file> <preset> <frame_number>"
    echo ""
    echo "Arguments:"
    echo "  video_file   Path to input video"
    echo "  preset       Anime4K preset (e.g., 'Mode A (Fast)')"
    echo "  frame_number Frame number to capture (e.g., 30)"
    echo ""
    echo "Presets:"
    echo "  Mode A (Fast), Mode B (Fast), Mode C (Fast)"
    echo "  Mode A (HQ), Mode B (HQ), Mode C (HQ)"
    echo "  Mode A+A (Fast), Mode B+B (Fast), Mode C+A (Fast)"
    echo "  Mode A+A (HQ), Mode B+B (HQ), Mode C+A (HQ)"
    exit 1
fi

VIDEO_FILE="$1"
PRESET="$2"
FRAME_NUMBER="$3"

# Validate video file
if [ ! -f "$VIDEO_FILE" ]; then
    echo_error "Video file not found: $VIDEO_FILE"
    exit 1
fi

# Check tools are built
if [ ! -x "$BUILD_DIR/QualityCompare" ]; then
    echo_warning "QualityCompare tool not found. Building..."
    cd "$SCRIPT_DIR/.."
    swiftc -o "$BUILD_DIR/QualityCompare" \
        Tools/QualityCompare/QualityCompare.swift \
        Tools/QualityCompare/QualityCompareTool.swift \
        -framework CoreGraphics \
        -framework ImageIO \
        -framework Accelerate || {
        echo_error "Failed to build QualityCompare tool"
        exit 1
    }
    echo_success "QualityCompare tool built"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo_header "Quality Comparison Pipeline"

echo "Configuration:"
echo "  Video:      $VIDEO_FILE"
echo "  Preset:     $PRESET"
echo "  Frame:      $FRAME_NUMBER"
echo "  Output Dir: $OUTPUT_DIR"
echo ""

# Step 1: Capture GLSL reference frame
echo_header "Step 1: Capture GLSL Reference Frame"

if [ -x "$SCRIPT_DIR/capture_glsl_reference.sh" ]; then
    "$SCRIPT_DIR/capture_glsl_reference.sh" "$VIDEO_FILE" "$PRESET" "$FRAME_NUMBER" "$OUTPUT_DIR" || {
        echo_warning "GLSL capture script failed or mpv not available"
        echo "Continuing without GLSL reference..."
    }
else
    echo_warning "GLSL capture script not found: $SCRIPT_DIR/capture_glsl_reference.sh"
fi

# Find GLSL reference file
GLSL_FILE=$(ls -t "$OUTPUT_DIR"/frame_*_glsl_*.png 2>/dev/null | head -1)
if [ -n "$GLSL_FILE" ]; then
    echo_success "GLSL reference captured: $GLSL_FILE"
else
    echo_warning "No GLSL reference found - will compare Metal vs source only"
fi

# Step 2: Instructions for Metal capture
echo_header "Step 2: Capture Metal Output Frame"

echo "To capture Metal output frames:"
echo ""
echo "1. Open Glass Player and load the video:"
echo "   open \"/Applications/Glass Player.app\" --args \"$VIDEO_FILE\""
echo ""
echo "2. Enable Anime4K with preset: $PRESET"
echo ""
echo "3. Enable frame capture in code (ViewLayer.swift):"
echo "   frameCaptureEnabled = true"
echo ""
echo "4. Play to frame $FRAME_NUMBER and pause"
echo ""
echo "Captured frames will be saved to: $OUTPUT_DIR"
echo ""
echo "Files created:"
echo "  - frame_0_source.png (before Anime4K)"
echo "  - frame_0_output.png (after Anime4K)"
echo ""
read -p "Press Enter when Metal frames are captured..."

# Find Metal output file
METAL_OUTPUT=$(ls -t "$OUTPUT_DIR"/frame_*_output_*.png 2>/dev/null | head -1)
METAL_SOURCE=$(ls -t "$OUTPUT_DIR"/frame_*_source_*.png 2>/dev/null | head -1)

if [ -z "$METAL_OUTPUT" ] || [ -z "$METAL_SOURCE" ]; then
    echo_error "Metal output or source file not found in $OUTPUT_DIR"
    exit 1
fi

echo_success "Metal frames found:"
echo "  Source: $METAL_SOURCE"
echo "  Output: $METAL_OUTPUT"

# Step 3: Run quality comparison
echo_header "Step 3: Running Quality Comparison"

REPORT_FILE="$OUTPUT_DIR/quality_report_$(date +%Y%m%d_%H%M%S).json"
HEATMAP_FILE="$OUTPUT_DIR/difference_heatmap.png"

COMPARISON_ARGS="$METAL_SOURCE $METAL_OUTPUT"
if [ -n "$GLSL_FILE" ]; then
    COMPARISON_ARGS="$COMPARISON_ARGS --reference $GLSL_FILE"
fi

"$BUILD_DIR/QualityCompare" $COMPARISON_ARGS \
    --output "$REPORT_FILE" \
    --heatmap "$HEATMAP_FILE" \
    --ssim 0.99 \
    --psnr 40

# Check results
echo_header "Results"

if [ -f "$REPORT_FILE" ]; then
    echo_success "Report generated: $REPORT_FILE"
    echo ""
    cat "$REPORT_FILE"
    echo ""

    # Extract pass/fail status
    if grep -q '"passed" : true' "$REPORT_FILE"; then
        echo_success "Quality check PASSED (SSIM > 0.99, PSNR > 40dB)"
    else
        echo_warning "Quality check below thresholds - review metrics"
    fi
else
    echo_error "Report generation failed"
fi

if [ -f "$HEATMAP_FILE" ]; then
    echo_success "Difference heatmap: $HEATMAP_FILE"
    echo "Open with: open $HEATMAP_FILE"
fi

echo ""
echo_header "Summary"
echo "Output files in: $OUTPUT_DIR"
echo ""
ls -la "$OUTPUT_DIR"/*.png "$OUTPUT_DIR"/*.json 2>/dev/null || true
