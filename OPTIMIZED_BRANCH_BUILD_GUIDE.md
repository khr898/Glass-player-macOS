# Glass Player — `optimized` Branch Build Guide

**Executor:** Gemini Flash 3.5
**Repository:** `https://github.com/khr898/Glass-player-macOS`
**Target branch:** `optimized` (new, forked from `main`)
**Source of truth for this guide:** the actual current contents of `main` and `scarlet` as of authoring. File paths, symbol names, and line references below are real — do not invent alternatives.

---

## 0. READ THIS FIRST — Non-Negotiable Rules

These rules override any natural-language ambiguity later in the document. If a later step seems to conflict with a rule here, the rule here wins.

1. **All work happens on the `optimized` branch only.** Never commit to `main` or `scarlet`. Verify with `git branch --show-current` before every commit.
2. **Pure Anime4K only.** Never copy `ArtCNN`, `CoreML`, `MoltenVK`, `Vulkan`, or any ML-upscaling code/shaders/presets from `scarlet`. The complete exclusion list is in §2.3.
3. **The app must stay fully self-contained.** No runtime download, no reliance on a user-installed `mpv`, no absolute paths, no environment-variable lookups for required assets. Everything required to run ships inside the bundle/installer.
4. **Do not break relative asset paths.** macOS resolves shaders from `Contents/Resources/shaders`; Windows embeds them via `windows/resources.qrc` using `../shaders/...`. The root `shaders/` folder must stay at repo root. (See §1.)
5. **Three of the original requests are based on false premises about the repo.** They are corrected in §1.2. Do not attempt the non-existent work — it will produce broken or no-op diffs.
6. **Make minimal, surgical diffs.** Do not reformat files, do not re-order unrelated code, do not "modernize" untouched functions. Smaller diffs = fewer regressions.
7. **After every file edit, the project must still build.** Build instructions are in §9. If a change breaks the build, fix or revert it before continuing.

---

## 1. Repository Reality (verified)

### 1.1 Current branch layout

Both `main` and `scarlet` **already** use the layout described in the request: common content (`configs/`, `shaders/`) at the repo root, with `macOS/` and `windows/` folders for the two ports.

```
main/                          scarlet/  (adds the ML-rendering path on top of main)
├── configs/mpv.conf           ├── configs/mpv.conf
├── shaders/  (pure Anime4K)   ├── core/rendering/IGpuRenderer.hpp      ← DO NOT COPY
├── macOS/GlassPlayer/...      ├── scripts/aot_shader_pipeline.py       ← DO NOT COPY
└── windows/  (full Qt port)   ├── shaders/  (Anime4K + ArtCNN/)        ← copy Anime4K parts only (already in main)
                               ├── macOS/  (+ MetalCoreMlRenderer.*)    ← DO NOT COPY ML files
                               └── windows/ (+ VulkanRenderer.*)        ← DO NOT COPY ML files
```

**Conclusion:** the "organize like scarlet" requirement is already satisfied by `main`. There is **no folder reorganization to perform.** Forking from `main` gives the correct structure for free. Do **not** add `core/` or `scripts/` from scarlet — they belong to the excluded ML path.

### 1.2 Three requested tasks that DO NOT EXIST as described

Read carefully. Attempting these will waste effort and risk corrupting the tree.

| Original request | Reality | Correct action |
|---|---|---|
| "Get the Windows port from scarlet if it's not in main." | `main` already contains a complete, working Windows Qt port under `windows/`, with all pure Anime4K shaders embedded in `windows/resources.qrc`. Scarlet's Windows port only **adds** `VulkanRenderer.cpp/.h` (excluded ML path). | **Keep main's Windows port as-is.** Do not pull anything from scarlet's `windows/`. |
| "Port scarlet's better timeline + brightness/volume sliders to macOS." | `main`'s macOS port already has `GlassSlider` for the timeline and volume, plus vertical brightness/volume sliders (`PlayerWindow.swift` defines `timelineSlider`, `volumeSlider`, `brightnessSliderV`, `volumeSliderV`). The `main`↔`scarlet` macOS diff contains **zero** new slider/timeline UI. | **No port needed.** `optimized` inherits these from `main`. Do not search scarlet for slider UI — it isn't there. |
| "Remove the Automatic preset (scarlet already did it, just take it)." | Scarlet did remove the macOS "Auto (Recommended)" menu item — but in the **same** edit it added the excluded ArtCNN/MoltenVK "★ Special" and "ArtCNN Standard" preset groups. The removal cannot be cherry-picked cleanly. | **Re-do the Auto removal by hand** per §6, taking only the deletions, none of the ArtCNN additions. |

