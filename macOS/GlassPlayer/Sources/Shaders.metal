// ---------------------------------------------------------------------------
// Shaders.metal – Metal Shading Language 3.0 Display Pipeline
//
// Glass Player – Native Apple Silicon Metal 3 implementation.
// Replaces all legacy OpenGL/GLSL vertex and fragment shaders with MSL 3.0.
//
// These shaders render the video frame (received via IOSurface-backed
// MTLTexture) onto a fullscreen quad displayed by CAMetalLayer.
//
// Metal NDC Z-axis: [0, 1] (OpenGL used [-1, 1]).
// Projection-matrix depth correction is applied here (Z = 0.5 in clip space).
// ---------------------------------------------------------------------------

#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Vertex output / Fragment input – interpolated per-pixel data
// ---------------------------------------------------------------------------
struct VertexOut {
    float4 position [[position]];   // Clip-space position
    float2 texCoord;                // UV coordinate for video texture sampling
};

// ---------------------------------------------------------------------------
// [[vertex]] fullscreenVertex
//
// Generates a fullscreen triangle-strip quad entirely from vertex_id.
// No vertex buffer is required (Metal 3 best practice for screen-space passes).
// This replaces OpenGL's glGenBuffers/glBindBuffer/glBufferData VBO setup.
//
// Metal NDC: X ∈ [-1,1], Y ∈ [-1,1], Z ∈ [0,1].
// Z is set to 0.5 to sit in the center of Metal's depth range, avoiding
// the clipping artifact that would occur if we used OpenGL's Z=0 (which
// maps to the near-clip plane in Metal's [0,1] NDC).
// ---------------------------------------------------------------------------
vertex VertexOut fullscreenVertex(uint vid [[vertex_id]]) {
    // Triangle strip: 4 vertices → fullscreen quad (no index buffer needed)
    const float2 positions[4] = {
        float2(-1.0, -1.0),   // bottom-left  (clip space)
        float2( 1.0, -1.0),   // bottom-right
        float2(-1.0,  1.0),   // top-left
        float2( 1.0,  1.0),   // top-right
    };

    // UV coordinates: Metal textures use top-left origin (0,0).
    // mpv renders with FLIP_Y=0 so OpenGL FBO row 0 (bottom of frame) is
    // at the start of IOSurface memory. Metal reads this as UV (0,0) at top,
    // which corresponds to the bottom of the video frame. To display correctly,
    // the V axis is flipped: screen-bottom → UV v=1 (top of video data),
    // screen-top → UV v=0 (bottom of video data / top of frame visually).
    const float2 texCoords[4] = {
        float2(0.0, 1.0),     // bottom-left  vertex → sample bottom of texture (= top of video)
        float2(1.0, 1.0),     // bottom-right vertex → sample bottom-right
        float2(0.0, 0.0),     // top-left     vertex → sample top of texture (= bottom of video)
        float2(1.0, 0.0),     // top-right    vertex → sample top-right
    };

    VertexOut out;
    out.position = float4(positions[vid], 0.5, 1.0);  // Z=0.5: Metal NDC [0,1]
    out.texCoord = texCoords[vid];
    return out;
}

// ---------------------------------------------------------------------------
// [[fragment]] textureFragment
//
// Samples the video frame texture with bilinear filtering and edge clamping.
// The texture is an IOSurface-backed MTLTexture shared with mpv's renderer
// via Apple Silicon Unified Memory (zero-copy).
//
// Replaces the implicit OpenGL fragment output (gl_FragColor) with an
// explicit [[stage_in]] + texture binding. The constexpr sampler is compiled
// into the pipeline state at MSL compile time (no runtime sampler creation).
// ---------------------------------------------------------------------------
fragment float4 textureFragment(VertexOut in [[stage_in]],
                                texture2d<float, access::sample> videoFrame [[texture(0)]]) {
    // Statically compiled sampler – replaces OpenGL's glTexParameter calls.
    // Bilinear filtering with edge clamping for clean video display.
    constexpr sampler linearSampler(filter::linear,
                                    mip_filter::none,
                                    address::clamp_to_edge);
    return videoFrame.sample(linearSampler, in.texCoord);
}
