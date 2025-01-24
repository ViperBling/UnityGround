#pragma once

float3 GetWorldPosition(float rawDepth, float2 texCoord)
{
    float4 positionCS = float4(texCoord * 2.0 - 1.0 , rawDepth, 1.0);
#if UNITY_UV_STARTS_AT_TOP
    positionCS.y *= -1;
#endif
    float4 positionVS = mul(_InvProjectionMatrixSSR, positionCS);
    float4 positionWS = mul(_InvViewMatrixSSR, positionVS);
    positionWS /= positionWS.w;

    return positionWS.xyz;
}

inline float ScreenEdgeMask(float2 clipPos)
{
    float yDiff = 1 - abs(clipPos.y);
    float xDiff = 1 - abs(clipPos.x);

    UNITY_FLATTEN
    if (yDiff < 0 || xDiff < 0)
    {
        return 0;
    }

    float t1 = smoothstep(0, 0.2, yDiff);
    float t2 = smoothstep(0, 0.1, xDiff);

    return saturate(t1 * t2);
}

inline float RGB2Lum(float3 rgb)
{
    return (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b);
}



