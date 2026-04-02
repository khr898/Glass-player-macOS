#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
GLSL_ROOT="$ROOT_DIR/Anime4K_GLSL/glsl"

APP_BIN="${APP_BIN:-$PROJECT_DIR/build/baseline/Glass Player.app/Contents/MacOS/Glass Player}"
VIDEO="${VIDEO:-$ROOT_DIR/TestVideos/test_pattern_1080p.mp4}"
OUT_DIR="${OUT_DIR:-/tmp/glass_parity}"
CAPTURE_TIME="${CAPTURE_TIME:-1.0}"
CAPTURE_SETTLE_MS="${CAPTURE_SETTLE_MS:-900}"
REQUIRED_LIBPLACEBO_PREFIX="${REQUIRED_LIBPLACEBO_PREFIX:-v7.351}"
USE_NEURAL_ASSIST="${USE_NEURAL_ASSIST:-1}"

mkdir -p "$OUT_DIR" "$OUT_DIR/glsl" "$OUT_DIR/metal" "$OUT_DIR/diff" "$OUT_DIR/logs"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd"
    exit 1
  fi
}

require_cmd mpv
require_cmd ffmpeg
require_cmd ffprobe
require_cmd awk
require_cmd sed

if command -v socat >/dev/null 2>&1; then
  MPV_IPC_TOOL="socat"
elif command -v nc >/dev/null 2>&1; then
  MPV_IPC_TOOL="nc"
else
  echo "ERROR: need socat or nc for mpv IPC control"
  exit 1
fi

MPV_IPC_NC_ARGS=(-U)
if [[ "$MPV_IPC_TOOL" == "nc" ]]; then
  if nc -h 2>&1 | grep -q -- " -N "; then
    MPV_IPC_NC_ARGS=(-N -U)
  else
    MPV_IPC_NC_ARGS=(-w 1 -U)
  fi
fi

send_mpv_ipc() {
  local socket="$1"
  local json_payload="$2"

  if [[ "$MPV_IPC_TOOL" == "socat" ]]; then
    printf '%s\n' "$json_payload" | socat - "$socket" >/dev/null 2>&1 || true
  else
    printf '%s\n' "$json_payload" | nc "${MPV_IPC_NC_ARGS[@]}" "$socket" >/dev/null 2>&1 || true
  fi
}

repair_mpv_signature_if_needed() {
  local mpv_bin
  mpv_bin="$(command -v mpv)"
  if mpv --version >/dev/null 2>&1; then
    return 0
  fi

  local real_mpv
  real_mpv="$(realpath "$mpv_bin")"
  if codesign -vvv "$real_mpv" 2>&1 | grep -qi "invalid signature"; then
    echo "[parity] mpv signature invalid after local patch, applying ad-hoc signature"
    codesign --force --sign - "$real_mpv"
  fi

  if ! mpv --version >/dev/null 2>&1; then
    echo "ERROR: mpv is still not executable after signature repair"
    exit 1
  fi
}

verify_libplacebo_version() {
  local line version
  line="$(mpv --version | awk -F': ' '/libplacebo version/ {print $2; exit}')"
  version="$line"
  if [[ -z "$version" ]]; then
    echo "ERROR: unable to read libplacebo version from mpv --version"
    exit 1
  fi
  if [[ "$version" != ${REQUIRED_LIBPLACEBO_PREFIX}* ]]; then
    echo "ERROR: libplacebo version mismatch. Required prefix: ${REQUIRED_LIBPLACEBO_PREFIX}, detected: ${version}"
    echo "Refusing to continue because newer libplacebo is known-bad for Anime4K quality in this workflow."
    exit 1
  fi
  echo "[parity] Using libplacebo ${version}"
}

ensure_app_build() {
  if [[ -x "$APP_BIN" ]]; then
    return 0
  fi

  echo "[parity] Building baseline app (missing executable)"
  (
    cd "$PROJECT_DIR"
    BUILD_PROFILE=baseline NO_INSTALL=1 CREATE_DMG=0 SKIP_SIGN=1 bash build.sh >"$OUT_DIR/logs/build.log" 2>&1
  )

  if [[ ! -x "$APP_BIN" ]]; then
    echo "ERROR: failed to build app. See $OUT_DIR/logs/build.log"
    exit 1
  fi
}

