Shader "Custom/Particle/Sphere"
{
    Properties
    {
        _PrimaryColor("Primary Color", Color) = (1,1,1,1)
        _SecondaryColor("Secondary Color", Color) = (1,1,1,1)
        _FoamColor("Foam Color", Color) = (1,1,1,1)
        [HDR] _SpecularColor("Specular Color", Color) = (1,1,1,1)
        _PhongExp("Phong Exponent", Float) = 128
        _EnvMap("Environment Map", Cube) = "" {}
    }
    
    SubShader
    {
        Tags {"RenderType"="Opaque"}
        
        Pass
        {
            HLSLPROGRAM

            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Particle
            {
                float4 Position;
                float4 Velocity;
            };

            StructuredBuffer<Particle> Particles;
            StructuredBuffer<float3> Principle;
            int UsePositionSmoothing;
            float Radius;

            struct VertexInput
            {
                float4 positionOS : POSITION;
            };

            struct PixelInput
            {
                float4 positionCS : SV_POSITION;
            };

            PixelInput vert(VertexInput vsIn, uint id : SV_InstanceID)
            {
                PixelInput vsOut;

                float3 spherePos = UsePositionSmoothing ? Principle[id * 4 * 3] : Particles[id].Position.xyz;
                float3 localPos = vsIn.positionOS.xyz * (Radius * 2 * 2);
                
                float3x3 ellip = float3x3(Principle[id * 4 + 0], Principle[id * 4 + 1], Principle[id * 4 + 2]);
                
                float3 worldPos = mul(ellip, localPos) + spherePos;
                
                vsOut.positionCS = mul(UNITY_MATRIX_VP, float4(worldPos, 1));
                return vsOut;
            }

            half4 frag(PixelInput psIn) : SV_Target
            {
                return 0;
            }
            
            ENDHLSL
        }
    }
}