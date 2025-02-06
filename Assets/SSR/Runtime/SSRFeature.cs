using System;
using System.Reflection;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR
{
    [DisallowMultipleRendererFeature("ScreenSpaceReflection")]
    public partial class SSRFeature : ScriptableRendererFeature
    {
        public enum SSRResolution
        {
            [InspectorName("100%"), Tooltip("Render at full resolution.")]
            Full = 4,
            [InspectorName("75%"), Tooltip("Render at 75% resolution.")]
            ThreeQuarters = 3,
            [InspectorName("50%"), Tooltip("Render at 50% resolution.")]
            Half = 2,
            [InspectorName("25%"), Tooltip("Render at 25% resolution.")]
            Quarter = 1
        }

        public enum SSRMipmapMode
        {
            [Tooltip("Disable rough reflection in approximated mode.")]
            Disabled = 0,
            [Tooltip("Enable rough reflection in approximated mode.")]
            TriLinear = 1
        }

        // [Header("Setup")] [Tooltip("The post-processing material of ssr.")]
        private Material m_Material;

        [Header("Performance")] [Tooltip("The resolution of the SSR effect.")]
        public SSRResolution m_Resolution = SSRResolution.Full;
        
        [Header("Approximation")] [Tooltip("The roughness of the SSR effect.")]
        public SSRMipmapMode m_MipmapMode = SSRMipmapMode.TriLinear;
        
        [Header("PBR Accumulation")] [Tooltip("Enable SSR in SceneView.")]
        public bool m_EnableInSceneView = false;

        private const string m_SSRShaderName = "Hidden/Lighting/SSRShader";
        
        private ScreenSpaceReflectionPass m_SSRPass;
        private BackFaceDepthPass m_BackFaceDepthPass;

        private readonly static FieldInfo m_RenderingModeFieldInfo = typeof(UniversalRenderer).GetField("m_RenderingMode", BindingFlags.NonPublic | BindingFlags.Instance);
        private readonly static FieldInfo m_NormalTextureFieldInfo = typeof(UniversalRenderer).GetField("m_NormalsTexture", BindingFlags.NonPublic | BindingFlags.Instance);

        public SSRResolution DownSampling
        {
            get { return m_Resolution; }
            set { m_Resolution = value; }
        }
        
        public SSRMipmapMode MipmapMode
        {
            get { return m_MipmapMode; }
            set { m_MipmapMode = value; }
        }
        
        public override void Create()
        {
            if (m_Material != null)
            {
                if (m_Material.shader != Shader.Find(m_SSRShaderName))
                {
                    return;
                }
            }

            GetMaterial();

            if (m_BackFaceDepthPass == null)
            {
                m_BackFaceDepthPass = new(m_Material);
                m_BackFaceDepthPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
            }

            if (m_SSRPass == null)
            {
                m_SSRPass = new(m_Resolution, m_MipmapMode, m_Material);
                m_SSRPass.renderPassEvent = RenderPassEvent.BeforeRenderingTransparents + 1;
            }
            else
            {
                m_SSRPass.m_RenderResolution = m_Resolution;
                m_SSRPass.m_MipmapMode = m_MipmapMode;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (m_SSRPass != null) m_SSRPass.Dispose();
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (m_Material == null) return;

            var renderingMode = (RenderingMode)m_RenderingModeFieldInfo.GetValue(renderer as UniversalRenderer);
            bool isUsingDeferred = (renderingMode != RenderingMode.Forward) && (renderingMode != RenderingMode.ForwardPlus);

            var stack = VolumeManager.instance.stack;
            ScreenSpaceReflectionEffect ssrVolume = stack.GetComponent<ScreenSpaceReflectionEffect>();
            bool isActive = ssrVolume != null && ssrVolume.IsActive();
            bool isDebug = DebugManager.instance.isAnyDebugUIActive;

            // bool isMotionValid = true;
            
// #if UNITY_EDITOR
            // isMotionValid = m_EnableInSceneView || UnityEditor.EditorApplication.isPlaying || renderingData.cameraData.camera.cameraType != CameraType.SceneView;
// #endif
            if (renderingData.cameraData.camera.cameraType != CameraType.Preview && isActive && (!isDebug))
            {
                m_BackFaceDepthPass.m_SSRVolume = ssrVolume;
                renderer.EnqueuePass(m_BackFaceDepthPass);
                // m_SSRPass.m_

                m_SSRPass.renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
                m_SSRPass.m_SSRVolume = ssrVolume;
                renderer.EnqueuePass(m_SSRPass);
            }
        }

        private void GetMaterial()
        {
            if (m_Material != null) return;
            var ssrShader = Shader.Find(m_SSRShaderName);
            m_Material = CoreUtils.CreateEngineMaterial(ssrShader);
        }
    }
}