### 1.3 What IS real work

The legitimate, grounded tasks are: branch creation (§3), enforcing pure-Anime4K shaders (§4 — already true, just verify/lock), self-containment hardening (§5), removing the dead "Auto" preset paths on both ports (§6), fixing the missing shader button (§7), Windows-only UI polish + UX bug pass (§8), and the performance / memory-leak / energy hardening + cross-port parity (§10–§12).

---

## 2. Source Boundaries — What May Be Copied From Where

### 2.1 From `main` → `optimized`
Everything. `optimized` is a fork of `main`. This is the baseline.

### 2.2 From `scarlet` → `optimized`
**Nothing is copied wholesale.** Scarlet is reference-only. The only scarlet idea that is reused is the *concept* of statically-labelled Anime4K menu headers ("── Anime4K (HQ) ──" / "── Anime4K (Fast) ──"), which you will re-implement by hand in §6. Do not `git checkout scarlet -- <file>` for any file.

### 2.3 Hard exclusion list (never appears in `optimized`)
- `core/rendering/IGpuRenderer.hpp`
- `scripts/aot_shader_pipeline.py`
- `shaders/ArtCNN/` (entire directory)
- `macOS/GlassPlayer/Sources/MetalCoreMlRenderer.h`
- `macOS/GlassPlayer/Sources/MetalCoreMlRenderer.mm`
- `windows/VulkanRenderer.cpp`, `windows/VulkanRenderer.h`
- Any symbol referencing `MoltenVK`, `isMoltenVKPresent`, `CoreMl`, `ArtCNN`, `Vulkan`, `recommendedAnime4KPreset` (the last is the Auto-resolver — remove it, see §6).
- Shader presets: `★ Anime Balanced`, `★ Anime Quality`, `★ SD / Legacy Anime`, `★ Anime Quality + Chroma`, `ArtCNN Quality (DS)`, `ArtCNN Quality (DN)`, `ArtCNN Light (DS)`, `ArtCNN Light (DN)`.

If you ever find yourself adding any of the above to `optimized`, STOP — you have taken a wrong turn.

---

## 3. STEP 1 — Create the Branch

```bash
git fetch origin
git checkout main
git pull origin main
git checkout -b optimized origin/main
git push -u origin optimized
```

Verify:
```bash
git branch --show-current     # must print: optimized
git log --oneline -1          # must match main's HEAD
```

From here on, **every** commit must be on `optimized`. Re-check `git branch --show-current` before each commit.

---

## 4. STEP 2 — Lock Shaders to Pure Anime4K (verify-only)

`main`'s `shaders/` already contains **only** pure Anime4K `.glsl` files (no `ArtCNN/` subfolder). Action:

1. Confirm no ArtCNN exists on `optimized`:
   ```bash
   ls shaders/ | grep -i artcnn   # must return nothing
   find shaders -type d           # must be only: shaders
   ```
2. Confirm the Windows resource manifest embeds only Anime4K shaders:
   ```bash
   grep -i artcnn windows/resources.qrc   # must return nothing
   ```
   If `windows/resources.qrc` contains any ArtCNN `<file>` entries, delete those lines (do not touch the Anime4K or icon entries).
3. Do **not** add, rename, or reorganize any `.glsl` file. The preset → shader-file mappings in both ports reference these exact filenames; renaming breaks playback.

No commit needed unless step 2 found ArtCNN entries to remove.

---

## 5. STEP 3 — Self-Containment Hardening

Goal: the app runs on a clean machine with **no** pre-installed dependencies, and is immune to environment changes (PATH, user mpv config, missing system libs, relocated app folder).

### 5.1 macOS (`macOS/GlassPlayer/build.sh`)
The build script already bundles dylibs into `Contents/Frameworks` (rewriting install names to `@executable_path/../Frameworks/...`) and copies `shaders/` into `Contents/Resources/shaders`. Verify and harden:

1. Confirm shader copy still present (around the `mkdir -p ".../Resources/shaders"` and `cp -R "$ROOT_DIR/shaders/."` lines). Do not remove.
2. Confirm dylib bundling loop still rewrites all non-system deps to `@executable_path/../Frameworks`. Any dep resolving to `/opt/homebrew`, `/usr/local`, or an absolute non-system path in the final binary is a self-containment failure. Add a post-build assertion:
   ```bash
   echo "=== Verifying no external dylib deps ==="
   otool -L "$APP_BUNDLE/Contents/MacOS/"* | \
     grep -E '/opt/homebrew|/usr/local' && \
     { echo "FAIL: external dylib leaked into bundle"; exit 1; } || \
     echo "OK: bundle is self-contained"
   ```
