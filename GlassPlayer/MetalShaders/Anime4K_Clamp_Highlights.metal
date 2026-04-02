// Auto-generated from GLSL using translate_anime4k_shaders.py
// Texture binding: BINDS=[0..N-1], MAIN=[N if applicable], OUTPUT=[last]
// Source: Anime4K_Clamp_Highlights.glsl
// Shaders: 3

// Shader: Anime4K-v4.0-De-Ring-Compute-Statistics
// Function: Anime4Kv40DeRingComputeStatistics
// BINDS: ['HOOKED']
// HOOK: MAIN
// SAVE: STATSMAX
// Input textures: ['HOOKED', 'MAIN']
// Output texture: STATSMAX
// Texture indices: BINDS=0..0, MAIN=1, OUTPUT=2

#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define HOOKED_pos MAIN_pos
#define HOOKED_size MAIN_size
#define HOOKED_pt MAIN_pt
#define HOOKED_tex(pos) MAIN_tex(pos)
#define HOOKED_texOff(off) MAIN_texOff(off)

#define HOOKED_pos mtlPos
#define HOOKED_size float2(HOOKED.get_width(), HOOKED.get_height())
#define HOOKED_pt (float2(1, 1) / HOOKED_size)
#define HOOKED_tex(pos) HOOKED.sample(textureSampler, pos)
#define HOOKED_texOff(off) HOOKED_tex(HOOKED_pos + HOOKED_pt * float2(off))

#define KERNELSIZE 5 //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE 2 //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).
float get_luma(float2 mtlPos, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN, sampler textureSampler, vec4 rgba) {
return dot(vec4(0.299, 0.587, 0.114, 0.0), rgba);
}
vec4 hook(float2 mtlPos, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> MAIN, sampler textureSampler) {
float gmax = 0.0;
for (int i=0; i<KERNELSIZE; i++) {
float g = get_luma(mtlPos, HOOKED, MAIN, textureSampler, MAIN_texOff(vec2(i - KERNELHALFSIZE, 0)));
gmax = max(g, gmax);
}
return vec4(gmax, 0.0, 0.0, 0.0);
}
kernel void Anime4Kv40DeRingComputeStatistics(
    texture2d<float, access::sample> HOOKED [[texture(0)]], texture2d<float, access::sample> MAIN [[texture(1)]], texture2d<float, access::write> output [[texture(2)]], uint2 gid [[thread_position_in_grid]], sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook(mtlPos, HOOKED, MAIN, textureSampler), gid);
}


// Shader: Anime4K-v4.0-De-Ring-Compute-Statistics
// Function: Anime4Kv40DeRingComputeStatistics_pass1
// BINDS: ['HOOKED', 'STATSMAX']
// HOOK: MAIN
// SAVE: STATSMAX
// Input textures: ['HOOKED', 'STATSMAX', 'MAIN']
// Output texture: STATSMAX
// Texture indices: BINDS=0..1, MAIN=2, OUTPUT=3

#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define HOOKED_pos MAIN_pos
#define HOOKED_size MAIN_size
#define HOOKED_pt MAIN_pt
#define HOOKED_tex(pos) MAIN_tex(pos)
#define HOOKED_texOff(off) MAIN_texOff(off)

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

#define KERNELSIZE 5 //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE 2 //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).
vec4 hook_pass1(float2 mtlPos, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> STATSMAX, texture2d<float, access::sample> MAIN, sampler textureSampler) {
float gmax = 0.0;
for (int i=0; i<KERNELSIZE; i++) {
float g = STATSMAX_texOff(vec2(0, i - KERNELHALFSIZE)).x;
gmax = max(g, gmax);
}
return vec4(gmax, 0.0, 0.0, 0.0);
}
kernel void Anime4Kv40DeRingComputeStatistics_pass1(
    texture2d<float, access::sample> HOOKED [[texture(0)]], texture2d<float, access::sample> STATSMAX [[texture(1)]], texture2d<float, access::sample> MAIN [[texture(2)]], texture2d<float, access::write> output [[texture(3)]], uint2 gid [[thread_position_in_grid]], sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass1(mtlPos, HOOKED, STATSMAX, MAIN, textureSampler), gid);
}


// Shader: Anime4K-v4.0-De-Ring-Clamp
// Function: Anime4Kv40DeRingClamp_pass2
// BINDS: ['HOOKED', 'STATSMAX']
// HOOK: MAIN
// SAVE: None
// Input textures: ['HOOKED', 'STATSMAX', 'MAIN']
// Output texture: output
// Texture indices: BINDS=0..1, MAIN=2, OUTPUT=3

#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define HOOKED_pos MAIN_pos
#define HOOKED_size MAIN_size
#define HOOKED_pt MAIN_pt
#define HOOKED_tex(pos) MAIN_tex(pos)
#define HOOKED_texOff(off) MAIN_texOff(off)

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

float get_luma(float2 mtlPos, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> STATSMAX, texture2d<float, access::sample> MAIN, sampler textureSampler, vec4 rgba) {
return dot(vec4(0.299, 0.587, 0.114, 0.0), rgba);
}
vec4 hook_pass2(float2 mtlPos, texture2d<float, access::sample> HOOKED, texture2d<float, access::sample> STATSMAX, texture2d<float, access::sample> MAIN, sampler textureSampler) {
float current_luma = get_luma(mtlPos, HOOKED, STATSMAX, MAIN, textureSampler, HOOKED_tex(HOOKED_pos));
float new_luma = min(current_luma, STATSMAX_tex(HOOKED_pos).x);
return HOOKED_tex(HOOKED_pos) - (current_luma - new_luma);
}
kernel void Anime4Kv40DeRingClamp_pass2(
    texture2d<float, access::sample> HOOKED [[texture(0)]], texture2d<float, access::sample> STATSMAX [[texture(1)]], texture2d<float, access::sample> MAIN [[texture(2)]], texture2d<float, access::write> output [[texture(3)]], uint2 gid [[thread_position_in_grid]], sampler textureSampler [[sampler(0)]]) {
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook_pass2(mtlPos, HOOKED, STATSMAX, MAIN, textureSampler), gid);
}


