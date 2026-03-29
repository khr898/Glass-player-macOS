// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v3.2-Thin-(Fast)-Luma

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

kernel void Anime4K_Thin_Fast_pass0_Anime4K_v3_2_Thin_Fast_Luma(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass0(mtlPos, textureSampler, HOOKED, MAIN), gid);
}


// DESC: Anime4K-v3.2-Thin-(Fast)-Sobel-X

#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

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

#define HOOKED_pos mtlPos
#define HOOKED_size float2(MAIN.get_width(), MAIN.get_height())
#define HOOKED_pt (float2(1, 1) / HOOKED_size)
#define HOOKED_tex(pos) MAIN.sample(textureSampler, pos)
#define HOOKED_texOff(off) HOOKED_tex(HOOKED_pos + HOOKED_pt * float2(off))

static float4 hook_pass1(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN) {
	float l = LINELUMA_texOff(float2(-1.0, 0.0)).x;
	float c = LINELUMA_tex(LINELUMA_pos).x;
	float r = LINELUMA_texOff(float2(1.0, 0.0)).x;

	float xgrad = (-l + r);
	float ygrad = (l + c + c + r);

	return float4(xgrad, ygrad, 0.0, 0.0);
}

kernel void Anime4K_Thin_Fast_pass1_Anime4K_v3_2_Thin_Fast_Sobel_X(
    texture2d<float, access::sample> LINELUMA [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass1(mtlPos, textureSampler, LINELUMA, MAIN), gid);
}


// DESC: Anime4K-v3.2-Thin-(Fast)-Sobel-Y

#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

#define LINESOBEL_pos mtlPos
#define LINESOBEL_size float2(LINESOBEL.get_width(), LINESOBEL.get_height())
#define LINESOBEL_pt (float2(1, 1) / LINESOBEL_size)
#define LINESOBEL_tex(pos) LINESOBEL.sample(textureSampler, pos)
#define LINESOBEL_texOff(off) LINESOBEL_tex(LINESOBEL_pos + LINESOBEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define HOOKED_pos mtlPos
#define HOOKED_size float2(MAIN.get_width(), MAIN.get_height())
#define HOOKED_pt (float2(1, 1) / HOOKED_size)
#define HOOKED_tex(pos) MAIN.sample(textureSampler, pos)
#define HOOKED_texOff(off) HOOKED_tex(HOOKED_pos + HOOKED_pt * float2(off))

static float4 hook_pass2(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> LINESOBEL, texture2d<float, access::sample> MAIN) {
	float tx = LINESOBEL_texOff(float2(0.0, -0.5)).x;
	float cx = LINESOBEL_tex(LINESOBEL_pos).x;
	float bx = LINESOBEL_texOff(float2(0.0, 0.5)).x;

	float ty = LINESOBEL_texOff(float2(0.0, -0.5)).y;
	float by = LINESOBEL_texOff(float2(0.0, 0.5)).y;

	float xgrad = (tx + cx + cx + bx) / 8.0;

	float ygrad = (-ty + by) / 8.0;

	//Computes the luminance's gradient
	float norm = sqrt(xgrad * xgrad + ygrad * ygrad);
	return float4(pow(norm, 0.7));
}

