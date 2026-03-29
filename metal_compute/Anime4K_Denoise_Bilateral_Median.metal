// Translated from Anime4K GLSL to Metal Compute Shaders
// Original: MIT License / Unlicense - bloc97
// Translation matches Anime4K.swift / MPVShader.swift architecture

// DESC: Anime4K-v3.2-Denoise-Bilateral-Median-Luma

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

kernel void Anime4K_Denoise_Bilateral_Median_pass0_Anime4K_v3_2_Denoise_Bilateral_Median_Luma(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> MAIN [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass0(mtlPos, textureSampler, HOOKED, MAIN), gid);
}


// DESC: Anime4K-v3.2-Denoise-Bilateral-Median-Apply

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

#define INTENSITY_SIGMA 0.1 //Intensity window size, higher is stronger denoise, must be a positive real number
#define SPATIAL_SIGMA 1.0 //Spatial window size, higher is stronger denoise, must be a positive real number.
#define HISTOGRAM_REGULARIZATION 0.0 //Histogram regularization window size, higher values approximate a bilateral "closest-to-mean" filter.

#define INTENSITY_POWER_CURVE 1.0 //Intensity window power curve. Setting it to 0 will make the intensity window treat all intensities equally, while increasing it will make the window narrower in darker intensities and wider in brighter intensities.

#define KERNELSIZE int(max(int(SPATIAL_SIGMA), 1) * 2 + 1) //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).
#define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.

#define GETOFFSET(i) float2((i % KERNELSIZE) - KERNELHALFSIZE, (i / KERNELSIZE) - KERNELHALFSIZE)

float gaussian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float x, float s, float m) {
	float scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float4 getMedian(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN, float4 v[KERNELLEN], float w[KERNELLEN], float n) {

	for (int i=0; i<KERNELLEN; i++) {
		float w_above = 0.0;
		float w_below = 0.0;
		for (int j=0; j<KERNELLEN; j++) {
			if (v[j].x > v[i].x) {
				w_above += w[j];
			} else if (v[j].x < v[i].x) {
				w_below += w[j];
			}
		}

		if ((n - w_above) / n >= 0.5 && w_below / n <= 0.5) {
			return v[i];
		}
	}
}

static float4 hook_pass1(float2 mtlPos, sampler textureSampler, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> LINELUMA, texture2d<float, access::sample> MAIN) {
	float4 histogram_v[KERNELLEN];
	float histogram_l[KERNELLEN];
	float histogram_w[KERNELLEN];
	float n = 0.0;

	float vc = LINELUMA_tex(HOOKED_pos).x;

	float is = pow(vc + 0.0001, INTENSITY_POWER_CURVE) * INTENSITY_SIGMA;
	float ss = SPATIAL_SIGMA;

	for (int i=0; i<KERNELLEN; i++) {
		float2 ipos = GETOFFSET(i);
		histogram_v[i] = HOOKED_texOff(ipos);
		histogram_l[i] = LINELUMA_texOff(ipos).x;
		histogram_w[i] = gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, histogram_l[i], is, vc) * gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, length(ipos), ss, 0.0);
		n += histogram_w[i];
	}

	if (HISTOGRAM_REGULARIZATION > 0.0) {
		float histogram_wn[KERNELLEN];
		n = 0.0;

		for (int i=0; i<KERNELLEN; i++) {
			histogram_wn[i] = 0.0;
		}

		for (int i=0; i<KERNELLEN; i++) {
			histogram_wn[i] += gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, 0.0, HISTOGRAM_REGULARIZATION, 0.0) * histogram_w[i];
			for (int j=(i+1); j<KERNELLEN; j++) {
				float d = gaussian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, histogram_l[j], HISTOGRAM_REGULARIZATION, histogram_l[i]);
				histogram_wn[j] += d * histogram_w[i];
				histogram_wn[i] += d * histogram_w[j];
			}
			n += histogram_wn[i];
		}

		return getMedian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, histogram_v, histogram_wn, n);
	}

	return getMedian(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN, histogram_v, histogram_w, n);
}

kernel void Anime4K_Denoise_Bilateral_Median_pass1_Anime4K_v3_2_Denoise_Bilateral_Median_Apply(
    texture2d<float, access::sample> HOOKED [[texture(0)]],
    texture2d<float, access::sample> LINELUMA [[texture(1)]],
    texture2d<float, access::sample> MAIN [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    uint2 gid [[thread_position_in_grid]],
    sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass1(mtlPos, textureSampler, HOOKED, LINELUMA, MAIN), gid);
}

