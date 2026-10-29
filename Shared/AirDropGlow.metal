#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float cellHash(float2 cell) {
    cell = fract(cell * float2(123.34, 456.21));
    cell += dot(cell, cell + 45.32);
    return fract(cell.x * cell.y);
}

static float valueNoise(float2 point) {
    float2 cell = floor(point);
    float2 local = fract(point);
    float2 smoothed = local * local * (3.0 - 2.0 * local);
    float a = cellHash(cell);
    float b = cellHash(cell + float2(1.0, 0.0));
    float c = cellHash(cell + float2(0.0, 1.0));
    float d = cellHash(cell + float2(1.0, 1.0));
    return mix(mix(a, b, smoothed.x), mix(c, d, smoothed.x), smoothed.y);
}

static float3 dispersionTint(float signedOffset) {
    float3 innerEdge = float3(0.78, 1.00, 0.84);
    float3 outerEdge = float3(0.96, 0.82, 1.00);
    float3 neutral = float3(1.0);
    return signedOffset < 0.0
        ? mix(neutral, innerEdge, clamp(-signedOffset, 0.0, 1.0))
        : mix(neutral, outerEdge, clamp(signedOffset, 0.0, 1.0));
}

constant float sweepOriginOffset = 0.45;
constant float sweepSpeed = 1.1;
constant float sweepDuration = 1.3;

static float rippleDisplacement(float travelledDistance, float elapsed, float amplitude, float speed) {
    float frequency = 12.0;
    float decay = 5.0;
    float localTime = max(0.0, elapsed - travelledDistance / speed);
    return amplitude * sin(frequency * localTime) * exp(-decay * localTime) * step(0.0001, localTime);
}

[[ stitchable ]] half4 contentRipple(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float2 layerSize,
    float elapsed,
    float amplitude,
    float horizontalDirection
) {
    float scale = max(layerSize.x, layerSize.y);
    float2 sweepOrigin = float2(origin.x - horizontalDirection * sweepOriginOffset * scale, origin.y);
    float2 offset = position - sweepOrigin;
    float distanceFromOrigin = length(offset);
    float2 direction = distanceFromOrigin > 0.001 ? offset / distanceFromOrigin : float2(0.0);
    float travelledDistance = max(distanceFromOrigin - sweepOriginOffset * scale, 0.0);
    float displacement = rippleDisplacement(travelledDistance, elapsed, amplitude, sweepSpeed * scale);
    float2 samplePosition = position + displacement * direction;
    float2 fringe = direction * displacement * 0.22;
    float2 lowerBound = float2(0.5);
    float2 upperBound = layerSize - 0.5;

    half4 redSample = layer.sample(clamp(samplePosition + fringe, lowerBound, upperBound));
    half4 greenSample = layer.sample(clamp(samplePosition, lowerBound, upperBound));
    half4 blueSample = layer.sample(clamp(samplePosition - fringe, lowerBound, upperBound));
    half4 color = half4(redSample.r, greenSample.g, blueSample.b, greenSample.a);
    color.rgb += half(0.18 * displacement / max(amplitude, 0.001)) * color.a;
    return color;
}

