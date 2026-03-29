// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v3.2-Denoise-Bilateral-Mean

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

#define INTENSITY_SIGMA 0.1 //Intensity window size, higher is stronger denoise, must be a positive real number
#define SPATIAL_SIGMA 1.0 //Spatial window size, higher is stronger denoise, must be a positive real number.

#define INTENSITY_POWER_CURVE 1.0 //Intensity window power curve. Setting it to 0 will make the intensity window treat all intensities equally, while increasing it will make the window narrower in darker intensities and wider in brighter intensities.

#define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).
#define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.

#define GETOFFSET(i) float2((i % KERNELSIZE) - KERNELHALFSIZE, (i / KERNELSIZE) - KERNELHALFSIZE)

float4 gaussian_vec(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN, float4 x, float4 s, float4 m) {
	float4 scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	float scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float4 hook(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN) {
	float4 sum = float4(0.0);
	float4 n = float4(0.0);

	float4 vc = HOOKED_tex(HOOKED_pos);

	float4 is = pow(vc + 0.0001, float4(INTENSITY_POWER_CURVE)) * INTENSITY_SIGMA;
	float ss = SPATIAL_SIGMA;

	for (int i=0; i<KERNELLEN; i++) {
		float2 ipos = GETOFFSET(i);
		float4 v = HOOKED_texOff(ipos);
		float4 d = gaussian_vec(mtlPos, textureSampler, HOOKED, MAIN, v, is, vc) * gaussian(mtlPos, textureSampler, HOOKED, MAIN, length(ipos), ss, 0.0);
		sum += d * v;
		n += d;
	}

	return sum / n;
}

kernel void Anime4K_Denoise_Bilateral_Mean_pass0_Anime4K_v3_2_Denoise_Bilateral_Mean(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, textureSampler, HOOKED, MAIN), gid);
}

