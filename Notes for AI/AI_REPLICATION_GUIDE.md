# Glass Player Anime4K + Startup Crash Replication Guide

## Goal
Restore a fully working Glass Player that:
- launches without startup kill,
- runs Anime4K upscaling + denoising in-app,
- and remains stable across repeated launches.

This guide documents what was changed, why it was changed, and how to validate it.

## Primary Problems Found

### 1) App startup kill (`SIGKILL (Code Signature Invalid)`)
Symptoms:
- App terminated immediately at launch.
- Crash reports in `~/Library/Logs/DiagnosticReports/Glass Player-*.ips` showed:
  - `signal: SIGKILL (Code Signature Invalid)`
  - `namespace: CODESIGNING`
  - `indicator: Invalid Page`

Root cause:
- Debug/fast builds used `SKIP_SIGN=1`, but build steps still mutated Mach-O binaries (especially after `install_name_tool` and dylib rebinding).
- Unsafely skipping signing after mutation can produce launch-time code-sign invalid pages.

### 2) Signature drift after app use
Symptoms:
- App might verify once, then fail `codesign --verify --deep --strict` later.
- Errors included sealed resource mismatch / files added in app bundle resources.

Root cause:
- mpv runtime state (`watch_later`) was written into bundle resources path under `Contents/Resources/configs`.
- Any write inside signed bundle content can invalidate signature sealing over time.

### 3) Anime4K runtime correctness and reliability gaps
Symptoms:
- Presets loaded but could produce no visible effect or unstable output.
- Conditional passes (AutoDownscale prepasses) could fail activation flow.

Root causes:
- Compute grid dispatch could exceed valid shader bounds for translated kernels without explicit `gid` guards.
- Conditional WHEN-evaluated files could incorrectly fail whole stage.
- Per-frame semantic context (`NATIVE`, `OUTPUT`) needed stable dimensions across chain.

## What Solved Black/No-Difference Output (What Other Models Missed)

This is the high-signal part that converted Anime4K from "loads but looks unchanged" into real visible output.

### 1) Exact-grid compute dispatch was mandatory
Finding:
- Many translated Anime4K kernels did not include defensive bounds checks for `gid`.
- Rounded threadgroup dispatch can launch threads outside valid texture bounds and cause undefined writes/reads, often showing as black or unstable output.

Action:
- Switched runtime compute dispatch to exact-grid (`dispatchThreads`) using output width/height.

Why this was decisive:
- Removed out-of-range kernel execution and stabilized per-pass output.

### 2) Conditional files must be valid no-op, not hard failure
Finding:
- `AutoDownscalePre` and similar conditional stages may legitimately disable all passes via WHEN for a given frame/output ratio.
- Treating "zero enabled passes" as compile/activation failure collapsed parts of the pipeline and yielded no-effect behavior.

Action:
- Changed runtime logic so "no enabled passes" returns success and cleanly skips the stage.

Why this was decisive:
- Prevented conditional stage gating from breaking the full chain.

### 3) `NATIVE` and `OUTPUT` semantics had to be stable for the whole frame
Finding:
- WHEN logic depends on stable dimensions, not drifting per-file intermediate dimensions.
- If `OUTPUT`/`NATIVE` were reinterpreted from rolling intermediate textures, upscale passes could be wrongly skipped.

Action:
- Added per-frame context propagation (`nativeWidth/nativeHeight`, `targetOutputWidth/targetOutputHeight`) from orchestrator to runtime file pipelines before compile/encode.

Why this was decisive:
- Ensured ratio-based pass activation matched intended Anime4K behavior.

### 4) Recompile cache keys had to include frame semantic dimensions
Finding:
- Recompile checks based only on current input dimensions can keep stale pass activation when target/native semantic dimensions changed.

Action:
- Extended compile cache conditions to include native and target output dimensions.

Why this was decisive:
- Prevented stale pipeline reuse that looked like "preset applied but no visual difference".

### 5) Runtime pass binding needed metadata-accurate semantics
Finding:
- Some prior static mapping paths were too coarse for complex pass chains with `BINDS`/`HOOK`/`SAVE` semantics.

Action:
- Drove runtime pipeline from shader metadata and symbolic texture mapping.
- Ensured pass input/output textures aligned with parsed stage intent.

Why this was decisive:
- Fixed silent misbinding cases where compute ran but output did not reflect intended pass chain.

### 6) Validation had to be chain-aware, not just "app didn’t crash"
Finding:
- A running app is not proof of effective Anime4K output.

Action:
- Verified runtime logs for active chain behavior and expected conditional skips.
- Confirmed upscaled output dimensions and non-black output in test runs.

Why this was decisive:
- Distinguished true output correctness from "pipeline appears active" false positives.

## Files Changed

