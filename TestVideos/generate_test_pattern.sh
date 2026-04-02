#!/bin/bash
# Generate a synthetic test pattern video for upscaling comparison

OUTPUT_DIR="/Users/user/Glass-player-macOS/TestVideos"
OUTPUT_FILE="$OUTPUT_DIR/test_pattern_1080p.mp4"

echo "Generating test pattern video..."

# Create a 10-second 1080p test pattern with geometric patterns
ffmpeg -y \
    -f lavfi -i testsrc2=size=1920x1080:rate=60 \
    -f lavfi -i sine=frequency=440:sample_rate=48000 \
    -vf "split=2[a][b]; \
         [a]drawbox=50:50:400:300:yellow@0.5:t=fill[pattern1]; \
         [b]drawgrid=width=1920:height=1080:color=cyan@0.3:thickness=2[pattern2]; \
         [pattern1][pattern2]overlay=960:0" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    -t 10 \
    "$OUTPUT_FILE" 2>&1

echo ""
echo "Test video created: $OUTPUT_FILE"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name -of csv=p=0 "$OUTPUT_FILE"
