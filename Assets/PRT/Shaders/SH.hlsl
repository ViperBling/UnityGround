#define PI          3.14159265358979323846

struct Surfel
{
    float3 position;
    float3 normal;
    float3 albedo;
    float skyMask;
};

// ref: https://www.shadertoy.com/view/lsfXWH
// ref: https://en.wikipedia.org/wiki/Table_of_spherical_harmonics
// Y_l_m(s), where l is the band and m the range in [-l..l] 
// return SH basis value of Y_l_m in direction s 
float SH(in int l, in int m, in float3 s)
{
    #define k01 0.2820947918    // sqrt(  1/PI)/2
    #define k02 0.4886025119    // sqrt(  3/PI)/2
    #define k03 1.0925484306    // sqrt( 15/PI)/2
    #define k04 0.3153915652    // sqrt(  5/PI)/4
    #define k05 0.5462742153    // sqrt( 15/PI)/4

    float x = s.x;
    float y = s.z;
    float z = s.y;

    //----------------------------------------------------------
    if( l == 0 )          return  k01;
    //----------------------------------------------------------
    if( l == 1 && m == -1 ) return  k02 * y;
    if( l == 1 && m ==  0 ) return  k02 * z;
    if( l == 1 && m ==  1 ) return  k02 * x;
    //----------------------------------------------------------
    if( l == 2 && m == -2 ) return  k03 * x * y;
    if( l == 2 && m == -1 ) return  k03 * y * z;
    if( l == 2 && m ==  0 ) return  k04 * (2.0 * z * z - x * x - y * y);
    if( l == 2 && m ==  1 ) return  k03 * x * z;
    if( l == 2 && m ==  2 ) return  k05 * (x * x - y * y);

    return 0.0;
}

float3 IrradianceSH9(in float3 c[9], in float3 dir)
{
    #define A0 3.1415
    #define A1 2.0943
    #define A2 0.7853

    // c: SH Coeff
    float3 irradiance = float3(0, 0, 0);
    irradiance += SH(0,  0, dir) * c[0] * A0;
    irradiance += SH(1, -1, dir) * c[1] * A1;
    irradiance += SH(1,  0, dir) * c[2] * A1;
    irradiance += SH(1,  1, dir) * c[3] * A1;
    irradiance += SH(2, -2, dir) * c[4] * A2;
    irradiance += SH(2, -1, dir) * c[5] * A2;
    irradiance += SH(2,  0, dir) * c[6] * A2;
    irradiance += SH(2,  1, dir) * c[7] * A2;
    irradiance += SH(2,  2, dir) * c[8] * A2;
    irradiance = max(float3(0, 0, 0), irradiance);

    return irradiance;
}

// 使用定点数存储小数, 保留小数点后 5 位
// 因为 compute shader 的 InterlockedAdd 不支持 float
#define FIXED_SCALE 100000.0
int EncodeFloatToInt(float x)
{
    return int(x * FIXED_SCALE);
}
float DecodeFloatFromInt(int x)
{
    return float(x) / FIXED_SCALE;
}

int3 GetProbeIndex3DFromWorldPos(float3 worldPos, float4 coefficientVoxelSize, float coefficientVoxelGridSize, float4 coefficientVoxelCorner)
{
    float3 probeIndex = floor((worldPos.xyz - coefficientVoxelCorner.xyz) / coefficientVoxelGridSize);
    int3 probeIndex3 = int3(probeIndex.x, probeIndex.y, probeIndex.z);
    return probeIndex3;
}

int GetProbeIndex1DFromIndex3D(int3 probeIndex3, float4 coefficientVoxelSize)
{
    int probeIndex = probeIndex3.x * coefficientVoxelSize.y * coefficientVoxelSize.z +
                     probeIndex3.y * coefficientVoxelSize.z +
                     probeIndex3.z;
    return probeIndex;
}

bool IsIndex3DInsideVoxel(int3 probeIndex3, float4 coefficientVoxelSize)
{
    return probeIndex3.x >= 0 && probeIndex3.x < coefficientVoxelSize.x &&
           probeIndex3.y >= 0 && probeIndex3.y < coefficientVoxelSize.y &&
           probeIndex3.z >= 0 && probeIndex3.z < coefficientVoxelSize.z;
}

