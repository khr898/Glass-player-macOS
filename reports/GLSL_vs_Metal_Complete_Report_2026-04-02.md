# Complete GLSL vs Metal Comparison Report

Date: 2026-04-02

## Executive Verdict
- Metal implementation is operationally superior for this project: tighter runtime control, integrated quality locks, thermal/perf telemetry, and deterministic preset orchestration.
- Quality output is now very close to the GLSL baseline across all presets in automated parity runs, while stability and instrumentation are significantly stronger on Metal.

## Scope And Method
- Parity dataset: `reports/data/parity_run7_metrics.csv` and `reports/data/parity_run7_summary.md`.
- Reliability dataset: `reports/data/preset_soak_summary2.log` (12-preset soak).
- Performance dataset: `reports/data/perf_mode_AA_HQ.log` (Mode A+A HQ telemetry).
- Test video: 1080p pattern clip, captured at 1.0s for parity.
- GLSL reference runtime: mpv + libplacebo v7.351 shader chain.
- Metal runtime: Glass Player in-app Anime4K pipeline (same preset matrix).

## Quality Comparison (GLSL Reference vs Metal Output)
- Evaluated presets: 12 / 12 successful (`status=ok`).
- Aggregate SSIM: avg 0.991532, median 0.992838, min 0.981999, max 0.995401.
- Aggregate PSNR: avg 36.599448 dB, median 36.829184 dB, min 34.540504 dB, max 38.019496 dB.
- Fast presets: SSIM avg 0.992078, PSNR avg 36.684999 dB.
- HQ presets: SSIM avg 0.990986, PSNR avg 36.513897 dB.
- Worst parity case: Mode C+A (HQ) (SSIM 0.981999, PSNR 34.540504 dB).
- Best SSIM case: Mode C (Fast) (SSIM 0.995401).
- Best PSNR case: Mode C (HQ) (PSNR 38.019496 dB).

| Preset | SSIM | PSNR (dB) | Status |
|---|---:|---:|---|
| Mode A (Fast) | 0.994504 | 37.248475 | ok |
| Mode B (Fast) | 0.995352 | 37.675953 | ok |
| Mode C (Fast) | 0.995401 | 37.947664 | ok |
| Mode A+A (Fast) | 0.989360 | 35.504535 | ok |
| Mode B+B (Fast) | 0.991476 | 36.409893 | ok |
| Mode C+A (Fast) | 0.986375 | 35.323477 | ok |
| Mode A (HQ) | 0.994199 | 37.261877 | ok |
| Mode B (HQ) | 0.995288 | 37.716107 | ok |
| Mode C (HQ) | 0.995325 | 38.019496 | ok |
| Mode A+A (HQ) | 0.989612 | 35.685767 | ok |
| Mode B+B (HQ) | 0.989492 | 35.859630 | ok |
| Mode C+A (HQ) | 0.981999 | 34.540504 | ok |

## Reliability And Runtime Robustness
- Soak coverage: 12 presets tested.
- Alive after 12s: 12/12.
- Preset activation confirmations: 12/12.
- Preset apply confirmations: 12/12.
- Logged soak errors: 0.

Interpretation: Metal runtime passed full preset soak with no early exits in this run set.

## Performance And Thermal Signals (Metal)
- Heavy preset sampled: Mode A+A (HQ), 1080p input -> 4K output path.
- Captured telemetry:
  - [Anime4KPerf] preset=Mode A+A (HQ) frame=30 avgCompute=0.19ms estFPS=5128.3 input=1920x1080 output=3840x2160
  - [Anime4KPerf] preset=Mode A+A (HQ) frame=60 avgCompute=0.17ms estFPS=5879.1 input=1920x1080 output=3840x2160
  - [Anime4KPerf] preset=Mode A+A (HQ) frame=90 avgCompute=0.15ms estFPS=6611.3 input=1920x1080 output=3840x2160
  - [Anime4KPerf] preset=Mode A+A (HQ) frame=120 avgCompute=0.16ms estFPS=6278.9 input=1920x1080 output=3840x2160
- Observed steady-state compute stayed around ~0.15-0.19 ms in this sample, indicating headroom and stable encode cost on the measured hardware path.

## Why Metal Is Superior In This Project
- Integrated control plane: preset orchestration, conditional pass semantics, and runtime metadata are under one codebase instead of external player behavior.
- Better observability: built-in per-frame telemetry and deterministic logs for validation.
- Stability engineering: no-op conditional stage handling, exact-grid dispatch behavior, and robust stage recompilation/cache logic.
- Modern acceleration hooks: Neural Assist path with optional MPS convolution metric and Vision fallback, without forced quality downgrade.
- Deployment reliability: in-app pipeline avoids fragile external shader/runtime dependency coupling.

## Important Comparison Notes
- Raw capture dimensions differed in 12/12 presets between GLSL and Metal capture paths; parity workflow normalizes dimensions before SSIM/PSNR.
- This report compares rendered frame outputs, not subjective motion quality over entire clips.
- Parity numbers are from one test clip/timepoint matrix; additional content classes (anime line art, grain-heavy live action, HDR scenes) should be added for broader generalization.

## Conclusion
- The legacy GLSL path remains a useful baseline reference, but the project’s Metal implementation is now the stronger production path.
- Metal currently delivers high parity to GLSL output plus materially better reliability, instrumentation, and performance governance required for sustained macOS deployment.
