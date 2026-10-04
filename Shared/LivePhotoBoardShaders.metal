#include <metal_stdlib>
using namespace metal;

struct TileInstance {
    float4 destinationRect;
    float4 sourceRect;
    float4 borderColor;
    float cornerRadius;
    float opacity;
    float contentInset;
    float borderWidth;
};

struct FrameUniforms {
    float4 viewAndContentSize;
    float4 textureAndDrawableSize;
    float4 visibleTextureRect;
};

struct VertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
    float2 localCoordinate;
    float2 tileSize;
    float4 borderColor;
    float cornerRadius;
    float opacity;
    float contentInset;
    float borderWidth;
};

vertex VertexOut livePhotoVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device TileInstance *tiles [[buffer(0)]],
    constant FrameUniforms &frame [[buffer(1)]]
) {
    constexpr float2 corners[] = {
        float2(0, 0),
        float2(1, 0),
        float2(0, 1),
        float2(1, 0),
        float2(1, 1),
        float2(0, 1)
    };

    TileInstance tile = tiles[instanceID];
    float2 corner = corners[vertexID];
    float2 viewSize = frame.viewAndContentSize.xy;
    float2 contentSize = frame.viewAndContentSize.zw;
    float2 textureSize = frame.textureAndDrawableSize.xy;
    float2 drawableSize = frame.textureAndDrawableSize.zw;
    float4 visibleRect = frame.visibleTextureRect;

    float boardAspect = contentSize.x / contentSize.y;
    float textureAspect =
        (textureSize.x * visibleRect.z) /
        (textureSize.y * visibleRect.w);
    float2 uvScale = visibleRect.zw;
    float2 uvOffset = visibleRect.xy;
    if (textureAspect > boardAspect) {
        float width = boardAspect / textureAspect;
        uvScale.x *= width;
        uvOffset.x += visibleRect.z * (1 - width) / 2;
    } else {
        float height = textureAspect / boardAspect;
        uvScale.y *= height;
        uvOffset.y += visibleRect.w * (1 - height) / 2;
    }

    float2 destinationMin = tile.destinationRect.xy;
    float2 destinationMax = tile.destinationRect.xy + tile.destinationRect.zw;
    bool isSeamless = tile.cornerRadius <= 0.001 &&
        tile.contentInset <= 0.001 &&
        tile.borderWidth <= 0.001;
    if (isSeamless) {
        float2 displayScale = drawableSize / viewSize;
        destinationMin = round(destinationMin * displayScale) / displayScale;
        destinationMax = round(destinationMax * displayScale) / displayScale;
    }
    float2 destination = mix(destinationMin, destinationMax, corner);
    float2 normalizedPosition = destination / viewSize;

    VertexOut output;
    output.position = float4(
        normalizedPosition.x * 2 - 1,
        1 - normalizedPosition.y * 2,
        0,
        1
    );
    output.textureCoordinate =
        uvOffset + mix(tile.sourceRect.xy, tile.sourceRect.zw, corner) * uvScale;
    output.tileSize = destinationMax - destinationMin;
    output.localCoordinate = corner * output.tileSize;
    output.borderColor = tile.borderColor;
    output.cornerRadius = tile.cornerRadius;
    output.opacity = tile.opacity;
    output.contentInset = tile.contentInset;
    output.borderWidth = tile.borderWidth;
    return output;
}

bool outsideRoundedRectangle(float2 coordinate, float2 size, float radius) {
    if (any(coordinate < 0) || any(coordinate > size)) {
        return true;
    }
    float2 edgeDistance = min(coordinate, size - coordinate);
    if (radius > 0 && edgeDistance.x < radius && edgeDistance.y < radius) {
        return length(float2(radius) - edgeDistance) > radius;
    }
    return false;
}

fragment float4 livePhotoFragment(
    VertexOut input [[stage_in]],
    texture2d<float> videoTexture [[texture(0)]],
    sampler videoSampler [[sampler(0)]]
) {
    if (outsideRoundedRectangle(input.localCoordinate, input.tileSize, input.cornerRadius)) {
        discard_fragment();
    }

    float2 borderCoordinate = input.localCoordinate - input.borderWidth;
    float2 borderSize = input.tileSize - 2 * input.borderWidth;
    float borderRadius = max(0.0, input.cornerRadius - input.borderWidth);
    if (input.borderWidth > 0 && outsideRoundedRectangle(borderCoordinate, borderSize, borderRadius)) {
        return float4(input.borderColor.rgb, input.borderColor.a * input.opacity);
    }

    float2 insetCoordinate = input.localCoordinate - input.contentInset;
    float2 insetSize = input.tileSize - 2 * input.contentInset;
    float insetRadius = max(0.0, input.cornerRadius - input.contentInset);
    if (outsideRoundedRectangle(insetCoordinate, insetSize, insetRadius)) {
        discard_fragment();
    }
    float4 color = videoTexture.sample(videoSampler, input.textureCoordinate);
    return float4(color.rgb, color.a * input.opacity);
}
