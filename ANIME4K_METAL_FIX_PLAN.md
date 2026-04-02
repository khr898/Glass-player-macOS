# Anime4K Metal Pipeline Fix Plan

**Date:** 2026-04-02  
**Status:** Ready for Implementation  
**Complexity:** HIGH  
**Estimated Time:** 7-10 days

---

## Executive Summary

**Goal:** Fix Anime4K upscaling/denoising in GlassPlayer using Metal compute shaders with mpv as decoder.

**Problem:** Shaders compile but produce no visible effect. Video displays normally but unchanged.

**Root Cause:** Texture format mismatch (`.bgra8Unorm` vs `.rgba16Float`) combined with incorrect texture binding architecture.

**Solution:** Align GlassPlayer's implementation with Anime4KMetal reference:
1. Use `.rgba16Float` for intermediate textures
2. Implement texture map architecture (named binding vs fixed indices)
3. Fix command buffer synchronization
4. Update kernel registry to match translated shaders

---

## Current State Analysis

### What Works
- ✅ Metal shaders compile successfully
- ✅ Pipeline activates (`isActive = true`)
- ✅ Video displays normally
- ✅ No crashes or errors

### What's Broken
- ❌ No visible upscaling/denoising effect
- ❌ Output texture = input texture (unchanged)
- ❌ Texture format mismatch
- ❌ Texture binding architecture mismatch

### Code Flow
```
User selects preset 
  → MPVController.applyShaderPreset() 
  → ViewLayer.enableAnime4K(preset) 
  → Anime4KMetalPipeline.activatePreset() 
  → On each frame: processFrame()
  → Returns sourceTexture unchanged (silent failure)
```

---

## Root Cause Analysis

### 1. Pixel Format Mismatch (CRITICAL)

**Anime4KMetal uses `.rgba16Float`:**
```swift
// Anime4KMetal/Shared/Anime4K.swift:195-198
desc.pixelFormat = .rgba16Float
desc.usage = [.shaderWrite, .shaderRead]
desc.storageMode = .private
```

**GlassPlayer uses `.bgra8Unorm`:**
```swift
// Anime4KMetalPipeline.swift
descriptor.pixelFormat = .bgra8Unorm
descriptor.usage = [.shaderRead, .shaderWrite]
descriptor.storageMode = .shared
```

**Impact:**
- 8-bit vs 16-bit precision loss in intermediate calculations
- Potential format incompatibility in compute shaders
- Silent failure (no error, just wrong output)

### 2. Texture Binding Architecture Mismatch

**Anime4KMetal approach:**
- Uses **texture map** dictionary keyed by name ("MAIN", "conv2d_tf", etc.)
- Each shader pass declares input textures via `BIND` directives
- Output texture bound at index = `inputTextureNames.count`
- Uses `.private` storage mode (GPU-only, optimal for compute)

**GlassPlayer approach:**
- Binds textures at **fixed indices** (0, 1, 2, ... 15)
- Uses `.shared` storage mode (CPU+GPU accessible, slower)
- Doesn't track intermediate textures by name
- Assumes all passes use same binding pattern

### 3. Command Buffer Synchronization

**Issue:** Compute encoder ends but no explicit barrier before render pass reads output.

- `encoder.endEncoding()` does NOT flush compute work
- `commandBuffer.commit()` called AFTER both compute and render encoding
- Without synchronization, render pass may read stale texture data

### 4. mpv Integration

**Finding:** mpv outputs `bgra8Unorm` or `bgra10Float` depending on display.

**Implication:** Need format conversion at pipeline boundaries:
- Input: `bgra8Unorm` (mpv) → `rgba16Float` (Anime4K)
- Output: `rgba16Float` (Anime4K) → `bgra8Unorm` (display)

---

## Implementation Phases

### Phase 1: Fix Texture Format (Days 1-2)

**Goal:** Match Anime4KMetal's texture format

