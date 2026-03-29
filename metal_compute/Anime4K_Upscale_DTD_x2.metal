// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v3.2-Upscale-DTD-x2-Luma

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

float get_luma(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN, float4 rgba) {
	return dot(float4(0.299, 0.587, 0.114, 0.0), rgba);
}

static float4 hook_pass0(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN) {
    return float4(get_luma(mtlPos, textureSampler, HOOKED, MAIN, HOOKED_tex(HOOKED_pos)), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Upscale_DTD_x2_pass0_Anime4K_v3_2_Upscale_DTD_x2_Luma(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass0(mtlPos, textureSampler, HOOKED, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-X
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LINELUMA_pos mtlPos
#define LINELUMA_size float2(LINELUMA.get_width(), LINELUMA.get_height())
#define LINELUMA_pt (float2(1, 1) / LINELUMA_size)
#define LINELUMA_tex(pos) LINELUMA.sample(textureSampler, pos)
#define LINELUMA_texOff(off) LINELUMA_tex(LINELUMA_pos + LINELUMA_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex LINELUMA_tex

#define SIGMA 1.0

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	return (1.0 / (s * sqrt(2.0 * 3.14159))) * exp(-0.5 * pow(abs(x - m) / s, 2.0));
}

float lumGaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float s = SIGMA * HOOKED_size.y / 1080.0;
	float kernel_size = s * 2.0 + 1.0;

	float g = (L_tex(pos).x) * gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, 0.0, s, 0.0);
	float gn = gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, 0.0, s, 0.0);

	g += (L_tex(pos - d).x + L_tex(pos + d).x) * gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, 1.0, s, 0.0);
	gn += gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, 1.0, s, 0.0) * 2.0;

	for (int i=2; float(i)<kernel_size; i++) {
		g += (L_tex(pos - (d * float(i))).x + L_tex(pos + (d * float(i))).x) * gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, float(i), s, 0.0);
		gn += gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, float(i), s, 0.0) * 2.0;
	}

	return g / gn;
}

static float4 hook_pass1(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN) {
    return float4(lumGaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, HOOKED_pos, float2(HOOKED_pt.x, 0)));
}

kernel void Anime4K_Upscale_DTD_x2_pass1_Anime4K_v3_2_Upscale_DTD_x2_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass1(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-Y
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LINELUMA_pos mtlPos
#define LINELUMA_size float2(LINELUMA.get_width(), LINELUMA.get_height())
#define LINELUMA_pt (float2(1, 1) / LINELUMA_size)
#define LINELUMA_tex(pos) LINELUMA.sample(textureSampler, pos)
#define LINELUMA_texOff(off) LINELUMA_tex(LINELUMA_pos + LINELUMA_pt * float2(off))

#define MMKERNEL_pos mtlPos
#define MMKERNEL_size float2(MMKERNEL.get_width(), MMKERNEL.get_height())
#define MMKERNEL_pt (float2(1, 1) / MMKERNEL_size)
#define MMKERNEL_tex(pos) MMKERNEL.sample(textureSampler, pos)
#define MMKERNEL_texOff(off) MMKERNEL_tex(MMKERNEL_pos + MMKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex MMKERNEL_tex

#define SIGMA 1.0

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	return (1.0 / (s * sqrt(2.0 * 3.14159))) * exp(-0.5 * pow(abs(x - m) / s, 2.0));
}

float lumGaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float s = SIGMA * HOOKED_size.y / 1080.0;
	float kernel_size = s * 2.0 + 1.0;

	float g = (L_tex(pos).x) * gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MMKERNEL, MAIN, 0.0, s, 0.0);
	float gn = gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MMKERNEL, MAIN, 0.0, s, 0.0);

	g += (L_tex(pos - d).x + L_tex(pos + d).x) * gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MMKERNEL, MAIN, 1.0, s, 0.0);
	gn += gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MMKERNEL, MAIN, 1.0, s, 0.0) * 2.0;

	for (int i=2; float(i)<kernel_size; i++) {
		g += (L_tex(pos - (d * float(i))).x + L_tex(pos + (d * float(i))).x) * gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MMKERNEL, MAIN, float(i), s, 0.0);
		gn += gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MMKERNEL, MAIN, float(i), s, 0.0) * 2.0;
	}

	return g / gn;
}