[[ stitchable ]] half4 airDropGlow(
    float2 position,
    half4 sourceColor,
    float2 canvasSize,
    float2 origin,
    float time,
    float intensity,
    float waveElapsed,
    float horizontalDirection
) {
    float scale = max(canvasSize.x, canvasSize.y);
    float2 offset = (position - origin) / scale;
    float distanceFromOrigin = length(offset);

    float breathing = 1.0 + 0.05 * sin(time * 2.4) + 0.025 * sin(time * 4.1 + 1.3);
    float isLandscape = step(canvasSize.y, canvasSize.x);
    float bloomRadius = max(intensity * mix(0.26, 0.42, isLandscape) * breathing, 0.0001);
    float2 stretched = float2(offset.x * 1.35, offset.y * 0.72);
    float stretchedDistance = length(stretched);

    float shimmer = 0.85 + 0.3 * valueNoise(position / 38.0 + float2(time * 0.6 * horizontalDirection, time * 0.25));
    float core = exp(-pow(stretchedDistance / (bloomRadius * 0.55), 2.0)) * intensity;
    float halo = exp(-pow(stretchedDistance / bloomRadius, 2.0) * 1.6) * intensity * 0.55 * shimmer;
    float edgeLine = exp(-pow(abs(position.x - origin.x) / 3.0, 2.0))
        * exp(-pow((position.y - origin.y) / (scale * bloomRadius * 1.3), 2.0)) * intensity;

    float2 sweepOrigin = float2(origin.x - horizontalDirection * sweepOriginOffset * scale, origin.y) / scale;
    float sweepDistance = length(position / scale - sweepOrigin);
    float waveRadius = sweepOriginOffset + waveElapsed * sweepSpeed;
    float waveIsActive = step(0.0001, waveElapsed) * step(waveElapsed, sweepDuration);
    float waveFade = pow(clamp(1.0 - waveElapsed / sweepDuration, 0.0, 1.0), 0.8) * waveIsActive;
    float bandWidth = 0.03;
    float signedBandOffset = (sweepDistance - waveRadius) / bandWidth;
    float waveBand = exp(-signedBandOffset * signedBandOffset) * waveFade * 0.6;
    float fringeBand = exp(-pow(abs(signedBandOffset) - 1.5, 2.0) * 1.2) * waveFade * 0.35;
    float flash = exp(-pow(distanceFromOrigin / 0.3, 2.0)) * exp(-waveElapsed * 6.0) * waveIsActive * 0.8;

    float peerIsRight = step(horizontalDirection, 0.0);
    float distanceToPeerEdge = peerIsRight > 0.5 ? canvasSize.x - position.x : position.x;
    float distanceToTop = position.y;
    float distanceToBottom = canvasSize.y - position.y;
    float distanceToNearestRim = min(distanceToPeerEdge, min(distanceToTop, distanceToBottom));
    float pathAlongPeerEdge = abs(position.y - origin.y);
    float pathAlongTop = origin.y + distanceToPeerEdge;
    float pathAlongBottom = (canvasSize.y - origin.y) + distanceToPeerEdge;
    float perimeterPath = distanceToPeerEdge <= min(distanceToTop, distanceToBottom)
        ? pathAlongPeerEdge
        : (distanceToTop < distanceToBottom ? pathAlongTop : pathAlongBottom);
    float rimFalloff = scale * 0.5;
    float rimThickness = scale * mix(0.03, 0.05, isLandscape) * exp(-perimeterPath / rimFalloff) + 1.5;
    float rimShimmer = 0.85 + 0.15 * valueNoise(float2(perimeterPath / 60.0 - time * 1.2, time * 0.4));
    float screenRim = exp(-distanceToNearestRim / rimThickness) * exp(-perimeterPath / (rimFalloff * 1.3)) * intensity * 0.85 * rimShimmer;

    float2 sparkleCell = floor(position / 18.0);
    float sparkleSeed = cellHash(sparkleCell);
    float2 sparkleCenter = (sparkleCell + 0.2 + 0.6 * float2(cellHash(sparkleCell + 7.1), cellHash(sparkleCell + 3.7))) * 18.0;
    float2 sparkleDelta = abs(position - sparkleCenter);
    float sparkleStar = exp(-pow(length(sparkleDelta) / 1.1, 2.0))
        + 0.5 * exp(-sparkleDelta.x / 0.6 - sparkleDelta.y / 4.0)
        + 0.5 * exp(-sparkleDelta.y / 0.6 - sparkleDelta.x / 4.0);
    float twinkle = step(0.9, sparkleSeed) * pow(0.5 + 0.5 * sin(time * 6.0 + sparkleSeed * 90.0), 4.0);
    float sparkleRegion = (1.0 - smoothstep(bloomRadius * 0.4, bloomRadius * 1.2, stretchedDistance)) * intensity
        + exp(-signedBandOffset * signedBandOffset * 0.15) * waveFade;
    float sparkle = min(sparkleStar, 1.0) * twinkle * sparkleRegion;

    float whiteAmount = core + halo + edgeLine + waveBand + flash + sparkle + screenRim;
    float fringeAmount = fringeBand;
    float coverage = whiteAmount + fringeAmount;
    if (coverage < 0.002) {
        return half4(0.0);
    }

    float3 glowTone = mix(float3(1.0), float3(0.84, 0.97, 0.90), clamp(stretchedDistance / bloomRadius, 0.0, 1.0));
    float3 color = (glowTone * (core + halo + flash) + float3(0.92, 1.0, 0.95) * screenRim
        + float3(1.0) * (edgeLine + sparkle + waveBand)
        + dispersionTint(sign(signedBandOffset)) * fringeAmount) / coverage;
    float alpha = clamp(coverage, 0.0, 1.0);
    return half4(half3(color * alpha), half(alpha));
}
