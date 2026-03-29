// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v3.2-Deblur-Original-Luma

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

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN) {
    return float4(get_luma(mtlPos, textureSampler, HOOKED, MAIN, HOOKED_tex(HOOKED_pos)), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Deblur_Original_pass0_Anime4K_v3_2_Deblur_Original_Luma(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, MAIN), gid);
}


// DESC: Anime4K-v3.2-Deblur-Original-Kernel-X

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

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	//[tl  t tr]
	//[ l  c  r]
	//[bl  b br]
	float l = LINELUMA_tex(HOOKED_pos + float2(-d.x, 0.0)).x;
	float c = LINELUMA_tex(HOOKED_pos).x;
	float r = LINELUMA_tex(HOOKED_pos + float2(d.x, 0.0)).x;


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
	return float4(xgrad, ygrad, 0.0, 0.0);
}

kernel void Anime4K_Deblur_Original_pass1_Anime4K_v3_2_Deblur_Original_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN), gid);
}


// DESC: Anime4K-v3.2-Deblur-Original-Kernel-Y

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

/* --------------------- SETTINGS --------------------- */

//Strength of edge refinement, good values are between 0.2 and 4
#define REFINE_STRENGTH 1.0


/* --- MODIFY THESE SETTINGS BELOW AT YOUR OWN RISK --- */

//Bias of the refinement function, good values are between 0 and 1
#define REFINE_BIAS 0.0

//Polynomial fit obtained by minimizing MSE error on image
#define P5 ( 11.68129591)
#define P4 (-42.46906057)
#define P3 ( 60.28286266)
#define P2 (-41.84451327)
#define P1 ( 14.05517353)
#define P0 (-1.081521930)

/* ----------------- END OF SETTINGS ----------------- */

float power_function(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> MAIN, float x) {
	float x2 = x * x;
	float x3 = x2 * x;
	float x4 = x2 * x2;
	float x5 = x2 * x3;

	return P5*x5 + P4*x4 + P3*x3 + P2*x2 + P1*x + P0;
}

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	//[tl  t tr]
	//[ l cc  r]
	//[bl  b br]
	float tx = LUMAD_tex(HOOKED_pos + float2(0.0, -d.y)).x;
	float cx = LUMAD_tex(HOOKED_pos).x;
	float bx = LUMAD_tex(HOOKED_pos + float2(0.0, d.y)).x;


	float ty = LUMAD_tex(HOOKED_pos + float2(0.0, -d.y)).y;
	//float cy = LUMAD_tex(HOOKED_pos).y;
	float by = LUMAD_tex(HOOKED_pos + float2(0.0, d.y)).y;


	//Horizontal Gradient
	//[-1  0  1]
	//[-2  0  2]
	//[-1  0  1]
	float xgrad = (tx + cx + cx + bx);

	//Vertical Gradient
	//[-1 -2 -1]
	//[ 0  0  0]
	//[ 1  2  1]
	float ygrad = (-ty + by);

	//Computes the luminance's gradient
	float sobel_norm = clamp(sqrt(xgrad * xgrad + ygrad * ygrad), 0.0, 1.0);

	float dval = clamp(power_function(mtlPos, textureSampler, HOOKED, LUMAD, MAIN, clamp(sobel_norm, 0.0, 1.0)) * REFINE_STRENGTH + REFINE_BIAS, 0.0, 1.0);

	return float4(sobel_norm, dval, 0.0, 0.0);
}

kernel void Anime4K_Deblur_Original_pass2_Anime4K_v3_2_Deblur_Original_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, LUMAD, MAIN), gid);
}


// DESC: Anime4K-v3.2-Deblur-Original-Kernel-X

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

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	if (LUMAD_tex(HOOKED_pos).y < 0.1) {
		return float4(0.0);
	}

	//[tl  t tr]
	//[ l  c  r]
	//[bl  b br]
	float l = LUMAD_tex(HOOKED_pos + float2(-d.x, 0.0)).x;
	float c = LUMAD_tex(HOOKED_pos).x;
	float r = LUMAD_tex(HOOKED_pos + float2(d.x, 0.0)).x;

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


	return float4(xgrad, ygrad, 0.0, 0.0);
}

kernel void Anime4K_Deblur_Original_pass3_Anime4K_v3_2_Deblur_Original_Kernel_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, LUMAD, MAIN), gid);
}


// DESC: Anime4K-v3.2-Deblur-Original-Kernel-Y

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

