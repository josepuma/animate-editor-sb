//
//  Shaders.metal
//  Instanced textured-quad renderer for osu! storyboards.
//

#include <metal_stdlib>

using namespace metal;

// ─── Shared layout ───────────────────────────────────────────────────────────
//
// These mirror ShaderTypes.h. They are declared inline rather than included
// because this file is compiled from source at runtime, where no header search
// path exists. ShaderLayoutTests asserts the two definitions stay in step.

typedef enum BufferIndex {
    BufferIndexInstances = 0,
    BufferIndexUniforms  = 1,
} BufferIndex;

struct Uniforms {
    float4x4 projection;
};

struct SpriteInstance {
    float2 position;
    float2 halfSize;
    float2 anchor;
    float rotation;
    uint textureIndex;
    float4 color;
    float4 uvRect;
};

struct RasterizerData {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    uint textureIndex;
};

/// Unit quad corners in a Y-down space, matching osu! storyboard coordinates
/// where y grows towards the bottom of the screen.
/// Two triangles: 0-1-2 and 2-1-3.
constant float2 kQuadCorners[4] = {
    float2(-1.0, -1.0),  // top-left
    float2( 1.0, -1.0),  // top-right
    float2(-1.0,  1.0),  // bottom-left
    float2( 1.0,  1.0),  // bottom-right
};

/// Normalised texture coordinates for those corners. Both axes run in the same
/// direction as the quad, so the image is upright in a Y-down space.
constant float2 kQuadUVs[4] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 1.0),
};

constant ushort kTriangleIndices[6] = { 0, 1, 2, 2, 1, 3 };

vertex RasterizerData spriteVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant SpriteInstance *instances [[buffer(BufferIndexInstances)]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]])
{
    const SpriteInstance sprite = instances[instanceID];

    const ushort corner = kTriangleIndices[vertexID];
    const float2 unit = kQuadCorners[corner];

    // Scale by half-extent. A negative component mirrors the quad, which also
    // reverses winding — culling stays disabled so both faces draw.
    float2 local = unit * sprite.halfSize;

    // Shift the quad so its anchor sits on the origin. Doing this here, after
    // scaling and before rotation, is what keeps a scaling sprite pinned to its
    // origin: computing the offset on the CPU from an already-scaled size makes
    // it grow with the sprite and drift away.
    const float2 anchorOffset = (float2(0.5, 0.5) - sprite.anchor) * 2.0 * sprite.halfSize;
    local += anchorOffset;

    // Rotate clockwise on screen. In this Y-down space that is the standard
    // rotation matrix; osu! measures sprite rotation the same way.
    const float c = cos(sprite.rotation);
    const float s = sin(sprite.rotation);
    const float2 rotated = float2(
        local.x * c - local.y * s,
        local.x * s + local.y * c);

    const float4 world = float4(rotated + sprite.position, 0.0, 1.0);

    // Map the unit UV onto this sprite's rectangle inside the atlas page, so
    // only its own pixels are sampled rather than the whole page.
    const float2 unitUV = kQuadUVs[corner];
    const float2 uvMin = sprite.uvRect.xy;
    const float2 uvMax = sprite.uvRect.zw;

    RasterizerData out;
    out.position = uniforms.projection * world;
    out.texCoord = mix(uvMin, uvMax, unitUV);
    out.color = sprite.color;
    out.textureIndex = sprite.textureIndex;
    return out;
}

fragment float4 spriteFragment(
    RasterizerData in [[stage_in]],
    texture2d_array<float> atlas [[texture(0)]],
    sampler atlasSampler [[sampler(0)]])
{
    const float4 texel = atlas.sample(atlasSampler, in.texCoord, in.textureIndex);

    // Atlas pixels arrive already premultiplied from Core Graphics, so the
    // tint scales the stored colour directly. Multiplying rgb by alpha again
    // here would darken every partly transparent edge.
    return float4(texel.rgb * in.color.rgb * in.color.a, texel.a * in.color.a);
}

/// Fallback for sprites whose texture failed to load: a flat tinted quad.
fragment float4 spriteFragmentUntextured(RasterizerData in [[stage_in]])
{
    return float4(in.color.rgb * in.color.a, in.color.a);
}