kernel void Anime4K_Thin_Fast_pass2_Anime4K_v3_2_Thin_Fast_Sobel_Y(
    texture2d<float, access::sample> LINESOBEL [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass2(mtlPos, textureSampler, LINESOBEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Thin-(Fast)-Gaussian-X

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

#define LINESOBEL_pos mtlPos
#define LINESOBEL_size float2(LINESOBEL.get_width(), LINESOBEL.get_height())
#define LINESOBEL_pt (float2(1, 1) / LINESOBEL_size)
#define LINESOBEL_tex(pos) LINESOBEL.sample(textureSampler, pos)
#define LINESOBEL_texOff(off) LINESOBEL_tex(LINESOBEL_pos + LINESOBEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

// // SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0  (computed in kernel below)

    // #define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.  (computed dynamically below)
    // #define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).  (computed dynamically below)
    // #define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.  (computed dynamically below)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float x, float m, float SPATIAL_SIGMA) {
	float scaled = (x - m) / SPATIAL_SIGMA;
	return exp(-0.5 * scaled * scaled);
}

float comp_gaussian_x(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINESOBEL, texture2d<float, access::sample> MAIN, int KERNELSIZE, int KERNELHALFSIZE, float SPATIAL_SIGMA, SPATIAL_SIGMA) {

	float g = 0.0;
	float gn = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float di = float(i - KERNELHALFSIZE);
		float gf = gaussian(mtlPos, textureSampler, HOOKED, LINESOBEL, MAIN, di, 0.0, SPATIAL_SIGMA);

		g = g + LINESOBEL_texOff(float2(di, 0.0)).x * gf;
		gn = gn + gf;

	}

	return g / gn;
}

static float4 hook_pass3(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINESOBEL, texture2d<float, access::sample> MAIN) {
    return float4(comp_gaussian_x(mtlPos, textureSampler, HOOKED, LINESOBEL, MAIN, SPATIAL_SIGMA), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Thin_Fast_pass3_Anime4K_v3_2_Thin_Fast_Gaussian_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINESOBEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass3(mtlPos, textureSampler, HOOKED, LINESOBEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Thin-(Fast)-Gaussian-Y

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

#define LINESOBEL_pos mtlPos
#define LINESOBEL_size float2(LINESOBEL.get_width(), LINESOBEL.get_height())
#define LINESOBEL_pt (float2(1, 1) / LINESOBEL_size)
#define LINESOBEL_tex(pos) LINESOBEL.sample(textureSampler, pos)
#define LINESOBEL_texOff(off) LINESOBEL_tex(LINESOBEL_pos + LINESOBEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

// // SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0  (computed in kernel below)

    // #define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.  (computed dynamically below)
    // #define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).  (computed dynamically below)
    // #define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.  (computed dynamically below)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float x, float m, float SPATIAL_SIGMA) {
	float scaled = (x - m) / SPATIAL_SIGMA;
	return exp(-0.5 * scaled * scaled);
}

float comp_gaussian_y(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINESOBEL, texture2d<float, access::sample> MAIN, int KERNELSIZE, int KERNELHALFSIZE) {

	float g = 0.0;
	float gn = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float di = float(i - KERNELHALFSIZE);
		float gf = gaussian(mtlPos, textureSampler, HOOKED, LINESOBEL, MAIN, di, 0.0, SPATIAL_SIGMA);

		g = g + LINESOBEL_texOff(float2(0.0, di)).x * gf;
		gn = gn + gf;

	}

	return g / gn;
}

static float4 hook_pass4(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINESOBEL, texture2d<float, access::sample> MAIN) {
    return float4(comp_gaussian_y(mtlPos, textureSampler, HOOKED, LINESOBEL, MAIN), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Thin_Fast_pass4_Anime4K_v3_2_Thin_Fast_Gaussian_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINESOBEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass4(mtlPos, textureSampler, HOOKED, LINESOBEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Thin-(Fast)-Kernel-X

#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

#define LINESOBEL_pos mtlPos
#define LINESOBEL_size float2(LINESOBEL.get_width(), LINESOBEL.get_height())
#define LINESOBEL_pt (float2(1, 1) / LINESOBEL_size)
#define LINESOBEL_tex(pos) LINESOBEL.sample(textureSampler, pos)
#define LINESOBEL_texOff(off) LINESOBEL_tex(LINESOBEL_pos + LINESOBEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define HOOKED_pos mtlPos
#define HOOKED_size float2(MAIN.get_width(), MAIN.get_height())
#define HOOKED_pt (float2(1, 1) / HOOKED_size)
#define HOOKED_tex(pos) MAIN.sample(textureSampler, pos)
#define HOOKED_texOff(off) HOOKED_tex(HOOKED_pos + HOOKED_pt * float2(off))

static float4 hook_pass5(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> LINESOBEL, texture2d<float, access::sample> MAIN) {
	float l = LINESOBEL_texOff(float2(-0.5, 0.0)).x;
	float c = LINESOBEL_tex(LINESOBEL_pos).x;
	float r = LINESOBEL_texOff(float2(0.5, 0.0)).x;

	float xgrad = (-l + r);
	float ygrad = (l + c + c + r);

	return float4(xgrad, ygrad, 0.0, 0.0);
}

kernel void Anime4K_Thin_Fast_pass5_Anime4K_v3_2_Thin_Fast_Kernel_X(
    texture2d<float, access::sample> LINESOBEL [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass5(mtlPos, textureSampler, LINESOBEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Thin-(Fast)-Kernel-Y

#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

#define LINESOBEL_pos mtlPos
#define LINESOBEL_size float2(LINESOBEL.get_width(), LINESOBEL.get_height())
#define LINESOBEL_pt (float2(1, 1) / LINESOBEL_size)
#define LINESOBEL_tex(pos) LINESOBEL.sample(textureSampler, pos)
#define LINESOBEL_texOff(off) LINESOBEL_tex(LINESOBEL_pos + LINESOBEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define HOOKED_pos mtlPos
#define HOOKED_size float2(MAIN.get_width(), MAIN.get_height())
#define HOOKED_pt (float2(1, 1) / HOOKED_size)
#define HOOKED_tex(pos) MAIN.sample(textureSampler, pos)
#define HOOKED_texOff(off) HOOKED_tex(HOOKED_pos + HOOKED_pt * float2(off))

static float4 hook_pass6(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> LINESOBEL, texture2d<float, access::sample> MAIN) {
	float tx = LINESOBEL_texOff(float2(0.0, -0.5)).x;
	float cx = LINESOBEL_tex(LINESOBEL_pos).x;
	float bx = LINESOBEL_texOff(float2(0.0, 0.5)).x;

	float ty = LINESOBEL_texOff(float2(0.0, -0.5)).y;
	float by = LINESOBEL_texOff(float2(0.0, 0.5)).y;

	float xgrad = (tx + cx + cx + bx) / 8.0;

	float ygrad = (-ty + by) / 8.0;

	//Computes the luminance's gradient
	return float4(xgrad, ygrad, 0.0, 0.0);
}

kernel void Anime4K_Thin_Fast_pass6_Anime4K_v3_2_Thin_Fast_Kernel_Y(
    texture2d<float, access::sample> LINESOBEL [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass6(mtlPos, textureSampler, LINESOBEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Thin-(Fast)-Warp

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

#define LINESOBEL_pos mtlPos
#define LINESOBEL_size float2(LINESOBEL.get_width(), LINESOBEL.get_height())
#define LINESOBEL_pt (float2(1, 1) / LINESOBEL_size)
#define LINESOBEL_tex(pos) LINESOBEL.sample(textureSampler, pos)
#define LINESOBEL_texOff(off) LINESOBEL_tex(LINESOBEL_pos + LINESOBEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define STRENGTH 0.6 //Strength of warping for each iteration
#define ITERATIONS 1 //Number of iterations for the forwards solver, decreasing strength and increasing iterations improves quality at the cost of speed.

static float4 hook_pass7(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINESOBEL, texture2d<float, access::sample> MAIN) {
	float2 d = HOOKED_pt;

	float relstr = HOOKED_size.y / 1080.0 * STRENGTH;

	float2 pos = HOOKED_pos;
	for (int i=0; i<ITERATIONS; i++) {
		float2 dn = LINESOBEL_tex(pos).xy;
		float2 dd = (dn / (length(dn) + 0.01)) * d * relstr; //Quasi-normalization for large vectors, avoids divide by zero
		pos -= dd;
	}

	return HOOKED_tex(pos);

}

kernel void Anime4K_Thin_Fast_pass7_Anime4K_v3_2_Thin_Fast_Warp(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINESOBEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass7(mtlPos, textureSampler, HOOKED, LINESOBEL, MAIN), gid);
}