3. The shader discovery in `MPVController.swift` (`findShaders`) already prefers the bundled `Contents/Resources/shaders` path and only falls back to user mpv dirs. Keep the bundled path **first** in the candidate list. Do not make the bundle depend on a user mpv config existing.

### 5.2 Windows
1. **Shaders** are embedded in the Qt resource system (`:/shaders/...` in `resources.qrc`) and extracted at runtime to a `QTemporaryDir` by `extractShader()` in `windows/MainWindow.cpp`. This is already self-contained. Keep it. Do not switch to reading shaders from disk.
2. **libmpv** is fetched at build time by `windows/download_mpv.py` and shipped via the installer (`installer.iss` packages `dist\*`). Ensure the final `dist/` (or install tree) contains: the app `.exe`, the mpv runtime DLL, all required Qt plugins (`platforms/qwindows.dll`, `styles/`, `imageformats/` as needed), and the VC++ runtime (either statically linked or bundled). Add/keep `windeployqt` invocation in the build so Qt deps are copied automatically. The user must never need Qt or mpv pre-installed.
3. **Harden `extractShader()`** against the `QTemporaryDir` being invalid (e.g. locked-down temp): if `tempDir.isValid()` is false, fall back to `QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/shaders"`, create it, and extract there. Never return an empty path silently in a way that hides the failure from the shader-availability check (§7).

### 5.3 Both ports
- No required asset may be located via an environment variable or absolute path. All asset lookups must be relative to the executable/bundle.
- Moving the installed app to another folder must not break it. Test by relocating the built app and launching (see §9 verification).

Commit: `optimized: harden self-containment (bundle assertions, temp-dir fallback)`

---

## 6. STEP 4 — Remove the "Automatic" Shader Preset (both ports)

The "Auto (Recommended)" preset and its GPU-detection resolver must be gone everywhere: menus, cycle logic, auto-apply-on-file-load, settings defaults, and the resolver function itself.

### 6.1 macOS — `macOS/GlassPlayer/Sources/PlayerWindow.swift`

In `showShaderMenu(_:)`:
- **Delete** the line computing the recommended preset:
  `let recommendedPreset = UniversalMetalRuntime.recommendedAnime4KPreset()`
- **Delete** the entire `autoItem` block (the `NSMenuItem(title: "Auto (Recommended)", ...)`, its `.target`, `.toolTip`, and `menu.addItem(autoItem)`).
- **Replace** the dynamic HQ/Fast header titles with static labels:
  - HQ header → `NSMenuItem(title: "── Anime4K (HQ) ──", action: nil, keyEquivalent: "")`
  - Fast header → `NSMenuItem(title: "── Anime4K (Fast) ──", action: nil, keyEquivalent: "")`
  - Remove the `recommendedPreset.contains("(HQ)")` / `("(Fast)")` ternaries that produced "(Recommended on this Mac)".
- **Do NOT add** any "★ Special" or "ArtCNN Standard" groups. The menu ends after the Fast presets, then `showMenu(menu, from: sender)`.

Delete the now-unused action method:
- `@objc private func applyAutoShaderAction() { ... }` — remove entirely.

In `cycleShaderPreset()`:
- Remove `"Auto (Recommended)"` from the `presets` array.
- Remove the `else if nextPreset == "Auto (Recommended)" { ... recommendedAnime4KPreset() ... }` branch.
- Do not add the ArtCNN/★ presets that scarlet appended here.

In the file-load auto-apply logic (the `mpvFileLoaded`/`prepareShaderState` area that reads `defaultShaderPreset`):
- Remove the `else if configuredPreset == "Auto (Recommended)"` branch. Keep only `"Off"` → clear, else → `applyShaderPreset(configuredPreset)`.

In `UniversalSilicon.swift` (defines `UniversalMetalRuntime`):
- Remove the `recommendedAnime4KPreset()` function. Search the whole macOS source tree for remaining references first:
  ```bash
  grep -rn "recommendedAnime4KPreset\|Auto (Recommended)\|applyAutoShaderAction" macOS/
  ```
  The grep must return **nothing** when you are done.

