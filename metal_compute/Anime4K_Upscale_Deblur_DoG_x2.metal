// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v3.2-Upscale-Deblur-DoG-x2-Luma

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

kernel void Anime4K_Upscale_Deblur_DoG_x2_pass0_Anime4K_v3_2_Upscale_Deblur_DoG_x2_Luma(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass0(mtlPos, textureSampler, HOOKED, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-Deblur-DoG-x2-Kernel-X
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

float max3v(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float a, float b, float c) {
	return max(max(a, b), c);
}
float min3v(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float a, float b, float c) {
	return min(min(a, b), c);
}

float2 minmax3(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float a = L_tex(pos - d).x;
	float b = L_tex(pos).x;
	float c = L_tex(pos + d).x;

	return float2(min3v(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, a, b, c), max3v(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, a, b, c));
}

float lumGaussian7(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float g = (L_tex(pos - (d + d)).x + L_tex(pos + (d + d)).x) * 0.06136;
	g = g + (L_tex(pos - d).x + L_tex(pos + d).x) * 0.24477;
	g = g + (L_tex(pos).x) * 0.38774;

	return g;
}


static float4 hook_pass1(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN) {
    return float4(lumGaussian7(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, HOOKED_pos, float2(HOOKED_pt.x, 0)), minmax3(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, HOOKED_pos, float2(HOOKED_pt.x, 0)), 0);
}

kernel void Anime4K_Upscale_Deblur_DoG_x2_pass1_Anime4K_v3_2_Upscale_Deblur_DoG_x2_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass1(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-Deblur-DoG-x2-Kernel-Y
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

#define GAUSS_X2_pos mtlPos
#define GAUSS_X2_size float2(GAUSS_X2.get_width(), GAUSS_X2.get_height())
#define GAUSS_X2_pt (float2(1, 1) / GAUSS_X2_size)
#define GAUSS_X2_tex(pos) GAUSS_X2.sample(textureSampler, pos)
#define GAUSS_X2_texOff(off) GAUSS_X2_tex(GAUSS_X2_pos + GAUSS_X2_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define L_tex GAUSS_X2_tex

float max3v(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> GAUSS_X2, texture2d<float, access::sample> MAIN, float a, float b, float c) {
	return max(max(a, b), c);
}
float min3v(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> GAUSS_X2, texture2d<float, access::sample> MAIN, float a, float b, float c) {
	return min(min(a, b), c);
}

float2 minmax3(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> GAUSS_X2, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float a0 = L_tex(pos - d).y;
	float b0 = L_tex(pos).y;
	float c0 = L_tex(pos + d).y;

	float a1 = L_tex(pos - d).z;
	float b1 = L_tex(pos).z;
	float c1 = L_tex(pos + d).z;

	return float2(min3v(mtlPos, textureSampler, HOOKED, GAUSS_X2, MAIN, a0, b0, c0), max3v(mtlPos, textureSampler, HOOKED, GAUSS_X2, MAIN, a1, b1, c1));
}

float lumGaussian7(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> GAUSS_X2, texture2d<float, access::sample> MAIN, float2 pos, float2 d) {
	float g = (L_tex(pos - (d + d)).x + L_tex(pos + (d + d)).x) * 0.06136;
	g = g + (L_tex(pos - d).x + L_tex(pos + d).x) * 0.24477;
	g = g + (L_tex(pos).x) * 0.38774;

	return g;
}


static float4 hook_pass2(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> GAUSS_X2, texture2d<float, access::sample> MAIN) {
    return float4(lumGaussian7(mtlPos, textureSampler, HOOKED, GAUSS_X2, MAIN, HOOKED_pos, float2(0, HOOKED_pt.y)), minmax3(mtlPos, textureSampler, HOOKED, GAUSS_X2, MAIN, HOOKED_pos, float2(0, HOOKED_pt.y)), 0);
}

kernel void Anime4K_Upscale_Deblur_DoG_x2_pass2_Anime4K_v3_2_Upscale_Deblur_DoG_x2_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> GAUSS_X2 [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass2(mtlPos, textureSampler, HOOKED, GAUSS_X2, MAIN), gid);
}


// DESC: Anime4K-v3.2-Upscale-Deblur-DoG-x2-Apply
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

#define GAUSS_X2_pos mtlPos
#define GAUSS_X2_size float2(GAUSS_X2.get_width(), GAUSS_X2.get_height())
#define GAUSS_X2_pt (float2(1, 1) / GAUSS_X2_size)
#define GAUSS_X2_tex(pos) GAUSS_X2.sample(textureSampler, pos)
#define GAUSS_X2_texOff(off) GAUSS_X2_tex(GAUSS_X2_pos + GAUSS_X2_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define STRENGTH 0.6 //De-blur proportional strength, higher is sharper. However, it is better to tweak BLUR_CURVE instead to avoid ringing.
#define BLUR_CURVE 0.6 //De-blur power curve, lower is sharper. Good values are between 0.3 - 1. Values greater than 1 softens the image;
#define BLUR_THRESHOLD 0.1 //Value where curve kicks in, used to not de-blur already sharp edges. Only de-blur values that fall below this threshold.
#define NOISE_THRESHOLD 0.001 //Value where curve stops, used to not sharpen noise. Only de-blur values that fall above this threshold.

#define L_tex LINELUMA_tex

static float4 hook_pass3(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> GAUSS_X2, texture2d<float, access::sample> MAIN) {
	float c = (L_tex(HOOKED_pos).x - GAUSS_X2_tex(HOOKED_pos).x) * STRENGTH;

	float t_range = BLUR_THRESHOLD - NOISE_THRESHOLD;

	float c_t = abs(c);
	if (c_t > NOISE_THRESHOLD && c_t < BLUR_THRESHOLD) {
		c_t = (c_t - NOISE_THRESHOLD) / t_range;
		c_t = pow(c_t, BLUR_CURVE);
		c_t = c_t * t_range + NOISE_THRESHOLD;
		c_t = c_t * sign(c);
	} else {
		c_t = c;
	}

	float cc = clamp(c_t + L_tex(HOOKED_pos).x, GAUSS_X2_tex(HOOKED_pos).y, GAUSS_X2_tex(HOOKED_pos).z) - L_tex(HOOKED_pos).x;

	//This trick is only possible if the inverse Y->RGB matrix has 1 for every row... (which is the case for BT.709)
	//Otherwise we would need to convert RGB to YUV, modify Y then convert back to RGB.
	return HOOKED_tex(HOOKED_pos) + cc;
}

kernel void Anime4K_Upscale_Deblur_DoG_x2_pass3_Anime4K_v3_2_Upscale_Deblur_DoG_x2_Apply(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> GAUSS_X2 [[texture(2)]],
    texture2d<float, access::sample> MAIN [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass3(mtlPos, textureSampler, HOOKED, LINELUMA, GAUSS_X2, MAIN), gid);
}