chain_for_preset() {
  local p="$1"
  local r="$GLSL_ROOT/Restore"
  local u="$GLSL_ROOT/Upscale"
  local ud="$GLSL_ROOT/Upscale+Denoise"

  case "$p" in
    "Mode A (Fast)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$r/Anime4K_Restore_CNN_M.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_S.glsl"
      ;;
    "Mode B (Fast)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$r/Anime4K_Restore_CNN_Soft_M.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_S.glsl"
      ;;
    "Mode C (Fast)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$ud/Anime4K_Upscale_Denoise_CNN_x2_M.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_S.glsl"
      ;;
    "Mode A+A (Fast)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$r/Anime4K_Restore_CNN_M.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl:$r/Anime4K_Restore_CNN_S.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_S.glsl"
      ;;
    "Mode B+B (Fast)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$r/Anime4K_Restore_CNN_Soft_M.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$r/Anime4K_Restore_CNN_Soft_S.glsl:$u/Anime4K_Upscale_CNN_x2_S.glsl"
      ;;
    "Mode C+A (Fast)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$ud/Anime4K_Upscale_Denoise_CNN_x2_M.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$r/Anime4K_Restore_CNN_S.glsl:$u/Anime4K_Upscale_CNN_x2_S.glsl"
      ;;
    "Mode A (HQ)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$r/Anime4K_Restore_CNN_VL.glsl:$u/Anime4K_Upscale_CNN_x2_VL.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl"
      ;;
    "Mode B (HQ)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$r/Anime4K_Restore_CNN_Soft_VL.glsl:$u/Anime4K_Upscale_CNN_x2_VL.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl"
      ;;
    "Mode C (HQ)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$ud/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl"
      ;;
    "Mode A+A (HQ)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$r/Anime4K_Restore_CNN_VL.glsl:$u/Anime4K_Upscale_CNN_x2_VL.glsl:$r/Anime4K_Restore_CNN_M.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl"
      ;;
    "Mode B+B (HQ)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$r/Anime4K_Restore_CNN_Soft_VL.glsl:$u/Anime4K_Upscale_CNN_x2_VL.glsl:$r/Anime4K_Restore_CNN_Soft_M.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl"
      ;;
    "Mode C+A (HQ)")
      echo "$r/Anime4K_Clamp_Highlights.glsl:$ud/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl:$u/Anime4K_AutoDownscalePre_x2.glsl:$u/Anime4K_AutoDownscalePre_x4.glsl:$r/Anime4K_Restore_CNN_M.glsl:$u/Anime4K_Upscale_CNN_x2_M.glsl"
      ;;
    *)
      return 1
      ;;
  esac
}

capture_glsl_frame() {
  local preset="$1"
  local out_png="$2"
  local safe="$3"
  local chain socket log pid

  chain="$(chain_for_preset "$preset")" || {
    echo "ERROR: unsupported preset for GLSL chain mapping: $preset"
    return 1
  }

  socket="$OUT_DIR/logs/mpv_${safe}.sock"
  log="$OUT_DIR/logs/glsl_${safe}.log"

  rm -f "$socket" "$log" "$out_png"

  mpv \
    --no-config \
    --vo=gpu-next \
    --pause \
    --keep-open=yes \
    --input-ipc-server="$socket" \
    --glsl-shaders="$chain" \
    --msg-level=all=warn \
    --osd-level=0 \
    "$VIDEO" >"$log" 2>&1 &
  pid=$!

  local ready=0
  for _ in {1..120}; do
    if [[ -S "$socket" ]]; then
      ready=1
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.05
  done

  if [[ "$ready" -ne 1 ]]; then
    wait "$pid" >/dev/null 2>&1 || true
    echo "ERROR: mpv IPC socket did not appear for $preset"
    tail -n 80 "$log" || true
    return 1
  fi

  send_mpv_ipc "$socket" '{ "command": ["set", "pause", "yes"] }'
  send_mpv_ipc "$socket" "{ \"command\": [\"seek\", ${CAPTURE_TIME}, \"absolute+exact\"] }"
  sleep 0.6
  send_mpv_ipc "$socket" "{ \"command\": [\"screenshot-to-file\", \"${out_png}\", \"video\"] }"
  sleep 0.7
  send_mpv_ipc "$socket" '{ "command": ["quit"] }'

  wait "$pid" >/dev/null 2>&1 || true

  if [[ ! -f "$out_png" ]]; then
    echo "ERROR: GLSL capture missing for $preset"
    tail -n 120 "$log" || true
    return 1
  fi
}

capture_metal_frame() {
  local preset="$1"
  local out_png="$2"
  local safe="$3"
  local log="$OUT_DIR/logs/metal_${safe}.log"
  local neural_args=()

  rm -f "$out_png" "$log"

  if [[ "$USE_NEURAL_ASSIST" == "1" ]]; then
    neural_args=(--neural-assist)
  fi

  GLASS_THERMAL_GUARD=0 "$APP_BIN" \
    --anime4k "$preset" \
    "${neural_args[@]}" \
    --capture-time "$CAPTURE_TIME" \
    --capture-settle-ms "$CAPTURE_SETTLE_MS" \
    --capture-out "$out_png" \
    "$VIDEO" >"$log" 2>&1 || true

  if [[ ! -f "$out_png" ]]; then
    echo "ERROR: Metal capture missing for $preset"
    tail -n 120 "$log" || true
    return 1
  fi
}