**Tasks:**
1. [ ] Change intermediate texture format from `.bgra8Unorm` to `.rgba16Float`
2. [ ] Update `ensureOutputTexture()` to use correct format
3. [ ] Update `allocateIntermediateTextures()` to use correct format
4. [ ] Add format conversion at pipeline boundaries:
   - Input: `bgra8Unorm` → `rgba16Float` (blit encoder copy)
   - Output: `rgba16Float` → `bgra8Unorm` (blit encoder copy)
5. [ ] Use `.private` storage mode for intermediate textures

**Files Modified:**
- `GlassPlayer/Sources/Anime4KMetalPipeline.swift`

**Acceptance Criteria:**
- Intermediate textures use `.rgba16Float`
- Format conversion works without visual artifacts

**Risk:** MEDIUM - Format conversion adds overhead

---

### Phase 2: Implement Texture Map Architecture (Days 3-5)

**Goal:** Match Anime4KMetal's texture binding approach

**Tasks:**
1. [ ] Create `TextureMap` class to manage textures by name
   - Dictionary: `[String: MTLTexture]`
   - Methods: `get(name)`, `set(name, texture)`, `clear()`
2. [ ] Parse shader `BIND` directives to determine required textures
3. [ ] Update `processFrame()` to:
   - Create new texture map per frame
   - Set `textureMap["MAIN"] = inputTexture`
   - For each pass:
     - Bind input textures by name → index
     - Allocate output texture if needed
     - Bind output at index = input count
4. [ ] Allocate intermediate textures per-pass (not per-file)
5. [ ] Use `.private` storage mode for all intermediate textures

**New Files:**
- `GlassPlayer/Sources/TextureMap.swift`

**Files Modified:**
- `GlassPlayer/Sources/Anime4KMetalPipeline.swift`

**Acceptance Criteria:**
- Textures bound by name, not fixed index
- Each pass gets correct input textures
- Intermediate textures allocated per-pass

**Risk:** HIGH - Architectural change

---

### Phase 3: Fix Synchronization (Days 5-6)

**Goal:** Ensure compute work completes before render reads

**Tasks:**
1. [ ] Add `MTLFence` for compute→render synchronization
   - Create fence at pipeline init
   - Insert fence after compute dispatch
   - Wait for fence before render pass
2. [ ] OR use `addCompletedHandler` for explicit synchronization
3. [ ] Ensure each compute encoder's work is visible to subsequent passes
4. [ ] Add explicit barrier before final render pass
5. [ ] Test with Xcode Metal Debugger to verify synchronization

**Files Modified:**
- `GlassPlayer/Sources/Anime4KMetalPipeline.swift`
- `GlassPlayer/Sources/ViewLayer.swift`

**Acceptance Criteria:**
- No visual artifacts from race conditions
- Xcode Metal Debugger shows correct ordering
- Frame time stable (no stalls)

**Risk:** MEDIUM - Synchronization bugs are subtle

---

### Phase 4: Update Kernel Registry (Day 7)

**Goal:** Ensure kernel names match translated shaders

**Tasks:**
1. [ ] Verify all kernel names in `KernelFunctionRegistry` match translated shaders
2. [ ] Add `_passN` suffixes where needed
3. [ ] Test each preset individually:
   - Mode A (Fast)
   - Mode A (HQ)
   - Mode VL
   - Mode C (Denoise)
4. [ ] Add logging for kernel loading failures

**Files Modified:**
- `GlassPlayer/Sources/Anime4KMetalPipeline.swift`
- `GlassPlayer/Sources/Anime4KMode.swift`

**Acceptance Criteria:**
- All presets load without errors
- Each kernel found in metallib

**Risk:** LOW - Mechanical update

---

### Phase 5: Testing & Profiling (Days 8-10)

**Goal:** Verify functionality and performance

**Test Matrix:**

