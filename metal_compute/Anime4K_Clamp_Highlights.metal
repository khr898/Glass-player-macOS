// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v4.0-De-Ring-Compute-Statistics

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

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define KERNELSIZE 5 //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE 2 //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).

float get_luma(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN, float4 rgba) {
	return dot(float4(0.299, 0.587, 0.114, 0.0), rgba);
}

static float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN) {

	float gmax = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float g = get_luma(mtlPos, textureSampler, HOOKED, MAIN, MAIN_texOff(float2(i - KERNELHALFSIZE, 0)));

		gmax = max(g, gmax);
	}

	return float4(gmax, 0.0, 0.0, 0.0);
}

kernel void Anime4K_Clamp_Highlights_pass0_Anime4K_v4_0_De_Ring_Compute_Statistics(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, MAIN), gid);
}


// DESC: Anime4K-v4.0-De-Ring-Compute-Statistics

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

#define STATSMAX_pos mtlPos
#define STATSMAX_size float2(STATSMAX.get_width(), STATSMAX.get_height())
#define STATSMAX_pt (float2(1, 1) / STATSMAX_size)
#define STATSMAX_tex(pos) STATSMAX.sample(textureSampler, pos)
#define STATSMAX_texOff(off) STATSMAX_tex(STATSMAX_pos + STATSMAX_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define KERNELSIZE 5 //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE 2 //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).

static float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> STATSMAX, texture2d<float, access::sample> MAIN) {

	float gmax = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float g = STATSMAX_texOff(float2(0, i - KERNELHALFSIZE)).x;

		gmax = max(g, gmax);
	}

	return float4(gmax, 0.0, 0.0, 0.0);
}

kernel void Anime4K_Clamp_Highlights_pass1_Anime4K_v4_0_De_Ring_Compute_Statistics(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> STATSMAX [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, STATSMAX, MAIN), gid);
}


// DESC: Anime4K-v4.0-De-Ring-Clamp

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

#define STATSMAX_pos mtlPos
#define STATSMAX_size float2(STATSMAX.get_width(), STATSMAX.get_height())
#define STATSMAX_pt (float2(1, 1) / STATSMAX_size)
#define STATSMAX_tex(pos) STATSMAX.sample(textureSampler, pos)
#define STATSMAX_texOff(off) STATSMAX_tex(STATSMAX_pos + STATSMAX_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

float get_luma(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> STATSMAX, texture2d<float, access::sample> MAIN, float4 rgba) {
	return dot(float4(0.299, 0.587, 0.114, 0.0), rgba);
}

static float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> STATSMAX, texture2d<float, access::sample> MAIN) {

	float current_luma = get_luma(mtlPos, textureSampler, HOOKED, STATSMAX, MAIN, HOOKED_tex(HOOKED_pos));
	float new_luma = min(current_luma, STATSMAX_tex(HOOKED_pos).x);

	//This trick is only possible if the inverse Y->RGB matrix has 1 for every row... (which is the case for BT.709)
	//Otherwise we would need to convert RGB to YUV, modify Y then convert back to RGB.
    return HOOKED_tex(HOOKED_pos) - (current_luma - new_luma); 
}

kernel void Anime4K_Clamp_Highlights_pass2_Anime4K_v4_0_De_Ring_Clamp(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> STATSMAX [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, STATSMAX, MAIN), gid);
}