In `SettingsWindow.swift`:
- If a "Default shader preset" dropdown lists `Auto (Recommended)`, remove that option. If the stored default equals `Auto (Recommended)`, migrate it to `Off` on load.

### 6.2 Windows — `windows/MainWindow.cpp`

The Windows menu (`onShaderClicked`) does **not** display an Auto entry, but dead Auto-resolution code exists:
- In `onShaderClicked`: remove the unused `QString recommendedPreset = ...;` computation (both the `Mode A (Fast)` and `Mode A (HQ)` arch-conditional assignments) if it is not used to render any menu item. Verify it isn't referenced before deleting.
- In `applyShaderPreset(const QString& preset)`: remove the two `if (normalizedPreset == "Auto (Recommended)") { resolvedPreset = ...; }` branches.
- In `SettingsWindow.cpp` and any settings defaults: ensure no UI option or stored default is `Auto (Recommended)`; migrate any such stored value to `Off`.
- Grep to confirm:
  ```bash
  grep -rn "Auto (Recommended)\|recommendedPreset" windows/   # must return nothing
  ```

Commit: `optimized: remove Automatic shader preset from both ports`

---

## 7. STEP 5 — Fix the Missing Shader Control Button

**Reported bug:** the shader control button is missing from the playback controls.

### 7.1 Root cause (macOS — most likely)
In `PlayerWindow.swift` the button is created and added, but:
```
shaderButton.isHidden = !mpv.shadersAvailable      // hidden at setup if shaders not yet found
... later, lazy reveal:
if mpv.shadersAvailable && shaderButton.isHidden { shaderButton.isHidden = false }
```
`mpv.shadersAvailable` is set true only when `findShaders()` locates a directory containing an `Anime4K*` file. If shaders are not bundled, found too late, or `findShaders` runs against the wrong `contentsDir`, the button stays hidden forever. This is **directly tied to self-containment (§5).**

Fix steps:
1. Ensure shaders are bundled (§5.1) — without this the button is correctly hidden because the feature truly is unavailable.
2. Ensure `findShaders()` runs (and `shadersAvailable` is set) **before** the lazy-reveal check, or make the reveal re-evaluate on first file load. Confirm the bundled path is candidate #0.
3. Make the reveal robust: re-check `mpv.shadersAvailable` on `mpvFileLoaded` and on window-did-become-key, not only once. If available, unhide and run `updateShaderButton()`.
4. Verify the Auto-loop layout constraints (`shaderButton.leadingAnchor`… in the constraints block) still place the button between `audioButton` and the next control after the §6 menu edits.

### 7.2 Windows
`m_shaderBtn` is created and `addWidget`-ed unconditionally in the bottom bar, so a literal "missing button" is more likely a **layout/overflow** issue (bottom bar too narrow, button pushed out, zero-size icon, or wrong z-order) than a visibility flag. Diagnose:
1. Confirm `:/icons/shader.svg` resolves (it is listed in `resources.qrc`). A missing icon renders an invisible button.
2. Confirm the bottom-bar layout reserves space for the shader button at small window widths (it should not be the first control to collapse). If a stretch/`QSpacerItem` is eating it, fix the layout so playback-critical controls (play, seek, shader, volume, fullscreen) never collapse.
3. Confirm no leftover code hides it based on a shader-availability flag; if such a flag exists, gate it the same way as macOS (available ⇒ visible).

### 7.3 Parity
After the fix, the shader button must be present and behave identically on both ports: same icon, same position relative to the volume/audio controls, same tint-on-active behavior (`updateShaderButton`), same menu contents (Off + Anime4K HQ + Anime4K Fast, no Auto, no ArtCNN).

Commit: `optimized: fix missing shader control button (both ports)`

---

## 8. STEP 6 — Windows UI Polish + UX/UI Bug Pass (Windows only)

Scope: **Windows port only.** macOS UI is already at parity target and must not be restyled.

Do a structured diagnosis of `windows/MainWindow.cpp`, `windows/SettingsWindow.cpp`, `windows/Theme.h`, and the `.svg` icons. For each issue, record: symptom → root cause → fix → verification.