static float4 hook_pass2(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN) {
    return float4(min(LINELUMA_tex(HOOKED_pos).x - lumGaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MMKERNEL, MAIN, HOOKED_pos, float2(0, HOOKED_pt.y)), 0.0));
}

kernel void Anime4K_Upscale_DTD_x2_pass2_Anime4K_v3_2_Upscale_DTD_x2_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> MMKERNEL [[texture(2)]],
    texture2d<float, access::sample> MAIN [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass2(mtlPos, textureSampler, HOOKED, LINELUMA, MMKERNEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-X
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define MMKERNEL_pos mtlPos
#define MMKERNEL_size float2(MMKERNEL.get_width(), MMKERNEL.get_height())
#define MMKERNEL_pt (float2(1, 1) / MMKERNEL_size)
#define MMKERNEL_tex(pos) MMKERNEL.sample(textureSampler, pos)
#define MMKERNEL_texOff(off) MMKERNEL_tex(MMKERNEL_pos + MMKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex MMKERNEL_tex

#define SIGMA 0.4

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	return (1.0 / (s * sqrt(2.0 * 3.14159))) * exp(-0.5 * pow(abs(x - m) / s, 2.0));
}

float lumGaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float s = SIGMA * HOOKED_size.y / 1080.0;
	float kernel_size = s * 2.0 + 1.0;

	float g = (L_tex(pos).x) * gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, 0.0, s, 0.0);
	float gn = gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, 0.0, s, 0.0);

	g += (L_tex(pos - d).x + L_tex(pos + d).x) * gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, 1.0, s, 0.0);
	gn += gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, 1.0, s, 0.0) * 2.0;

	for (int i=2; float(i)<kernel_size; i++) {
		g += (L_tex(pos - (d * float(i))).x + L_tex(pos + (d * float(i))).x) * gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, float(i), s, 0.0);
		gn += gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, float(i), s, 0.0) * 2.0;
	}

	return g / gn;
}

static float4 hook_pass3(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN) {
    return float4(lumGaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, HOOKED_pos, float2(HOOKED_pt.x, 0)));
}

kernel void Anime4K_Upscale_DTD_x2_pass3_Anime4K_v3_2_Upscale_DTD_x2_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MMKERNEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass3(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-Y
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define MMKERNEL_pos mtlPos
#define MMKERNEL_size float2(MMKERNEL.get_width(), MMKERNEL.get_height())
#define MMKERNEL_pt (float2(1, 1) / MMKERNEL_size)
#define MMKERNEL_tex(pos) MMKERNEL.sample(textureSampler, pos)
#define MMKERNEL_texOff(off) MMKERNEL_tex(MMKERNEL_pos + MMKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex MMKERNEL_tex

#define SIGMA 0.4

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	return (1.0 / (s * sqrt(2.0 * 3.14159))) * exp(-0.5 * pow(abs(x - m) / s, 2.0));
}

float lumGaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float s = SIGMA * HOOKED_size.y / 1080.0;
	float kernel_size = s * 2.0 + 1.0;

	float g = (L_tex(pos).x) * gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, 0.0, s, 0.0);
	float gn = gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, 0.0, s, 0.0);

	g += (L_tex(pos - d).x + L_tex(pos + d).x) * gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, 1.0, s, 0.0);
	gn += gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, 1.0, s, 0.0) * 2.0;

	for (int i=2; float(i)<kernel_size; i++) {
		g += (L_tex(pos - (d * float(i))).x + L_tex(pos + (d * float(i))).x) * gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, float(i), s, 0.0);
		gn += gaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, float(i), s, 0.0) * 2.0;
	}

	return g / gn;
}