| Preset | 1080p | 4K | Hardware |
|--------|-------|----|----------|
| Mode A (Fast) | ✅ | ✅ | M1/M2/M3 |
| Mode A (HQ) | ✅ | ✅ | M1 Pro+ |
| Mode B (Fast) | ✅ | ✅ | M1/M2/M3 |
| Mode C (Denoise) | ✅ | ⚠️ | M1 Pro+ |
| Mode VL | ✅ | ⚠️ | M2 Pro+ |

**Profiling Tasks:**
1. [ ] Use Xcode Instruments (Metal System Trace)
2. [ ] Measure frame time per preset
3. [ ] Verify GPU utilization <80% (headroom for other tasks)
4. [ ] Check for synchronization stalls
5. [ ] Compare quality vs mpv GLSL reference (SSIM >0.95)

**Test Videos:**
- 720p anime (upscale test)
- 1080p anime (denoise test)
- 4K HDR (performance test)

**Acceptance Criteria:**
- Visible upscaling/denoising effect
- Frame time <10ms on M1 (1080p)
- No stuttering or dropped frames
- SSIM >0.95 vs reference

**Risk:** LOW - Standard testing

---

## Dependencies

| Dependency | Purpose | Status |
|------------|---------|--------|
| Xcode 16+ | Metal debugging | ✅ Available |
| Anime4KMetal reference | Architecture guide | ✅ Available |
| Metal debugger | Profiling | ✅ Built-in |
| Test videos | Validation | ✅ Available |

---

## Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Format conversion overhead | HIGH | Performance loss | Use `.private` storage, minimize copies |
| Texture binding bugs | MEDIUM | Black screen | Extensive logging, test each pass |
| Synchronization issues | MEDIUM | Visual artifacts | Xcode Metal debugger, fence testing |
| Performance regression | LOW | Unwatchable | Profile early, add quality presets |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Functional** | Visible upscaling | 720p → 1080p clearly sharper |
| **Performance** | <10ms frame time | Xcode Instruments |
| **Quality** | SSIM >0.95 | vs mpv GLSL reference |
| **Compatibility** | All formats work | MKV, ASS, SRT tested |

---

## Files Summary

### New Files
- `GlassPlayer/Sources/TextureMap.swift`

### Modified Files
- `GlassPlayer/Sources/Anime4KMetalPipeline.swift` (Phases 1-4)
- `GlassPlayer/Sources/ViewLayer.swift` (Phase 3)
- `GlassPlayer/Sources/Anime4KMode.swift` (Phase 4)

### Unchanged (for reference)
- `GlassPlayer/MetalShaders/*.metal` (translated shaders)
- `GlassPlayer/Sources/MPVController.swift` (mpv integration)

---

## Appendix: Reference Implementation

### Anime4KMetal Texture Binding (Reference)
```swift
// From Anime4KMetal/Shared/Anime4K.swift:223-253
for j in 0..<shader.inputTextureNames.count {
    var textureName = shader.inputTextureNames[j]
    if textureName == "HOOKED", let hook = shader.hook {
        textureName = hook
    }
    if !textureMap[bufferIndex].keys.contains(textureName) {
        if textureName == shader.save {
            // Allocate intermediate texture
            let desc = MTLTextureDescriptor()
            desc.pixelFormat = .rgba16Float
            desc.storageMode = .private
            textureMap[bufferIndex][textureName] = device.makeTexture(descriptor: desc)
        } else {
            throw Anime4KError.encoderFail("texture \(textureName) is missing")
        }
    }
    encoder.setTexture(textureMap[bufferIndex][textureName], index: j)
}
let outputTex = textureMap[bufferIndex][shader.outputTextureName]!
encoder.setTexture(outputTex, index: shader.inputTextureNames.count)
```

### Key Differences from GlassPlayer
| Aspect | Anime4KMetal | GlassPlayer |
|--------|--------------|-------------|
| Format | `.rgba16Float` | `.bgra8Unorm` |
| Storage | `.private` | `.shared` |
| Binding | By name → index | Fixed indices |
| Sync | Per-pass encoder | Single encoder |

---

**Plan Version:** 1.0  
**Created:** 2026-04-02  
**Next Review:** After Phase 1 completion
