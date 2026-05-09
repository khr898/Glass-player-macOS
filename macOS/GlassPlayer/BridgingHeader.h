#ifndef BridgingHeader_h
#define BridgingHeader_h

// ── mpv headers ──
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>          // mpv_opengl_init_params, mpv_opengl_fbo

// ── OpenGL (minimal: offscreen CGL context for mpv render API interop) ──
// These are NOT used for display rendering – all screen output uses Metal 3.
// CGL is required because mpv_render_context only supports OpenGL API type.
#include <OpenGL/OpenGL.h>          // CGL context management
#include <OpenGL/gl3.h>             // GL types for IOSurface-backed FBO
#include <OpenGL/CGLIOSurface.h>    // CGLTexImageIOSurface2D (IOSurface ↔ GL texture bridge)

// ── IOSurface (zero-copy Apple Silicon UMA bridge: GL FBO → Metal texture) ──
#include <IOSurface/IOSurface.h>

// ── System ──
#include <IOKit/graphics/IOGraphicsLib.h>
#include <os/lock.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct __attribute__((aligned(64))) GPAlignedRenderState {
	os_unfair_lock lock;
	int32_t needsUpdate;
	int32_t forceRender;
	int32_t _padding;
} GPAlignedRenderState;

static inline void GPAlignedRenderStateInit(GPAlignedRenderState *state) {
	state->lock = OS_UNFAIR_LOCK_INIT;
	state->needsUpdate = 0;
	state->forceRender = 0;
	state->_padding = 0;
}

static inline void *GPAlignedRenderStateCreate(void) {
	GPAlignedRenderState *state = NULL;
	if (posix_memalign((void **)&state, 64, sizeof(GPAlignedRenderState)) != 0 || state == NULL) {
		return NULL;
	}
	GPAlignedRenderStateInit(state);
	return state;
}

static inline void GPAlignedRenderStateDestroy(void *opaqueState) {
	if (opaqueState != NULL) {
		free(opaqueState);
	}
}

static inline GPAlignedRenderState *GPAlignedRenderStateCast(void *opaqueState) {
	return (GPAlignedRenderState *)opaqueState;
}

static inline void GPAlignedRenderStateMarkUpdate(void *opaqueState, int32_t force) {
	GPAlignedRenderState *state = GPAlignedRenderStateCast(opaqueState);
	if (state == NULL) return;
	os_unfair_lock_lock(&state->lock);
	state->needsUpdate = 1;
	if (force) {
		state->forceRender = 1;
	}
	os_unfair_lock_unlock(&state->lock);
}

static inline void GPAlignedRenderStateClearFrameFlags(void *opaqueState) {
	GPAlignedRenderState *state = GPAlignedRenderStateCast(opaqueState);
	if (state == NULL) return;
	os_unfair_lock_lock(&state->lock);
	state->needsUpdate = 0;
	state->forceRender = 0;
	os_unfair_lock_unlock(&state->lock);
}

static inline int32_t GPAlignedRenderStateGetNeedsUpdate(void *opaqueState) {
	GPAlignedRenderState *state = GPAlignedRenderStateCast(opaqueState);
	if (state == NULL) return 0;
	os_unfair_lock_lock(&state->lock);
	int32_t value = state->needsUpdate;
	os_unfair_lock_unlock(&state->lock);
	return value;
}

static inline int32_t GPAlignedRenderStateGetForceRender(void *opaqueState) {
	GPAlignedRenderState *state = GPAlignedRenderStateCast(opaqueState);
	if (state == NULL) return 0;
	os_unfair_lock_lock(&state->lock);
	int32_t value = state->forceRender;
	os_unfair_lock_unlock(&state->lock);
	return value;
}

#endif
