// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v3.2-AutoDownscalePre-x4
// WHEN: OUTPUT.w NATIVE.w / 4.0 < OUTPUT.h NATIVE.h / 4.0 < * OUTPUT.w NATIVE.w / 2.4 > OUTPUT.h NATIVE.h / 2.4 > * *

#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

#define HOOKED_pos mtlPos
#define HOOKED_size float2(HOOKED.get_width(), HOOKED.get_height())
#define HOOKED_pt (float2(1, 1) / HOOKED_size)
#define HOOKED_tex(pos) HOOKED.sample(textureSampler, pos)
#define HOOKED_texOff(off) HOOKED_tex(HOOKED_pos + HOOKED_pt * float2(off))

#define NATIVE_pos mtlPos
#define NATIVE_size float2(NATIVE.get_width(), NATIVE.get_height())
#define NATIVE_pt (float2(1, 1) / NATIVE_size)
#define NATIVE_tex(pos) NATIVE.sample(textureSampler, pos)
#define NATIVE_texOff(off) NATIVE_tex(NATIVE_pos + NATIVE_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

static float4 hook_pass0(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> NATIVE, texture2d<float, access::sample> MAIN) {
	return HOOKED_tex(HOOKED_pos);
}

kernel void Anime4K_AutoDownscalePre_x4_pass0_Anime4K_v3_2_AutoDownscalePre_x4(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> NATIVE [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass0(mtlPos, textureSampler, HOOKED, NATIVE, MAIN), gid);
}

