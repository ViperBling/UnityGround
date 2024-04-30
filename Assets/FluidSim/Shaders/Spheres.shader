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
            #pragma vertex ShaderVertex
            #pragma fragment ShaderFragment

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

            PixelInput ShaderVertex(VertexInput vsIn, uint id : SV_InstanceID)
            {
                PixelInput vsOut;

                float3 spherePos = UsePositionSmoothing ? Principle[id * 4 * 3] : Particles[id].Position.xyz;
                float3 localPos = vsIn.positionOS.xyz * (Radius * 2 * 2);
                
                float3x3 ellip = float3x3(Principle[id * 4 + 0], Principle[id * 4 + 1], Principle[id * 4 + 2]);
                
                float3 worldPos = mul(ellip, localPos) + spherePos;
                
                vsOut.positionCS = mul(UNITY_MATRIX_VP, float4(worldPos, 1));
                return vsOut;
            }

            half4 ShaderFragment(PixelInput psIn) : SV_Target
            {
                return 0;
            }
            
            ENDHLSL
        }

        Pass
        {
            ZTest Always
            
            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex ShaderVertex
            #pragma fragment ShaderFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.postprocessing/PostProcessing/Shaders/StdLib.hlsl"

            sampler2D DepthBuffer;

            struct VertexInput
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct PixelInput
            {
                float4 positionOS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            float4x4 InverseViewMat, InverseProjMat;
            float Radius;

            PixelInput ShaderVertex(VertexInput vsIn)
            {
                PixelInput vsOut;
                vsOut.positionOS = vsIn.positionOS;
                vsOut.positionOS.z = 0.5;
                vsOut.uv = vsIn.uv;
                return vsOut;
            }

            float4 ShaderFragment(PixelInput psIn, out float depth : SV_Depth) : SV_Target
            {
                float d = tex2D(DepthBuffer, psIn.uv);
                depth = d;

                float3 viewSpaceRayDir = normalize(mul(InverseProjMat, float4(psIn.uv * 2 - 1, 0, 1)).xyz);
                float viewSpaceDistance = LinearEyeDepth(d) / dot(viewSpaceRayDir, float3(0, 0, -1));

                float3 viewSpacePos = viewSpaceRayDir * viewSpaceDistance;
                float3 worldSpacePos = mul(InverseViewMat, float4(viewSpacePos, 1)).xyz;

                return float4(worldSpacePos, 0);
            }
            ENDHLSL
        }

        Pass
        {
            ZTest Less
            ZWrite Off
            Blend One One
            
            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex ShaderVertex
            #pragma fragment ShaderFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Particle
            {
                float4 Position;
                float4 Velocity;
            };

            StructuredBuffer<Particle> Particles;
            float Radius;
            StructuredBuffer<float3> Principle;
            int UsePositionSmoothing;

            sampler2D WorldPosBuffer;

            struct VertexInput
            {
                float4 positionOS : POSITION;
            };

            struct PixelInput
            {
                float4 positionCS : SV_POSITION;
                float4 rayDir : TEXCOORD0;
                float3 rayOrigin : TEXCOORD1;
                float4 spherePos : TEXCOORD2;
                float2 densitySpeed : TEXCOORD3;
                float3 m1 : TEXCOORD4;
                float3 m2 : TEXCOORD5;
                float3 m3 : TEXCOORD6;
            };

            struct PixelOutput
            {
                float4 normal : SV_Target0;
                float2 densitySpeed : SV_Target1;
            };

            float SphereIntersect(float3 RayOrigin, float3 RayDir, float4 Sphere)
            {
                float3 OC = RayOrigin - Sphere.xyz;
                float B = dot(OC, RayDir);
                float C = dot(OC, OC) - Sphere.w * Sphere.w;
                float D = B * B - C;
                if (D < 0.0) return -1.0;
                D = sqrt(D);
                return -B - D;
            }

            float InvLerp(float A, float B, float T)
            {
                return (T - A) / (B - A);
            }

            float3x3 Inverse(float3x3 m)
            {
                float a00 = m[0][0], a01 = m[0][1], a02 = m[0][2];
                float a10 = m[1][0], a11 = m[1][1], a12 = m[1][2];
                float a20 = m[2][0], a21 = m[2][1], a22 = m[2][2];

                float b01 = a22 * a11 - a12 * a21;
                float b11 = -a22 * a10 + a12 * a20;
                float b21 = a21 * a10 - a11 * a20;

                float det = a00 * b01 + a01 * b11 + a02 * b21;

                return float3x3(b01, (-a22 * a01 + a02 * a21), ( a12 * a01 - a02 * a11),
                                b11, ( a22 * a00 - a02 * a20), (-a12 * a00 + a02 * a10),
                                b21, (-a21 * a00 + a01 * a20), ( a11 * a00 - a01 * a10)) / det;
            }

            PixelInput ShaderVertex(VertexInput vsIn, uint id : SV_InstanceID)
            {
                float3 spherePos = UsePositionSmoothing ? Principle[id.x * 4 + 3] : Particles[id.x].Position.xyz;
                float3 localPos = vsIn.positionOS.xyz * (Radius * 2 * 4);

                float3x3 ellip = float3x3(Principle[id.x * 4 + 0], Principle[id.x * 4 + 1], Principle[id.x * 4 + 2]);
                float3 worldPos = mul(ellip, localPos) + spherePos;

                ellip = Inverse(ellip);

                float3 objectSpaceCamera = _WorldSpaceCameraPos.xyz - spherePos;
                objectSpaceCamera = mul(ellip, objectSpaceCamera);

                float3 objectSpaceDir = normalize(worldPos - _WorldSpaceCameraPos.xyz);
                objectSpaceDir = mul(ellip, objectSpaceDir);
                objectSpaceDir = normalize(objectSpaceDir);

                PixelInput vsOut;
                vsOut.positionCS = mul(UNITY_MATRIX_VP, float4(worldPos, 1));
                vsOut.rayDir = ComputeScreenPos(vsOut.positionCS);
                vsOut.rayOrigin = objectSpaceCamera;
                vsOut.spherePos = float4(spherePos, Particles[id].Position.w);
                vsOut.densitySpeed = saturate(float2(InvLerp(0, 1, vsOut.spherePos.w), InvLerp(10, 30, length(Particles[id].Velocity.xyz))));
                vsOut.m1 = ellip._11_12_13;
                vsOut.m2 = ellip._21_22_23;
                vsOut.m3 = ellip._31_32_33;

                return vsOut;
            }

            PixelOutput ShaderFragment(PixelInput psIn) : SV_Target
            {
                float3x3 mInv = float3x3(psIn.m1, psIn.m2, psIn.m3);

                float2 uv = psIn.rayDir.xy / psIn.rayDir.w;
                float3 worldPos  = tex2D(WorldPosBuffer, uv).xyz;
                float3 ellipPos = mul(mInv, worldPos - psIn.spherePos.xyz);

                float distSqr = dot(ellipPos, ellipPos);
                float radiusSqr = pow(Radius * 4, 2);
                if (distSqr >= radiusSqr) discard;

                mInv = mul(transpose(mInv), mInv);

                float weight = pow(1 - distSqr / radiusSqr, 3);

                float3 centered = worldPos - psIn.spherePos.xyz;
                float3 grad = mul(mInv, centered) + mul(centered, mInv);
                float3 normal = grad * weight;

                PixelOutput psOut = (PixelOutput)0;
                psOut.normal = float4(normal, weight);
                psOut.densitySpeed = float2(psIn.densitySpeed) * weight;

                return psOut;
            }
            ENDHLSL
        }

        Pass
        {
            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex ShaderVertex
            #pragma fragment ShaderFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            sampler2D DepthBuffer;
            sampler2D WorldPosBuffer;
            sampler2D NormalBuffer;
            sampler2D ColorBuffer;
            samplerCUBE _EnvMap;

            float4 _PrimaryColor, _SecondaryColor, _FoamColor;
            float4 _SpecularColor;
            float _PhongExp;

            struct VertexInput
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct PixelInput
            {
                float4 positionOS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            PixelInput ShaderVertex(VertexInput vsIn)
            {
                PixelInput vsOut;
                vsOut.positionOS = vsIn.positionOS;
                vsOut.uv = vsIn.uv;
                return vsOut;
            }

            float4 ShaderFragment(PixelInput psIn, out float depth : SV_Depth) : SV_Target
            {
                float d = tex2D(DepthBuffer, psIn.uv);
                float3 worldPos = tex2D(WorldPosBuffer, psIn.uv).xyz;
                float4 normal = tex2D(NormalBuffer, psIn.uv);
                float2 densitySpeed = tex2D(ColorBuffer, psIn.uv);

                if (d == 0) discard;

                if (normal.w > 0)
                {
                    normal.xyz = normalize(normal.xyz);
                    densitySpeed /= normal.w;
                }
                depth = d;

                float3 diffuse = lerp(_PrimaryColor, _SecondaryColor, densitySpeed.x);
                diffuse = lerp(diffuse, _FoamColor, densitySpeed.y);

                float light = max(dot(normal, _MainLightPosition.xyz), 0);
                light = lerp(0.1, 1, light);

                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - worldPos);
                float3 lightDir = normalize(_MainLightPosition.xyz - worldPos);
                float3 HalfDir = normalize(lightDir + viewDir);

                diffuse += pow(max(dot(normal, HalfDir), 0), _PhongExp) * _SpecularColor;

                float4 reflectedColor = texCUBE(_EnvMap, reflect(-viewDir, normal.xyz));

                float iorAir = 1.0;
                float iorWater = 1.33;
                float r0 = pow((iorAir - iorWater) / (iorAir + iorWater), 2);
                float rTheta = r0 + (1 - r0) * pow(1 - max(dot(viewDir, normal.xyz), 0), 5);

                diffuse = lerp(diffuse, reflectedColor, rTheta);

                return float4(diffuse, 1);
            }

            ENDHLSL
        }
    }
}