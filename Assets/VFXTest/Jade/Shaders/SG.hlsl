#pragma once

#define PI 3.14159265359

struct SphericalGaussian
{
    half3 Amplitude;
    half3 Axis;
    half Sharpness;
};

half3 EvaluateSG(in SphericalGaussian sg, in float3 dir)
{
    half cosAngle = dot(dir, sg.Axis);
    return sg.Amplitude * exp(sg.Sharpness * (cosAngle - 1.0f));
}

half DotCosineLobe(SphericalGaussian sg, half3 normal)
{
    const half muDotN = dot(sg.Axis, normal);
    const half c0 = 0.36;
    const half c1 = 0.25 / c0;

    half eml = exp(-sg.Sharpness);
    half eml2 = eml * eml;
    half rl = rcp(sg.Sharpness);

    half scale = 1.0f + 2.0f * eml2 - rl;
    half bias = (eml - eml2) * rl - eml2;

    half x = sqrt(1.0 - scale);
    half x0 = c0 * muDotN;
    half x1 = c1 * x;

    half n = x0 + x1;
    half y = (abs(x0) <= x1) ? n * n / x : saturate(muDotN);

    return scale * y + bias;
}

SphericalGaussian MakeNormalizedSG(half3 lightDir, half sharpness)
{
    SphericalGaussian sg;
    sg.Axis = lightDir;
    sg.Sharpness = sharpness;
    sg.Amplitude = sg.Sharpness / ((2 * PI) * (1 - exp(-2 * sg.Sharpness)));
    return sg;
}

half3 SGDiffuseLighting(half3 normal, half3 lightDir, half3 scatterAmount)
{
    SphericalGaussian sgR = MakeNormalizedSG(lightDir, 1 / max(scatterAmount.x, 0.0001));
    SphericalGaussian sgG = MakeNormalizedSG(lightDir, 1 / max(scatterAmount.y, 0.0001));
    SphericalGaussian sgB = MakeNormalizedSG(lightDir, 1 / max(scatterAmount.z, 0.0001));

    half3 diffuse = half3(DotCosineLobe(sgR, normal), DotCosineLobe(sgG, normal), DotCosineLobe(sgB, normal));

    // Tone map
    half3 x = max(0, diffuse - 0.004);
    diffuse = (x * (6.2 * x + 0.5)) / (x * (6.2 * x + 1.7) + 0.06);
    return diffuse;
}