compute_metrics() {
  local ref_png="$1"
  local test_png="$2"
  local norm_test_png="$3"
  local ssim_line psnr_line ssim psnr

  ssim_line="$(ffmpeg -hide_banner -nostats -i "$ref_png" -i "$norm_test_png" -lavfi ssim -f null - 2>&1 | grep -E 'All:' | tail -n1 || true)"
  psnr_line="$(ffmpeg -hide_banner -nostats -i "$ref_png" -i "$norm_test_png" -lavfi psnr -f null - 2>&1 | grep -E 'average:' | tail -n1 || true)"

  ssim="$(echo "$ssim_line" | sed -n 's/.*All:\([0-9.]*\).*/\1/p')"
  psnr="$(echo "$psnr_line" | sed -n 's/.*average:\([0-9.]*\).*/\1/p')"

  [[ -n "$ssim" ]] || ssim="nan"
  [[ -n "$psnr" ]] || psnr="nan"

  echo "$ssim,$psnr"
}

make_diff_image() {
  local ref_png="$1"
  local norm_test_png="$2"
  local diff_png="$3"
  ffmpeg -hide_banner -loglevel error -y -i "$ref_png" -i "$norm_test_png" \
    -filter_complex "[0:v][1:v]blend=all_mode=difference" \
    -frames:v 1 "$diff_png"
}

image_dimensions() {
  local image="$1"
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$image"
}

normalize_for_metrics() {
  local ref_png="$1"
  local test_png="$2"
  local out_png="$3"
  local ref_dims test_dims

  ref_dims="$(image_dimensions "$ref_png")"
  test_dims="$(image_dimensions "$test_png")"

  if [[ "$ref_dims" == "$test_dims" ]]; then
    cp "$test_png" "$out_png"
    return 0
  fi

  local ref_w="${ref_dims%x*}"
  local ref_h="${ref_dims#*x}"

  ffmpeg -hide_banner -loglevel error -y \
    -i "$test_png" \
    -vf "scale=${ref_w}:${ref_h}:flags=lanczos" \
    -frames:v 1 "$out_png"
}

repair_mpv_signature_if_needed
verify_libplacebo_version
ensure_app_build

if [[ ! -f "$VIDEO" ]]; then
  echo "ERROR: video file not found: $VIDEO"
  exit 1
fi

presets=(
  "Mode A (Fast)"
  "Mode B (Fast)"
  "Mode C (Fast)"
  "Mode A+A (Fast)"
  "Mode B+B (Fast)"
  "Mode C+A (Fast)"
  "Mode A (HQ)"
  "Mode B (HQ)"
  "Mode C (HQ)"
  "Mode A+A (HQ)"
  "Mode B+B (HQ)"
  "Mode C+A (HQ)"
)

CSV="$OUT_DIR/parity_metrics.csv"
SUMMARY="$OUT_DIR/parity_summary.md"

echo "preset,ssim,psnr,glsl_png,metal_png,diff_png,status" > "$CSV"

for preset in "${presets[@]}"; do
  safe="${preset//[^A-Za-z0-9]/_}"
  glsl_png="$OUT_DIR/glsl/${safe}.png"
  metal_png="$OUT_DIR/metal/${safe}.png"
  metal_norm_png="$OUT_DIR/metal/${safe}.metrics.png"
  diff_png="$OUT_DIR/diff/${safe}.png"

  echo "[parity] Running $preset"

  result_status="ok"
  ssim="nan"
  psnr="nan"

  if ! capture_glsl_frame "$preset" "$glsl_png" "$safe"; then
    result_status="glsl_capture_failed"
  elif ! capture_metal_frame "$preset" "$metal_png" "$safe"; then
    result_status="metal_capture_failed"
  elif ! normalize_for_metrics "$glsl_png" "$metal_png" "$metal_norm_png"; then
    result_status="metric_normalization_failed"
  else
    metrics="$(compute_metrics "$glsl_png" "$metal_png" "$metal_norm_png")"
    ssim="${metrics%%,*}"
    psnr="${metrics##*,}"
    make_diff_image "$glsl_png" "$metal_norm_png" "$diff_png" || true
  fi

  printf '"%s",%s,%s,"%s","%s","%s",%s\n' \
    "$preset" "$ssim" "$psnr" "$glsl_png" "$metal_png" "$diff_png" "$result_status" >> "$CSV"
done

{
  echo "# Anime4K Parity Summary"
  echo
  echo "- Required libplacebo: $REQUIRED_LIBPLACEBO_PREFIX"
  echo "- Capture time: $CAPTURE_TIME"
  echo "- Metal settle delay (ms): $CAPTURE_SETTLE_MS"
  echo "- Video: $VIDEO"
  echo "- Metrics CSV: $CSV"
  echo
  echo "| Preset | SSIM | PSNR | Status |"
  echo "|---|---:|---:|---|"

  tail -n +2 "$CSV" | while IFS=',' read -r preset ssim psnr _ _ _ result_status; do
    preset="${preset%\"}"
    preset="${preset#\"}"
    echo "| $preset | $ssim | $psnr | $result_status |"
  done
} > "$SUMMARY"

echo "[parity] Complete"
echo "[parity] Summary: $SUMMARY"
echo "[parity] CSV: $CSV"