#define LUMAMM_pos mtlPos
#define LUMAMM_size float2(LUMAMM.get_width(), LUMAMM.get_height())
#define LUMAMM_pt (float2(1, 1) / LUMAMM_size)
#define LUMAMM_tex(pos) LUMAMM.sample(textureSampler, pos)
#define LUMAMM_texOff(off) LUMAMM_tex(LUMAMM_pos + LUMAMM_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> LUMAMM, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	if (LUMAD_tex(HOOKED_pos).y < 0.1) {
		return float4(0.0);
	}

	//[tl  t tr]
	//[ l cc  r]
	//[bl  b br]
	float tx = LUMAMM_tex(HOOKED_pos + float2(0.0, -d.y)).x;
	float cx = LUMAMM_tex(HOOKED_pos).x;
	float bx = LUMAMM_tex(HOOKED_pos + float2(0.0, d.y)).x;

	float ty = LUMAMM_tex(HOOKED_pos + float2(0.0, -d.y)).y;
	//float cy = LUMAMM_tex(HOOKED_pos).y;
	float by = LUMAMM_tex(HOOKED_pos + float2(0.0, d.y)).y;

	//Horizontal Gradient
	//[-1  0  1]
	//[-2  0  2]
	//[-1  0  1]
	float xgrad = (tx + cx + cx + bx);

	//Vertical Gradient
	//[-1 -2 -1]
	//[ 0  0  0]
	//[ 1  2  1]
	float ygrad = (-ty + by);

	float norm = sqrt(xgrad * xgrad + ygrad * ygrad);
	if (norm <= 0.001) {
		xgrad = 0.0;
		ygrad = 0.0;
		norm = 1.0;
	}

	return float4(xgrad/norm, ygrad/norm, 0.0, 0.0);
}

kernel void Anime4K_Deblur_Original_pass4_Anime4K_v3_2_Deblur_Original_Kernel_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> LUMAMM [[texture(2)]],
    texture2d<float, access::sample> MAIN [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, LUMAD, LUMAMM, MAIN), gid);
}


// DESC: Anime4K-v3.2-Deblur-Original-Apply

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

#define LUMAMM_pos mtlPos
#define LUMAMM_size float2(LUMAMM.get_width(), LUMAMM.get_height())
#define LUMAMM_pt (float2(1, 1) / LUMAMM_size)
#define LUMAMM_tex(pos) LUMAMM.sample(textureSampler, pos)
#define LUMAMM_texOff(off) LUMAMM_tex(LUMAMM_pos + LUMAMM_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LUMAD, texture2d<float, access::sample> LUMAMM, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	float dval = LUMAD_tex(HOOKED_pos).y;
	if (dval < 0.1) {
		return HOOKED_tex(HOOKED_pos);
	}

	float4 dc = LUMAMM_tex(HOOKED_pos);
	if (abs(dc.x + dc.y) <= 0.0001) {
		return HOOKED_tex(HOOKED_pos);
	}

	float xpos = -sign(dc.x);
	float ypos = -sign(dc.y);

	float4 xval = HOOKED_tex(HOOKED_pos + float2(d.x * xpos, 0.0));
	float4 yval = HOOKED_tex(HOOKED_pos + float2(0.0, d.y * ypos));

	float xyratio = abs(dc.x) / (abs(dc.x) + abs(dc.y));

	float4 avg = xyratio * xval + (1.0 - xyratio) * yval;

	return avg * dval + HOOKED_tex(HOOKED_pos) * (1.0 - dval);

}

kernel void Anime4K_Deblur_Original_pass5_Anime4K_v3_2_Deblur_Original_Apply(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LUMAD [[texture(1)]],
    texture2d<float, access::sample> LUMAMM [[texture(2)]],
    texture2d<float, access::sample> MAIN [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, LUMAD, LUMAMM, MAIN), gid);
}


// DESC: Anime4K-v3.2-Deblur-Original-Resample

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

#define RESAMPLED_pos mtlPos
#define RESAMPLED_size float2(RESAMPLED.get_width(), RESAMPLED.get_height())
#define RESAMPLED_pt (float2(1, 1) / RESAMPLED_size)
#define RESAMPLED_tex(pos) RESAMPLED.sample(textureSampler, pos)
#define RESAMPLED_texOff(off) RESAMPLED_tex(RESAMPLED_pos + RESAMPLED_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> RESAMPLED, texture2d<float, access::sample> MAIN) {
	return RESAMPLED_tex(HOOKED_pos);
}

kernel void Anime4K_Deblur_Original_pass6_Anime4K_v3_2_Deblur_Original_Resample(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> RESAMPLED [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, RESAMPLED, MAIN), gid);
}