Required checks (at minimum):
1. **Control bar at all widths:** no control overlaps, clips, or disappears when resizing from minimum to maximized. Playback-critical controls never collapse.
2. **Slider feel:** seek, volume, and brightness sliders use consistent styling (`Theme::kSliderHorizontalStyle` / `kSliderVerticalStyle`), correct hit-area, hover-grow handle, and accurate value mapping. Verify the seek slider's `setRange(0, 1000000)` maps smoothly with no integer-rounding jitter on long files.
3. **Hover bars:** brightness/volume hover bars (`updateHoverBars`) appear/dismiss cleanly, don't stick, and don't steal focus.
4. **Icon states:** play/pause, volume (high/mid/mute), fullscreen/fullscreen-exit swap correctly and never show a blank icon (missing-resource guard).
5. **Focus & keyboard:** spacebar play/pause, arrow seek, and shortcut keys work and don't double-fire when a slider has focus.
6. **DPI scaling:** UI is crisp and correctly sized at 125%/150%/200% Windows scaling.
7. **Theme consistency:** colors, radii, and spacing come from `Theme.h` constants — no hardcoded one-off values that drift from the design system.
8. **Settings window:** all controls reflect persisted values on open and apply immediately/consistently.

Polish constraints:
- Match the macOS port's visual language (accent color, slider proportions, control spacing) so the two feel like one product (§11).
- Do not introduce new external UI dependencies. Qt Widgets + existing SVG icons only.

Commit: `optimized: windows UI polish and UX bug fixes`

---

## 9. STEP 7 — Build & Verify (run after EVERY major step)

A change is not "done" until the affected port builds and launches.

### 9.1 macOS
```bash
cd macOS/GlassPlayer
./build.sh
```
Then verify self-containment + button:
- App launches on a machine without Homebrew mpv installed.
- `otool -L` assertion from §5.1 passes (no `/opt/homebrew`, `/usr/local`).
- Move `GlassPlayer.app` to a different folder and relaunch — still works.
- Open a video → shader button is visible → menu shows Off / Anime4K (HQ) / Anime4K (Fast), no Auto, no ArtCNN.

### 9.2 Windows
```bash
cd windows
python download_mpv.py --arch x64        # or arm64
cmake -B build -S . && cmake --build build --config Release
windeployqt build/Release/GlassPlayer.exe # ensure Qt deps copied
```
Then verify:
- Run on a clean Windows VM with no Qt/mpv installed — launches.
- Shader button visible; menu parity with macOS.
- Resize/maximize/restore — no control disappears or overlaps.
- Relocate the install folder — still launches.

If a build fails, fix before proceeding. Never leave `optimized` in a non-building state across commits.

---

## 10. STEP 8 — Performance, Memory-Leak, and Energy Hardening (both ports)

Apply per `userPreferences` priority: **secure > optimized > short.** Make these concrete, measured changes — not vague "optimize" gestures.

### 10.1 Memory leaks
- **macOS (Swift/ObjC bridge):** audit `MPVController.swift` and `ViewLayer.swift` for retained mpv handles, render contexts, and CVDisplayLink/timers not invalidated on window close. Ensure `mpv_render_context_free` / `mpv_destroy` run exactly once on teardown. Check the thumbnail caches (`thumbnailCache`, `thumbnailTimes`, `thumbnailAccessOrder`) are bounded and cleared on file change (they already clear in `mpvStartFile`). Use Instruments → Leaks + Allocations on open→play→seek→close cycles; target zero growth across 20 cycles.
- **Windows (Qt/C++):** audit `MpvWidget.cpp`, `MainWindow.cpp` for `new` without parent/`delete`, dangling `connect` lambdas capturing raw `this`, and `QTemporaryDir`/`QFile` lifetimes. Run with Application Verifier / Dr. Memory or ASan build; target zero leaks on the same open→play→seek→close cycle.

### 10.2 Speed / responsiveness
- Keep all mpv property observation and rendering off the UI thread; ensure the seek slider does not block on synchronous mpv commands (use async `command` + property observers).
- Cache decoded thumbnails (already present on macOS) with a hard cap; ensure eviction is O(1) and bounded.
- Avoid per-frame allocations in the render path. Reuse buffers.

### 10.3 Energy efficiency
- **Pause = idle:** when paused or when no video is loaded, stop render callbacks, vsync loops, and any polling timers. Do not redraw a static frame at display refresh rate.
- **Background = throttle:** when the window is occluded/minimized, suspend rendering and thumbnail generation.
- **macOS:** avoid waking the GPU when idle; ensure the CVDisplayLink/Metal loop is paused on pause. Verify with `powermetrics` / Activity Monitor "Energy" that idle (paused) CPU/GPU ≈ 0.
- **Windows:** ensure the render timer stops on pause; verify idle CPU ≈ 0 in Task Manager. Respect system power/throttling states.

