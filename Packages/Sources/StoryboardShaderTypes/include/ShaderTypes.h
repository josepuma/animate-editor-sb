//
//  ShaderTypes.h
//  Shared between Swift and the Metal shaders so both agree on memory layout.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

/// Buffer indices, matching the `[[buffer(n)]]` attributes in Shaders.metal.
typedef enum BufferIndex {
    BufferIndexInstances = 0,
    BufferIndexUniforms  = 1,
} BufferIndex;

/// Per-frame values shared by every sprite.
typedef struct {
    /// Maps osu! storyboard space to Metal clip space.
    matrix_float4x4 projection;
} Uniforms;

/// One sprite instance. The vertex shader expands each into a textured quad.
typedef struct {
    /// The sprite's origin in canvas coordinates: the point it is positioned,
    /// scaled and rotated about.
    vector_float2 position;
    /// Scaled half-extent, sign-flipped for horizontal or vertical mirroring.
    vector_float2 halfSize;
    /// Normalised anchor within the quad, (0, 0) top-left to (1, 1)
    /// bottom-right. The shader offsets the quad so this point lands on
    /// `position`, after scaling and before rotation — matching how osu!
    /// anchors a sprite to its origin.
    vector_float2 anchor;
    /// Rotation in radians, clockwise, matching osu!.
    float rotation;
    /// Slice index into the atlas array texture.
    uint32_t textureIndex;
    /// Premultiplied tint: rgb in [0, 1], a is opacity.
    vector_float4 color;
    /// Region of the atlas page holding this sprite: (u0, v0, u1, v1).
    /// Sprites share a page, so each samples only its own rectangle.
    vector_float4 uvRect;
} SpriteInstance;

#endif /* ShaderTypes_h */