### `GlassPlayer/build.sh`
Key fixes:
- `SKIP_SIGN=1` no longer means "no signing".
- Always perform at least ad-hoc signing (`codesign -s -`) for local/debug build stability.
- Keep release signing flow for real identities (`Developer ID` / `Apple Development`) with runtime options and entitlements.
- Sign framework Mach-O binaries, then sign app bundle, then verify with deep strict validation.

Why this matters:
- Prevents launch-time code signature invalid kills on debug builds.

### `GlassPlayer/Sources/MPVController.swift`
Key fixes:
- Do not keep runtime mpv state in signed bundle resources.
- Create and use user-writable config/state path:
  - `~/Library/Application Support/Glass Player/mpv`
- Copy bundled `mpv.conf` into user path only if missing.
- Set:
  - `config-dir` to user path,
  - `watch-later-directory` to user path `watch_later`.
- Fall back to bundled config only if user path setup fails.

Why this matters:
- Prevents signature invalidation due to runtime writes in signed app bundle.

### `GlassPlayer/Sources/Anime4KRuntimePipeline.swift`
Key fixes:
- Use exact-grid compute dispatch (`dispatchThreads`) for translated kernels.
- Treat "no enabled passes" (WHEN false) as valid no-op, not hard failure.
- Add per-frame context updates for stable `NATIVE`/`OUTPUT` semantics.
- Include native/target dimensions in recompilation decisions.

Why this matters:
- Stabilizes pass activation logic and avoids out-of-range compute hazards.

### `GlassPlayer/Sources/Anime4KMetalPipeline.swift`
Key fixes:
- Per frame, propagate stable frame context (native + target output dims) before runtime file pipeline compile/encode.
- Use runtime file pipeline chaining for metadata-driven passes.

Why this matters:
- Keeps conditional logic and output sizing consistent across pass chain.

### `GlassPlayer/Sources/ViewLayer.swift`
Key fixes:
- Acquire drawable later in frame flow (after compute encode) to reduce drawable pressure.
- Keep Anime4K output path and verification hooks aligned to runtime pipeline behavior.

Why this matters:
- Reduces rendering pipeline contention and timing-related instability.

## Validation Workflow (What Passed)

### Build and signing validation
- Build command used:
  - `BUILD_PROFILE=baseline NO_INSTALL=1 SKIP_SIGN=1 CREATE_DMG=0 bash build.sh`
- Verification used:
  - `codesign --verify --deep --strict --verbose=2 "build/baseline/Glass Player.app"`
- Result:
  - Valid on disk / satisfies designated requirement.

### Installed app validation
- Installed fresh patched app:
  - `BUILD_PROFILE=baseline NO_INSTALL=0 SKIP_SIGN=1 CREATE_DMG=0 bash build.sh`
- Verified installed bundle:
  - `codesign --verify --deep --strict --verbose=2 "/Applications/Glass Player.app"`
- Result:
  - Valid on disk / satisfies designated requirement.

### Startup behavior validation
- Ran app with and without args and observed process alive after several seconds (no immediate kill).
- Confirmed no new `Code Signature Invalid` startup crash generated during final checks.

### Anime4K behavior validation
- During playback with `--anime4k "Mode A (Fast)"`, logs confirmed active runtime pipeline and non-trivial output path.
- Runtime logs showed expected no-op skips for conditional prepasses when WHEN evaluated false.
- Output texture logs confirmed real upscale path behavior (for example, 1080p source to 4K-class intermediate/output in tested runs).

## Quick Replication Checklist for Future AI

1. Confirm crash class first
- Inspect latest IPS for `CODESIGNING` vs shader/runtime crash.
- If `SIGKILL (Code Signature Invalid)`, prioritize signing/build and bundle write paths.

2. Ensure build script always signs mutated binaries
- Even in fast debug mode.
- Ad-hoc signing is acceptable for local launchability.

3. Keep runtime app state outside signed bundle
- mpv config/state in user Application Support.
- Explicitly set `watch-later-directory` there.

4. Keep Anime4K compute safe
- Use exact-grid dispatch when kernels lack bounds guards.
- Handle conditional files as valid no-op.
- Maintain stable frame context dimensions.

5. Validate with both
- `codesign --verify --deep --strict`
- real process launch tests (with and without video args).

## Cleanup Performed in This Pass

- Removed workspace build output folders:
  - root `build/`
  - `GlassPlayer/build/`
- Removed all `.air` byproduct files across workspace.
- Removed obsolete markdown plan/summary files from workspace root.
- Script set was intentionally pruned to keep only the scripts used in this fix workflow:
  - `GlassPlayer/Tools/preset_soak.zsh`
  - `Scripts/export_anime4kmetal_shaders.swift`

## Notes

- If startup still fails after these fixes, immediately re-check the newest IPS report before editing shaders.
- Signing failures and runtime pipeline bugs can coexist; debug order matters.
