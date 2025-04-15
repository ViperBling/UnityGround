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
        [SerializeField]
        private Material m_SSRMaterial;
        
        private ArtDepthPyramid m_DepthPyramidPass;
        private ArtSSRRenderPass m_SSRRenderPass;
        // private ArtSSRBackFaceDepthPass m_BackFaceDepthPass;
        
        private readonly static FieldInfo m_RenderingModeFieldInfo = typeof(UniversalRenderer).GetField("m_RenderingMode", BindingFlags.NonPublic | BindingFlags.Instance);
        
        public override void Create()
        {
            GetMaterial();

            if (m_DepthPyramidPass == null)
            {
                m_DepthPyramidPass = new ArtDepthPyramid();
                m_DepthPyramidPass.renderPassEvent = RenderPassEvent.BeforeRenderingSkybox;
            }

            // if (m_BackFaceDepthPass == null)
            // {
            //     m_BackFaceDepthPass = new ArtSSRBackFaceDepthPass(m_SSRMaterial);
            //     m_BackFaceDepthPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
            // }

            if (m_SSRRenderPass == null)
            {
                m_SSRRenderPass = new ArtSSRRenderPass(m_SSRMaterial);
                m_SSRRenderPass.renderPassEvent = RenderPassEvent.BeforeRenderingTransparents + 1;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (m_DepthPyramidPass != null) m_DepthPyramidPass.Dispose();
            if (m_SSRRenderPass != null) m_SSRRenderPass.Dispose();
            // CoreUtils.Destroy(m_SSRMaterial);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var stack = VolumeManager.instance.stack;
            ArtScreenSpaceReflection artSSRVolume = stack.GetComponent<ArtScreenSpaceReflection>();
            bool isSSRActive = artSSRVolume != null && artSSRVolume.IsActive();

            if (isSSRActive)
            {
                if (artSSRVolume.m_MarchingMode.value == ArtScreenSpaceReflection.RayMarchingMode.HiZTracing)
                {
                   m_DepthPyramidPass.m_SSRVolume = artSSRVolume;
                    renderer.EnqueuePass(m_DepthPyramidPass);
                }

                // m_BackFaceDepthPass.m_SSRVolume = artSSRVolume;
                // renderer.EnqueuePass(m_BackFaceDepthPass);
                
                m_SSRRenderPass.m_SSRVolume = artSSRVolume;
                renderer.EnqueuePass(m_SSRRenderPass);
            }
        }
        
         private void GetMaterial()
         {
             if (m_SSRMaterial != null) return;

             if (m_SSRShader == null)
             {
                 m_SSRShader = Shader.Find("Hidden/ArtSSRShader");
                 if (m_SSRShader == null)
                 {
                     Debug.LogError("ArtSSRShader not found");
                     return;
                 }
             }

             m_SSRMaterial = CoreUtils.CreateEngineMaterial(m_SSRShader);
         }
    }
}