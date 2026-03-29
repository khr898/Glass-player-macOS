// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v3.2-Darken-DoG-(HQ)-Luma

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

kernel void Anime4K_Darken_HQ_pass0_Anime4K_v3_2_Darken_DoG_HQ_Luma(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, MAIN), gid);
}


// DESC: Anime4K-v3.2-Darken-DoG-(HQ)-Difference-X

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

    // SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0  (computed in kernel below)

    // #define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.  (computed dynamically below)
    // #define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).  (computed dynamically below)
    // #define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.  (computed dynamically below)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	float scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float comp_gaussian_x(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN) {

	float g = 0.0;
	float gn = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float di = float(i - KERNELHALFSIZE);
		float gf = gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, di, SPATIAL_SIGMA, 0.0);

		g = g + LINELUMA_texOff(float2(di, 0.0)).x * gf;
		gn = gn + gf;

	}

	return g / gn;
}

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN) {
    return float4(comp_gaussian_x(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Darken_HQ_pass1_Anime4K_v3_2_Darken_DoG_HQ_Difference_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    const float SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0;
    const int KERNELSIZE = max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1;
    const int KERNELHALFSIZE = int(KERNELSIZE / 2);
    const int KERNELLEN = KERNELSIZE * KERNELSIZE;
    output.write(hook(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN), gid);
}


// DESC: Anime4K-v3.2-Darken-DoG-(HQ)-Difference-Y

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

#define LINEKERNEL_pos mtlPos
#define LINEKERNEL_size float2(LINEKERNEL.get_width(), LINEKERNEL.get_height())
#define LINEKERNEL_pt (float2(1, 1) / LINEKERNEL_size)
#define LINEKERNEL_tex(pos) LINEKERNEL.sample(textureSampler, pos)
#define LINEKERNEL_texOff(off) LINEKERNEL_tex(LINEKERNEL_pos + LINEKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

    // SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0  (computed in kernel below)

    // #define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.  (computed dynamically below)
    // #define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).  (computed dynamically below)
    // #define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.  (computed dynamically below)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	float scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float comp_gaussian_y(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN) {

	float g = 0.0;
	float gn = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float di = float(i - KERNELHALFSIZE);
		float gf = gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, LINEKERNEL, MAIN, di, SPATIAL_SIGMA, 0.0);

		g = g + LINEKERNEL_texOff(float2(0.0, di)).x * gf;
		gn = gn + gf;

	}

	return g / gn;
}

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN) {
    return float4(min(LINELUMA_tex(HOOKED_pos).x - comp_gaussian_y(mtlPos, textureSampler, HOOKED, LINELUMA, LINEKERNEL, MAIN), 0.0), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Darken_HQ_pass2_Anime4K_v3_2_Darken_DoG_HQ_Difference_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> LINEKERNEL [[texture(2)]],
    texture2d<float, access::sample> MAIN [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    const float SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0;
    const int KERNELSIZE = max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1;
    const int KERNELHALFSIZE = int(KERNELSIZE / 2);
    const int KERNELLEN = KERNELSIZE * KERNELSIZE;
    output.write(hook(mtlPos, textureSampler, HOOKED, LINELUMA, LINEKERNEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Darken-DoG-(HQ)-Gaussian-X

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

#define LINEKERNEL_pos mtlPos
#define LINEKERNEL_size float2(LINEKERNEL.get_width(), LINEKERNEL.get_height())
#define LINEKERNEL_pt (float2(1, 1) / LINEKERNEL_size)
#define LINEKERNEL_tex(pos) LINEKERNEL.sample(textureSampler, pos)
#define LINEKERNEL_texOff(off) LINEKERNEL_tex(LINEKERNEL_pos + LINEKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

    // SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0  (computed in kernel below)

    // #define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.  (computed dynamically below)
    // #define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).  (computed dynamically below)
    // #define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.  (computed dynamically below)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	float scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float comp_gaussian_x(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN) {

	float g = 0.0;
	float gn = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float di = float(i - KERNELHALFSIZE);
		float gf = gaussian(mtlPos, textureSampler, HOOKED, LINEKERNEL, MAIN, di, SPATIAL_SIGMA, 0.0);

		g = g + LINEKERNEL_texOff(float2(di, 0.0)).x * gf;
		gn = gn + gf;

	}

	return g / gn;
}

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN) {
    return float4(comp_gaussian_x(mtlPos, textureSampler, HOOKED, LINEKERNEL, MAIN), 0.0, 0.0, 0.0);
}

kernel void Anime4K_Darken_HQ_pass3_Anime4K_v3_2_Darken_DoG_HQ_Gaussian_X(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINEKERNEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    const float SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0;
    const int KERNELSIZE = max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1;
    const int KERNELHALFSIZE = int(KERNELSIZE / 2);
    const int KERNELLEN = KERNELSIZE * KERNELSIZE;
    output.write(hook(mtlPos, textureSampler, HOOKED, LINEKERNEL, MAIN), gid);
}


// DESC: Anime4K-v3.2-Darken-DoG-(HQ)-Gaussian-Y

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

#define LINEKERNEL_pos mtlPos
#define LINEKERNEL_size float2(LINEKERNEL.get_width(), LINEKERNEL.get_height())
#define LINEKERNEL_pt (float2(1, 1) / LINEKERNEL_size)
#define LINEKERNEL_tex(pos) LINEKERNEL.sample(textureSampler, pos)
#define LINEKERNEL_texOff(off) LINEKERNEL_tex(LINEKERNEL_pos + LINEKERNEL_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

    // SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0  (computed in kernel below)

    // #define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.  (computed dynamically below)
    // #define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).  (computed dynamically below)
    // #define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.  (computed dynamically below)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	float scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float comp_gaussian_y(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN) {

	float g = 0.0;
	float gn = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float di = float(i - KERNELHALFSIZE);
		float gf = gaussian(mtlPos, textureSampler, HOOKED, LINEKERNEL, MAIN, di, SPATIAL_SIGMA, 0.0);

		g = g + LINEKERNEL_texOff(float2(0.0, di)).x * gf;
		gn = gn + gf;

	}

	return g / gn;
}



#define STRENGTH 1.5 //Line darken proportional strength, higher is darker.

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINEKERNEL, texture2d<float, access::sample> MAIN) {
	//This trick is only possible if the inverse Y->RGB matrix has 1 for every row... (which is the case for BT.709)
	//Otherwise we would need to convert RGB to YUV, modify Y then convert back to RGB.
    return HOOKED_tex(HOOKED_pos) + (comp_gaussian_y(mtlPos, textureSampler, HOOKED, LINEKERNEL, MAIN) * STRENGTH);
}

kernel void Anime4K_Darken_HQ_pass4_Anime4K_v3_2_Darken_DoG_HQ_Gaussian_Y(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINEKERNEL [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    const float SPATIAL_SIGMA = 1.0 * float(HOOKED.get_height()) / 1080.0;
    const int KERNELSIZE = max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1;
    const int KERNELHALFSIZE = int(KERNELSIZE / 2);
    const int KERNELLEN = KERNELSIZE * KERNELSIZE;
    output.write(hook(mtlPos, textureSampler, HOOKED, LINEKERNEL, MAIN), gid);
}