### 10.4 Robustness (counts as "secure")
- Guard every shader/file/asset load against missing or unreadable resources — fail gracefully (disable the feature, log once) instead of crashing.
- Validate any value read from settings before applying to mpv.
- Never assume a directory or env var exists.

Commit: `optimized: perf, memory-leak, and energy hardening (both ports)`

---

## 11. STEP 9 — Cross-Port UI Parity

Both ports must be "connected and operate similarly." Verify each row holds on **both** macOS and Windows:

| Element | Required parity |
|---|---|
| Playback controls present | play/pause, prev/next, rewind/forward, seek slider, time labels, volume button+slider, subtitle, audio, **shader**, aspect, settings, fullscreen |
| Shader menu | Off · Anime4K (HQ) group · Anime4K (Fast) group · no Auto · no ArtCNN/Special |
| Shader button behavior | visible when shaders available; tint changes when a preset is active |
| Timeline | scrub, hover preview/thumbnail, current + remaining time labels |
| Volume | horizontal slider 0–200, mute toggle, icon reflects level |
| Brightness | vertical slider/hover bar |
| Keyboard | same shortcut set, same actions |
| Accent / styling | same accent color and proportions within each OS's native idiom |

Where a behavior differs only because of an OS convention (e.g. native fullscreen animation on macOS), that is acceptable; functional behavior must match.

---

## 12. STEP 10 — Final Review & Handoff

1. **Exclusion audit** — these must all return nothing:
   ```bash
   grep -rni "artcnn\|moltenvk\|vulkan\|coreml\|recommendedAnime4KPreset\|Auto (Recommended)" \
     --include=*.swift --include=*.cpp --include=*.h --include=*.mm --include=*.metal .
   find . -name "MetalCoreMlRenderer.*" -o -name "VulkanRenderer.*"   # nothing
   ls shaders/ | grep -i artcnn                                       # nothing
   ```
2. **Both ports build clean** (§9).
3. **Both ports launch self-contained on clean machines**, survive folder relocation, show the shader button, and pass the parity table (§11).
4. **No leaks, idle is energy-quiet** (§10).
5. **Branch check:** every commit is on `optimized`:
   ```bash
   git log --oneline origin/main..optimized   # shows only your new commits
   git branch --show-current                  # optimized
   ```
6. Push:
   ```bash
   git push origin optimized
   ```
7. Open a PR from `optimized` → `main` (do not merge). Summarize in the PR body: branch created, Auto preset removed (both ports), shader button fixed, Windows UI polished, self-containment hardened, perf/leak/energy work, parity verified, and explicitly note that ArtCNN/CoreML/Vulkan/MoltenVK were intentionally excluded.

---

## Appendix A — Commit Sequence (recommended)

1. `optimized: lock shaders to pure Anime4K (verify, strip any ArtCNN qrc entries)`
2. `optimized: harden self-containment (bundle assertions, temp-dir fallback)`
3. `optimized: remove Automatic shader preset from both ports`
4. `optimized: fix missing shader control button (both ports)`
5. `optimized: windows UI polish and UX bug fixes`
6. `optimized: perf, memory-leak, and energy hardening (both ports)`
7. `optimized: verify cross-port UI parity`

Build (§9) after commits 2–6 at minimum.

## Appendix B — Key File Map

| Concern | macOS | Windows |
|---|---|---|
| Playback UI + controls | `macOS/GlassPlayer/Sources/PlayerWindow.swift` | `windows/MainWindow.cpp` / `.h` |
| mpv integration + shader discovery | `macOS/GlassPlayer/Sources/MPVController.swift` | `windows/MpvWidget.cpp` / `.h` |
| Shader presets / apply | `PlayerWindow.swift` + `MPVController.swift` | `MainWindow.cpp` (`applyShaderPreset`, `extractShader`) |
| GPU/runtime helpers | `macOS/GlassPlayer/Sources/UniversalSilicon.swift` (`UniversalMetalRuntime`) | — |
| Settings | `macOS/.../SettingsWindow.swift` | `windows/SettingsWindow.cpp` / `.h` |
| Theme/styling | (in-code) | `windows/Theme.h` |
| Shader embedding | `build.sh` → `Contents/Resources/shaders` | `windows/resources.qrc` (`:/shaders/...`) |
| Build | `macOS/GlassPlayer/build.sh` | `windows/CMakeLists.txt` + `download_mpv.py` + `installer.iss` |
| Shared assets (do not move) | repo-root `shaders/`, `configs/` | same |