void DecodeSHCoeffFromVoxel(inout float3 c[9], in StructuredBuffer<int> coefficientVoxel, int probeIndex)
{
    const int coeffByteSize = 27;
    int offset = probeIndex * coeffByteSize;
    for (int i = 0; i < 9; i++)
    {
        c[i].x = DecodeFloatFromInt(coefficientVoxel[offset + i * 3 + 0]);
        c[i].y = DecodeFloatFromInt(coefficientVoxel[offset + i * 3 + 1]);
        c[i].z = DecodeFloatFromInt(coefficientVoxel[offset + i * 3 + 2]);
    }
}

float3 GetProbePositionFromIndex3D(int3 probeIndex3, float coefficientVoxelGridSize, float4 coefficientVoxelCorner)
{
    float3 res = float3(probeIndex3.x, probeIndex3.y, probeIndex3.z) * coefficientVoxelGridSize + coefficientVoxelCorner.xyz;
    return res;
}

float3 TrilinearInterpolationFloat3(in float3 value[8], float3 rate)
{
    float3 a = lerp(value[0], value[4], rate.x);    // 000, 100
    float3 b = lerp(value[2], value[6], rate.x);    // 010, 110
    float3 c = lerp(value[1], value[5], rate.x);    // 001, 101
    float3 d = lerp(value[3], value[7], rate.x);    // 011, 111
    float3 e = lerp(a, b, rate.y);
    float3 f = lerp(c, d, rate.y);
    float3 g = lerp(e, f, rate.z); 
    return g;
}

float3 SampleSHVoxel(
    in float4 worldPos,
    in float3 albedo,
    in float3 normal,
    in StructuredBuffer<int> coefficientVoxel,
    in float4 coefficientVoxelSize,
    in float4 coefficientVoxelCorner,
    in float coefficientVoxelGridSize)
{
    int3 probeIndex3 = GetProbeIndex3DFromWorldPos(worldPos, coefficientVoxelSize, coefficientVoxelGridSize, coefficientVoxelCorner);
    int3 offset[8] = {
        int3(0, 0, 0), int3(0, 0, 1), int3(0, 1, 0), int3(0, 1, 1), 
        int3(1, 0, 0), int3(1, 0, 1), int3(1, 1, 0), int3(1, 1, 1), 
    };

    float3 c[9];
    float3 Lo[8] = {
        float3(0, 0, 0), float3(0, 0, 0), float3(0, 0, 0), float3(0, 0, 0),
        float3(0, 0, 0), float3(0, 0, 0), float3(0, 0, 0), float3(0, 0, 0)
    };
    float3 BRDF = albedo / PI;
    float weight = 0.0005;

    // near 8 probes
    for (int i = 0; i < 8; i++)
    {
        int3 idx3 = probeIndex3 + offset[i];
        bool isInsideVoxel = IsIndex3DInsideVoxel(idx3, coefficientVoxelSize);
    
        if (!isInsideVoxel)
        {
            Lo[i] = float3(0, 0, 0);
            continue;
        }
    
        float3 probePos = GetProbePositionFromIndex3D(idx3, coefficientVoxelGridSize, coefficientVoxelCorner);
        float3 dir = normalize(probePos - worldPos.xyz);
        float normalWeight = saturate(dot(dir, normal));
        weight += normalWeight;
    
        int probeIndex = GetProbeIndex1DFromIndex3D(idx3, coefficientVoxelSize);
        DecodeSHCoeffFromVoxel(c, coefficientVoxel, probeIndex);
        Lo[i] = IrradianceSH9(c, normal) * BRDF * normalWeight;
    }
    
    // Interpolation
    float3 minCorner = GetProbePositionFromIndex3D(probeIndex3, coefficientVoxelGridSize, coefficientVoxelCorner);
    float3 maxCorner = minCorner + coefficientVoxelGridSize;
    float3 rate = (worldPos.xyz - minCorner) / coefficientVoxelGridSize;
    float3 irradiance = TrilinearInterpolationFloat3(Lo, rate) / weight;

    // int probeIndex = GetProbeIndex1DFromIndex3D(probeIndex3 + offset[0], coefficientVoxelSize);
    // const int coeffByteSize = 27;
    // int probeOffset = probeIndex * coeffByteSize;
    // for (int i = 0; i < 9; i++)
    // {
    //     c[i].x = DecodeFloatFromInt(coefficientVoxel[probeOffset + i * 3 + 0]);
    //     c[i].y = DecodeFloatFromInt(coefficientVoxel[probeOffset + i * 3 + 1]);
    //     c[i].z = DecodeFloatFromInt(coefficientVoxel[probeOffset + i * 3 + 2]);
    // }

    // return c[0];
    
    return irradiance;
}