static float4 hook_pass4(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN) {
    return float4(lumGaussian(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, HOOKED_pos, float2(0, HOOKED_pt.y)));
}

kernel void Anime4K_Upscale_DTD_x2_pass4_Anime4K_v3_2_Upscale_DTD_x2_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MMKERNEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass4(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define MMKERNEL_pos mtlPos
#define MMKERNEL_size float2(MMKERNEL.get_width(), MMKERNEL.get_height())
#define MMKERNEL_pt (float2(1, 1) / MMKERNEL_size)
#define MMKERNEL_tex(pos) MMKERNEL.sample(textureSampler, pos)
#define MMKERNEL_texOff(off) MMKERNEL_tex(MMKERNEL_pos + MMKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define STRENGTH 1.8 //Line darken proportional strength, higher is darker.

static float4 hook_pass5(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN) {
	float c = (MMKERNEL_tex(HOOKED_pos).x) * STRENGTH;
	//This trick is only possible if the inverse Y->RGB matrix has 1 for every row... (which is the case for BT.709)
	//Otherwise we would need to convert RGB to YUV, modify Y then convert back to RGB.
    return HOOKED_tex(HOOKED_pos) + c;
}

kernel void Anime4K_Upscale_DTD_x2_pass5_Anime4K_v3_2_Upscale_DTD_x2(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MMKERNEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass5(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Luma

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

float get_luma(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN, float4 rgba) {
	return dot(float4(0.299, 0.587, 0.114, 0.0), rgba);
}

static float4 hook_pass6(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN) {
    return float4(get_luma(mtlPos, textureSampler, HOOKED, MAIN, HOOKED_tex(HOOKED_pos)), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Upscale_DTD_x2_pass6_Anime4K_v3_2_Upscale_DTD_x2_Luma(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass6(mtlPos, textureSampler, HOOKED, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-X
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LINELUMA_pos mtlPos
#define LINELUMA_size float2(LINELUMA.get_width(), LINELUMA.get_height())
#define LINELUMA_pt (float2(1, 1) / LINELUMA_size)
#define LINELUMA_tex(pos) LINELUMA.sample(textureSampler, pos)
#define LINELUMA_texOff(off) LINELUMA_tex(LINELUMA_pos + LINELUMA_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex LINELUMA_tex

static float4 hook_pass7(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	//[tl  t tr]
	//[ l  c  r]
	//[bl  b br]
	float l = L_tex(HOOKED_pos + float2(-d.x, 0)).x;
	float c = L_tex(HOOKED_pos).x;
	float r = L_tex(HOOKED_pos + float2(d.x, 0)).x;


	//Horizontal Gradient
	//[-1  0  1]
	//[-2  0  2]
	//[-1  0  1]
	float xgrad = (-l + r);

	//Vertical Gradient
	//[-1 -2 -1]
	//[ 0  0  0]
	//[ 1  2  1]
	float ygrad = (l + c + c + r);

	//Computes the luminance's gradient
	return float4(xgrad, ygrad, 0, 0);
}

kernel void Anime4K_Upscale_DTD_x2_pass7_Anime4K_v3_2_Upscale_DTD_x2_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass7(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-Y
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LUMAD_pos mtlPos
#define LUMAD_size float2(LUMAD.get_width(), LUMAD.get_height())
#define LUMAD_pt (float2(1, 1) / LUMAD_size)
#define LUMAD_tex(pos) LUMAD.sample(textureSampler, pos)
#define LUMAD_texOff(off) LUMAD_tex(LUMAD_pos + LUMAD_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

static float4 hook_pass8(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	//[tl  t tr]
	//[ l cc  r]
	//[bl  b br]
	float tx = LUMAD_tex(HOOKED_pos + float2(0, -d.y)).x;
	float cx = LUMAD_tex(HOOKED_pos).x;
	float bx = LUMAD_tex(HOOKED_pos + float2(0, d.y)).x;


	float ty = LUMAD_tex(HOOKED_pos + float2(0, -d.y)).y;
	//float cy = LUMAD_tex(HOOKED_pos).y;
	float by = LUMAD_tex(HOOKED_pos + float2(0, d.y)).y;


	//Horizontal Gradient
	//[-1  0  1]
	//[-2  0  2]
	//[-1  0  1]
	float xgrad = (tx + cx + cx + bx) / 8.0;

	//Vertical Gradient
	//[-1 -2 -1]
	//[ 0  0  0]
	//[ 1  2  1]
	float ygrad = (-ty + by) / 8.0;

	//Computes the luminance's gradient
	float norm = sqrt(xgrad * xgrad + ygrad * ygrad);
	return float4(pow(norm, 0.7));
}

kernel void Anime4K_Upscale_DTD_x2_pass8_Anime4K_v3_2_Upscale_DTD_x2_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass8(mtlPos, textureSampler, HOOKED, LUMAD, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-X
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LUMAD_pos mtlPos
#define LUMAD_size float2(LUMAD.get_width(), LUMAD.get_height())
#define LUMAD_pt (float2(1, 1) / LUMAD_size)
#define LUMAD_tex(pos) LUMAD.sample(textureSampler, pos)
#define LUMAD_texOff(off) LUMAD_tex(LUMAD_pos + LUMAD_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex LUMAD_tex

#define SIGMA (HOOKED_size.y / 1080.0) * 2.0
#define KERNELSIZE (SIGMA * 2.0 + 1.0)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	return (1.0 / (s * sqrt(2.0 * 3.14159))) * exp(-0.5 * pow(abs(x - m) / s, 2.0));
}

float lumGaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> MAIN, float2 pos, float2 d, int KERNELSIZE, int KERNELHALFSIZE) {
	float g = (L_tex(pos).x) * gaussian(mtlPos, textureSampler, HOOKED, LUMAD, MAIN, 0.0, SIGMA, 0.0);
	g = g + (L_tex(pos - d).x + L_tex(pos + d).x) * gaussian(mtlPos, textureSampler, HOOKED, LUMAD, MAIN, 1.0, SIGMA, 0.0);
	for (int i=2; float(i)<KERNELSIZE; i++) {
		g = g + (L_tex(pos - (d * float(i))).x + L_tex(pos + (d * float(i))).x) * gaussian(mtlPos, textureSampler, HOOKED, LUMAD, MAIN, float(i), SIGMA, 0.0);
	}

	return g;
}

static float4 hook_pass9(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> MAIN) {
    return float4(lumGaussian(mtlPos, textureSampler, HOOKED, LUMAD, MAIN, HOOKED_pos, float2(HOOKED_pt.x, 0)));
}

kernel void Anime4K_Upscale_DTD_x2_pass9_Anime4K_v3_2_Upscale_DTD_x2_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass9(mtlPos, textureSampler, HOOKED, LUMAD, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-Y
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LUMAD_pos mtlPos
#define LUMAD_size float2(LUMAD.get_width(), LUMAD.get_height())
#define LUMAD_pt (float2(1, 1) / LUMAD_size)
#define LUMAD_tex(pos) LUMAD.sample(textureSampler, pos)
#define LUMAD_texOff(off) LUMAD_tex(LUMAD_pos + LUMAD_pt * float2(off))

#define LUMADG_pos mtlPos
#define LUMADG_size float2(LUMADG.get_width(), LUMADG.get_height())
#define LUMADG_pt (float2(1, 1) / LUMADG_size)
#define LUMADG_tex(pos) LUMADG.sample(textureSampler, pos)
#define LUMADG_texOff(off) LUMADG_tex(LUMADG_pos + LUMADG_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex LUMADG_tex

#define SIGMA (HOOKED_size.y / 1080.0) * 2.0
#define KERNELSIZE (SIGMA * 2.0 + 1.0)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> LUMADG, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	return (1.0 / (s * sqrt(2.0 * 3.14159))) * exp(-0.5 * pow(abs(x - m) / s, 2.0));
}

float lumGaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> LUMADG, texture2d<float, access::sample> MAIN, float2 pos, float2 d, int KERNELSIZE, int KERNELHALFSIZE) {
	float g = (L_tex(pos).x) * gaussian(mtlPos, textureSampler, HOOKED, LUMAD, LUMADG, MAIN, 0.0, SIGMA, 0.0);
	g = g + (L_tex(pos - d).x + L_tex(pos + d).x) * gaussian(mtlPos, textureSampler, HOOKED, LUMAD, LUMADG, MAIN, 1.0, SIGMA, 0.0);
	for (int i=2; float(i)<KERNELSIZE; i++) {
		g = g + (L_tex(pos - (d * float(i))).x + L_tex(pos + (d * float(i))).x) * gaussian(mtlPos, textureSampler, HOOKED, LUMAD, LUMADG, MAIN, float(i), SIGMA, 0.0);
	}

	return g;
}

static float4 hook_pass10(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> LUMADG, texture2d<float, access::sample> MAIN) {
	float g = lumGaussian(mtlPos, textureSampler, HOOKED, LUMAD, LUMADG, MAIN, HOOKED_pos, float2(0, HOOKED_pt.y));
    return float4(g);
}

kernel void Anime4K_Upscale_DTD_x2_pass10_Anime4K_v3_2_Upscale_DTD_x2_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> LUMADG [[texture(2)]],
    texture2d<float, access::sample> MAIN [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass10(mtlPos, textureSampler, HOOKED, LUMAD, LUMADG, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-X
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LUMAD_pos mtlPos
#define LUMAD_size float2(LUMAD.get_width(), LUMAD.get_height())
#define LUMAD_pt (float2(1, 1) / LUMAD_size)
#define LUMAD_tex(pos) LUMAD.sample(textureSampler, pos)
#define LUMAD_texOff(off) LUMAD_tex(LUMAD_pos + LUMAD_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

static float4 hook_pass11(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	//[tl  t tr]
	//[ l  c  r]
	//[bl  b br]
	float l = LUMAD_tex(HOOKED_pos + float2(-d.x, 0)).x;
	float c = LUMAD_tex(HOOKED_pos).x;
	float r = LUMAD_tex(HOOKED_pos + float2(d.x, 0)).x;


	//Horizontal Gradient
	//[-1  0  1]
	//[-2  0  2]
	//[-1  0  1]
	float xgrad = (-l + r);

	//Vertical Gradient
	//[-1 -2 -1]
	//[ 0  0  0]
	//[ 1  2  1]
	float ygrad = (l + c + c + r);

	//Computes the luminance's gradient
	return float4(xgrad, ygrad, 0, 0);
}

kernel void Anime4K_Upscale_DTD_x2_pass11_Anime4K_v3_2_Upscale_DTD_x2_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass11(mtlPos, textureSampler, HOOKED, LUMAD, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-Y
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LUMAD2_pos mtlPos
#define LUMAD2_size float2(LUMAD2.get_width(), LUMAD2.get_height())
#define LUMAD2_pt (float2(1, 1) / LUMAD2_size)
#define LUMAD2_tex(pos) LUMAD2.sample(textureSampler, pos)
#define LUMAD2_texOff(off) LUMAD2_tex(LUMAD2_pos + LUMAD2_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

static float4 hook_pass12(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD2, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	//[tl  t tr]
	//[ l cc  r]
	//[bl  b br]
	float tx = LUMAD2_tex(HOOKED_pos + float2(0, -d.y)).x;
	float cx = LUMAD2_tex(HOOKED_pos).x;
	float bx = LUMAD2_tex(HOOKED_pos + float2(0, d.y)).x;


	float ty = LUMAD2_tex(HOOKED_pos + float2(0, -d.y)).y;
	//float cy = LUMAD2_tex(HOOKED_pos).y;
	float by = LUMAD2_tex(HOOKED_pos + float2(0, d.y)).y;


	//Horizontal Gradient
	//[-1  0  1]
	//[-2  0  2]
	//[-1  0  1]
	float xgrad = (tx + cx + cx + bx) / 8.0;

	//Vertical Gradient
	//[-1 -2 -1]
	//[ 0  0  0]
	//[ 1  2  1]
	float ygrad = (-ty + by) / 8.0;

	//Computes the luminance's gradient
	return float4(xgrad, ygrad, 0, 0);
}

kernel void Anime4K_Upscale_DTD_x2_pass12_Anime4K_v3_2_Upscale_DTD_x2_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD2 [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass12(mtlPos, textureSampler, HOOKED, LUMAD2, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define LUMAD_pos mtlPos
#define LUMAD_size float2(LUMAD.get_width(), LUMAD.get_height())
#define LUMAD_pt (float2(1, 1) / LUMAD_size)
#define LUMAD_tex(pos) LUMAD.sample(textureSampler, pos)
#define LUMAD_texOff(off) LUMAD_tex(LUMAD_pos + LUMAD_pt * float2(off))

#define LUMAD2_pos mtlPos
#define LUMAD2_size float2(LUMAD2.get_width(), LUMAD2.get_height())
#define LUMAD2_pt (float2(1, 1) / LUMAD2_size)
#define LUMAD2_tex(pos) LUMAD2.sample(textureSampler, pos)
#define LUMAD2_texOff(off) LUMAD2_tex(LUMAD2_pos + LUMAD2_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define STRENGTH 0.4 //Strength of warping for each iteration
#define ITERATIONS 1 //Number of iterations for the forwards solver, decreasing strength and increasing iterations improves quality at the cost of speed.

#define L_tex HOOKED_tex

static float4 hook_pass13(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> LUMAD2, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	float relstr = HOOKED_size.y / 1080.0 * STRENGTH;

	float2 pos = HOOKED_pos;
	for (int i=0; i<ITERATIONS; i++) {
		float2 dn = LUMAD2_tex(pos).xy;
		float2 dd = (dn / (length(dn) + 0.01)) * d * relstr; //Quasi-normalization for large vectors, avoids divide by zero
		pos -= dd;
	}

	return L_tex(pos);

}

kernel void Anime4K_Upscale_DTD_x2_pass13_Anime4K_v3_2_Upscale_DTD_x2(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> LUMAD2 [[texture(2)]],
    texture2d<float, access::sample> MAIN [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass13(mtlPos, textureSampler, HOOKED, LUMAD, LUMAD2, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Luma

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

#define MAINTEMPTHIN_pos mtlPos
#define MAINTEMPTHIN_size float2(MAINTEMPTHIN.get_width(), MAINTEMPTHIN.get_height())
#define MAINTEMPTHIN_pt (float2(1, 1) / MAINTEMPTHIN_size)
#define MAINTEMPTHIN_tex(pos) MAINTEMPTHIN.sample(textureSampler, pos)
#define MAINTEMPTHIN_texOff(off) MAINTEMPTHIN_tex(MAINTEMPTHIN_pos + MAINTEMPTHIN_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

float get_luma(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAINTEMPTHIN, texture2d<float, access::sample> MAIN, float4 rgba) {
	return dot(float4(0.299, 0.587, 0.114, 0.0), rgba);
}

static float4 hook_pass14(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAINTEMPTHIN, texture2d<float, access::sample> MAIN) {
    return float4(get_luma(mtlPos, textureSampler, HOOKED, MAINTEMPTHIN, MAIN, MAINTEMPTHIN_tex(HOOKED_pos)), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Upscale_DTD_x2_pass14_Anime4K_v3_2_Upscale_DTD_x2_Luma(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAINTEMPTHIN [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass14(mtlPos, textureSampler, HOOKED, MAINTEMPTHIN, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-X
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define MAINTEMP_pos mtlPos
#define MAINTEMP_size float2(MAINTEMP.get_width(), MAINTEMP.get_height())
#define MAINTEMP_pt (float2(1, 1) / MAINTEMP_size)
#define MAINTEMP_tex(pos) MAINTEMP.sample(textureSampler, pos)
#define MAINTEMP_texOff(off) MAINTEMP_tex(MAINTEMP_pos + MAINTEMP_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex MAINTEMP_tex

float max3v(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAINTEMP, texture2d<float, access::sample> MAIN, float a, float b, float c) {
	return max(max(a, b), c);
}
float min3v(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAINTEMP, texture2d<float, access::sample> MAIN, float a, float b, float c) {
	return min(min(a, b), c);
}

float2 minmax3(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAINTEMP, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float a = L_tex(pos - d).x;
	float b = L_tex(pos).x;
	float c = L_tex(pos + d).x;

	return float2(min3v(mtlPos, textureSampler, HOOKED, MAINTEMP, MAIN, a, b, c), max3v(mtlPos, textureSampler, HOOKED, MAINTEMP, MAIN, a, b, c));
}

float lumGaussian7(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAINTEMP, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float g = (L_tex(pos - (d + d)).x + L_tex(pos + (d + d)).x) * 0.06136;
	g = g + (L_tex(pos - d).x + L_tex(pos + d).x) * 0.24477;
	g = g + (L_tex(pos).x) * 0.38774;

	return g;
}


static float4 hook_pass15(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAINTEMP, texture2d<float, access::sample> MAIN) {
    return float4(lumGaussian7(mtlPos, textureSampler, HOOKED, MAINTEMP, MAIN, HOOKED_pos, float2(HOOKED_pt.x, 0)), minmax3(mtlPos, textureSampler, HOOKED, MAINTEMP, MAIN, HOOKED_pos, float2(HOOKED_pt.x, 0)), 0);
}

kernel void Anime4K_Upscale_DTD_x2_pass15_Anime4K_v3_2_Upscale_DTD_x2_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAINTEMP [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass15(mtlPos, textureSampler, HOOKED, MAINTEMP, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2-Kernel-Y
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define MMKERNEL_pos mtlPos
#define MMKERNEL_size float2(MMKERNEL.get_width(), MMKERNEL.get_height())
#define MMKERNEL_pt (float2(1, 1) / MMKERNEL_size)
#define MMKERNEL_tex(pos) MMKERNEL.sample(textureSampler, pos)
#define MMKERNEL_texOff(off) MMKERNEL_tex(MMKERNEL_pos + MMKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex MMKERNEL_tex

float max3v(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float a, float b, float c) {
	return max(max(a, b), c);
}
float min3v(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float a, float b, float c) {
	return min(min(a, b), c);
}

float2 minmax3(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float a0 = L_tex(pos - d).y;
	float b0 = L_tex(pos).y;
	float c0 = L_tex(pos + d).y;

	float a1 = L_tex(pos - d).z;
	float b1 = L_tex(pos).z;
	float c1 = L_tex(pos + d).z;

	return float2(min3v(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, a0, b0, c0), max3v(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, a1, b1, c1));
}

float lumGaussian7(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float g = (L_tex(pos - (d + d)).x + L_tex(pos + (d + d)).x) * 0.06136;
	g = g + (L_tex(pos - d).x + L_tex(pos + d).x) * 0.24477;
	g = g + (L_tex(pos).x) * 0.38774;

	return g;
}


static float4 hook_pass16(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN) {
    return float4(lumGaussian7(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, HOOKED_pos, float2(0, HOOKED_pt.y)), minmax3(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN, HOOKED_pos, float2(0, HOOKED_pt.y)), 0);
}

kernel void Anime4K_Upscale_DTD_x2_pass16_Anime4K_v3_2_Upscale_DTD_x2_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MMKERNEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass16(mtlPos, textureSampler, HOOKED, MMKERNEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-DTD-x2
// WHEN: OUTPUT.w MAIN.w / 1.200 > OUTPUT.h MAIN.h / 1.200 > *

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

#define MAINTEMPTHIN_pos mtlPos
#define MAINTEMPTHIN_size float2(MAINTEMPTHIN.get_width(), MAINTEMPTHIN.get_height())
#define MAINTEMPTHIN_pt (float2(1, 1) / MAINTEMPTHIN_size)
#define MAINTEMPTHIN_tex(pos) MAINTEMPTHIN.sample(textureSampler, pos)
#define MAINTEMPTHIN_texOff(off) MAINTEMPTHIN_tex(MAINTEMPTHIN_pos + MAINTEMPTHIN_pt * float2(off))

#define MAINTEMP_pos mtlPos
#define MAINTEMP_size float2(MAINTEMP.get_width(), MAINTEMP.get_height())
#define MAINTEMP_pt (float2(1, 1) / MAINTEMP_size)
#define MAINTEMP_tex(pos) MAINTEMP.sample(textureSampler, pos)
#define MAINTEMP_texOff(off) MAINTEMP_tex(MAINTEMP_pos + MAINTEMP_pt * float2(off))

#define MMKERNEL_pos mtlPos
#define MMKERNEL_size float2(MMKERNEL.get_width(), MMKERNEL.get_height())
#define MMKERNEL_pt (float2(1, 1) / MMKERNEL_size)
#define MMKERNEL_tex(pos) MMKERNEL.sample(textureSampler, pos)
#define MMKERNEL_texOff(off) MMKERNEL_tex(MMKERNEL_pos + MMKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define STRENGTH 0.5 //De-blur proportional strength, higher is sharper. However, it is better to tweak BLUR_CURVE instead to avoid ringing.
#define BLUR_CURVE 0.8 //De-blur power curve, lower is sharper. Good values are between 0.3 - 1. Values greater than 1 softens the image;
#define BLUR_THRESHOLD 0.1 //Value where curve kicks in, used to not de-blur already sharp edges. Only de-blur values that fall below this threshold.
#define NOISE_THRESHOLD 0.004 //Value where curve stops, used to not sharpen noise. Only de-blur values that fall above this threshold.

#define L_tex MAINTEMP_tex

static float4 hook_pass17(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAINTEMPTHIN, texture2d<float, access::sample> MAINTEMP, texture2d<float, access::sample> MMKERNEL, texture2d<float, access::sample> MAIN) {
	float c = (L_tex(HOOKED_pos).x - MMKERNEL_tex(HOOKED_pos).x) * STRENGTH;

	float t_range = BLUR_THRESHOLD - NOISE_THRESHOLD;

	float c_t = abs(c);
	if (c_t > NOISE_THRESHOLD) {
		c_t = (c_t - NOISE_THRESHOLD) / t_range;
		c_t = pow(c_t, BLUR_CURVE);
		c_t = c_t * t_range + NOISE_THRESHOLD;
		c_t = c_t * sign(c);
	} else {
		c_t = c;
	}

	float cc = clamp(c_t + L_tex(HOOKED_pos).x, MMKERNEL_tex(HOOKED_pos).y, MMKERNEL_tex(HOOKED_pos).z) - L_tex(HOOKED_pos).x;

	//This trick is only possible if the inverse Y->RGB matrix has 1 for every row... (which is the case for BT.709)
	//Otherwise we would need to convert RGB to YUV, modify Y then convert back to RGB.
	return MAINTEMPTHIN_tex(HOOKED_pos) + cc;
}

kernel void Anime4K_Upscale_DTD_x2_pass17_Anime4K_v3_2_Upscale_DTD_x2(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAINTEMPTHIN [[texture(1)]],
    texture2d<float, access::sample> MAINTEMP [[texture(2)]],
    texture2d<float, access::sample> MMKERNEL [[texture(3)]],
    texture2d<float, access::sample> MAIN [[texture(4)]],
    texture2d<float, access::write> output [[texture(5)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass17(mtlPos, textureSampler, HOOKED, MAINTEMPTHIN, MAINTEMP, MMKERNEL, MAIN), gid);
}

