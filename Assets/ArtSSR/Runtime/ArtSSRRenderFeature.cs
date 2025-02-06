using System;
using System.Reflection;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ArtSSR
{
    public partial class ArtSSRRenderFeature : ScriptableRendererFeature
    {
        private Shader m_SSRShader;
        private Material m_SSRMaterial;
        
        private ArtSSRRenderPass m_SSRRenderPass;
        
        private readonly static FieldInfo m_RenderingModeFieldInfo = typeof(UniversalRenderer).GetField("m_RenderingMode", BindingFlags.NonPublic | BindingFlags.Instance);
        
        public override void Create()
        {
            GetMaterial();

            if (m_SSRRenderPass == null)
            {
                m_SSRRenderPass = new ArtSSRRenderPass(m_SSRMaterial);
                m_SSRRenderPass.renderPassEvent = RenderPassEvent.BeforeRenderingTransparents + 1;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (m_SSRRenderPass != null) m_SSRRenderPass.Dispose();
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var stack = VolumeManager.instance.stack;
            ArtSSREffect artSSRVolume = stack.GetComponent<ArtSSREffect>();
            bool isSSRActive = artSSRVolume != null && artSSRVolume.IsActive();

            if (renderingData.cameraData.camera.cameraType != CameraType.Preview && isSSRActive)
            {
                m_SSRRenderPass.m_SSRVolume = artSSRVolume;
                renderer.EnqueuePass(m_SSRRenderPass);
            }
        }
        
//         public static ScreenSpaceReflectionSettings GetSettings()
//         {
//             return new ScreenSpaceReflectionSettings()
//             {
//                 Downsample = s_Instance.m_SSRSettings.m_DownSample,
//                 MaxSteps = s_Instance.m_SSRSettings.m_MaxSteps,
//                 MinSmoothness = s_Instance.m_SSRSettings.m_MinSmoothness,
//                 StepStrideLength = s_Instance.m_SSRSettings.m_StepStrideLength,
//                 TracingMode = s_Instance.m_SSRSettings.m_TracingMode,
//                 DitherMode = s_Instance.m_SSRSettings.m_DitherMode
//             };
//         }
//
//         public static void SetSettings(ScreenSpaceReflectionSettings ssrSettings)
//         {
//             s_Instance.m_SSRSettings = new SSRSettings()
//             {
//                 m_DownSample = (uint)Mathf.Clamp01(ssrSettings.Downsample),
//                 m_MaxSteps = Mathf.Max(ssrSettings.MaxSteps, 8),
//                 m_MinSmoothness = Mathf.Clamp01(ssrSettings.MinSmoothness),
//                 m_StepStrideLength = Mathf.Clamp(ssrSettings.StepStrideLength, 0.0001f, float.MaxValue),
//                 m_TracingMode = ssrSettings.TracingMode,
//                 m_DitherMode = ssrSettings.DitherMode,
//                 m_SSRMaterial = s_Instance.m_SSRSettings.m_SSRMaterial,
//                 m_SSRShader = s_Instance.m_SSRSettings.m_SSRShader
//             };
//             s_Instance.m_SSRRenderPass.m_Settings = s_Instance.m_SSRSettings;
//         }
//         
//         public static bool m_Enabled { get; set; } = true;
//         
//         [Serializable]
//         internal class SSRSettings
//         {
//             public RayTracingMode m_TracingMode = RayTracingMode.LinearTracing;
//             public float m_StepStrideLength = 0.03f;
//             public float m_MaxSteps = 128;
//             [Range(0, 1)]
//             public uint m_DownSample = 0;
//             public float m_MinSmoothness = 0.5f;
//             public bool m_ReflectSky = true;
//             public DitherMode m_DitherMode = DitherMode.InterleavedGradient;
//             [HideInInspector] public Material m_SSRMaterial;
//             [HideInInspector] public Shader m_SSRShader;
//         }
//
//         internal ArtSSRRenderPass m_SSRRenderPass = null;
//         internal static ArtSSRRenderFeature s_Instance = null;
//         [SerializeField] SSRSettings m_SSRSettings = new SSRSettings();
//         
//         void SetMaterialProperties(in RenderingData renderingData)
//         {
//             var projectionMatrix = renderingData.cameraData.GetGPUProjectionMatrix();
//             var viewMatrix = renderingData.cameraData.GetViewMatrix();
//
// #if UNITY_EDITOR
//             if (renderingData.cameraData.isSceneViewCamera)
//             {
//                 m_SSRSettings.m_SSRMaterial.SetFloat("_RenderScale", 1);
//             }
//             else
//             {
//                 m_SSRSettings.m_SSRMaterial.SetFloat("_RenderScale", renderingData.cameraData.renderScale);
//             }
// #else
//             m_SSRSettings.m_SSRMaterial.SetFloat("_RenderScale", renderingData.cameraData.renderScale);
// #endif
//             
//             m_SSRSettings.m_SSRMaterial.SetMatrix("_ProjectionMatrixSSR", projectionMatrix);
//             m_SSRSettings.m_SSRMaterial.SetMatrix("_InvProjectionMatrixSSR", projectionMatrix.inverse);
//             m_SSRSettings.m_SSRMaterial.SetMatrix("_ViewMatrixSSR", viewMatrix);
//             m_SSRSettings.m_SSRMaterial.SetMatrix("_InvViewMatrixSSR", viewMatrix.inverse);
//         }
//         
         private bool GetMaterial()
         {
             if (m_SSRMaterial != null) return true;

             if (m_SSRShader == null)
             {
                 m_SSRShader = Shader.Find("Hidden/ArtSSRShader");
                 if (m_SSRShader == null)
                 {
                     Debug.LogError("ArtSSRShader not found");
                     return false;
                 }
             }

             m_SSRMaterial = CoreUtils.CreateEngineMaterial(m_SSRShader);
             
             return m_SSRMaterial != null;
         }
//         
//         public override void Create()
//         {
//             s_Instance = this;
//             m_SSRRenderPass = new ArtSSRRenderPass()
//             {
//                 renderPassEvent = RenderPassEvent.BeforeRenderingTransparents,
//                 m_Settings = this.m_SSRSettings
//             };
//             GetMaterial();
//         }
//
//         public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
//         {
//             if (!renderingData.cameraData.postProcessEnabled || !m_Enabled) return;
//             if (!GetMaterial())
//             {
//                 Debug.LogError("Failed to create SSR material");
//                 return;
//             }
//             
//             m_SSRSettings.m_SSRMaterial.SetVector("_WorldSpaceViewDir", renderingData.cameraData.camera.transform.forward);
//
//             renderingData.cameraData.camera.depthTextureMode |= DepthTextureMode.MotionVectors | DepthTextureMode.Depth | DepthTextureMode.DepthNormals;
//             float renderScale = renderingData.cameraData.isSceneViewCamera ? 1 : renderingData.cameraData.renderScale;
//             
//             m_SSRRenderPass.m_RenderScale = renderScale;
//             
//             m_SSRSettings.m_SSRMaterial.SetFloat("_StepStride", m_SSRSettings.m_StepStrideLength);
//             m_SSRSettings.m_SSRMaterial.SetFloat("_NumSteps", m_SSRSettings.m_MaxSteps);
//             m_SSRSettings.m_SSRMaterial.SetFloat("_MinSmoothness", m_SSRSettings.m_MinSmoothness);
//             m_SSRSettings.m_SSRMaterial.SetFloat("_ReflectSky", m_SSRSettings.m_ReflectSky ? 1 : 0);
//
//             if (!UniversalRenderPipelineDebugDisplaySettings.Instance.AreAnySettingsActive)
//             {
//                 renderer.EnqueuePass(m_SSRRenderPass);
//             }
//         }
//
//         public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
//         {
//             if (!renderingData.cameraData.postProcessEnabled || !m_Enabled) return;
//             if (!GetMaterial())
//             {
//                 Debug.LogError("Failed to create SSR material");
//                 return;
//             }
//             SetMaterialProperties(in renderingData);
//             m_SSRRenderPass.m_ColorSource = renderer.cameraColorTargetHandle;
//         }
//
//         protected override void Dispose(bool disposing)
//         {
//             CoreUtils.Destroy(m_SSRSettings.m_SSRMaterial);
//         }
        
    }
}