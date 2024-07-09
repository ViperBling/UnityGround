using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ParticleSimTest
{
    public enum RenderQueueType
    {
        Opaque,
        Transparent,
    }
    
    [ExcludeFromPreset]
    public class RenderParticle : ScriptableRendererFeature
    {
        [System.Serializable]
        public class ParticleRenderSettings
        {
            public string m_PassTag = "RenderParticle";
            public RenderPassEvent m_RenderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            public ParticleRenderFilterSettings m_FilterSettings = new ParticleRenderFilterSettings();
            public Material m_OverrideMaterial = null;
            public int m_OverrideMaterialPassIndex = 0;
            public bool m_OverrideDepthState = false;
            public CompareFunction m_DepthCompareFunction = CompareFunction.LessEqual;
            public bool m_EnableWrite = true;
            public StencilStateData m_StencilSettings = new StencilStateData();
        }
        
        [System.Serializable]
        public class ParticleRenderFilterSettings
        {
            public RenderQueueType RenderQueueType;
            public LayerMask LayerMask;
            public string[] PassNames;
            public ParticleRenderFilterSettings()
            {
                RenderQueueType = RenderQueueType.Opaque;
                LayerMask = 0;
            }
        }

        public ParticleRenderSettings m_Settings = new ParticleRenderSettings();
        ParticleRenderPass m_ParticleRenderPass;

        public override void Create()
        {
            ParticleRenderFilterSettings filter = m_Settings.m_FilterSettings;
            m_ParticleRenderPass = new ParticleRenderPass(m_Settings.m_PassTag, m_Settings.m_RenderPassEvent, filter.PassNames,
                filter.RenderQueueType, filter.LayerMask);

            m_ParticleRenderPass.m_OverrideMaterial = m_Settings.m_OverrideMaterial;
            m_ParticleRenderPass.m_OverrideMaterialPassIndex = m_Settings.m_OverrideMaterialPassIndex;

            if (m_Settings.m_OverrideDepthState)
            {
                m_ParticleRenderPass.SetDepthState(m_Settings.m_EnableWrite, m_Settings.m_DepthCompareFunction);
            }

            if (m_Settings.m_StencilSettings.overrideStencilState)
            {
                m_ParticleRenderPass.SetStencilState(m_Settings.m_StencilSettings.stencilReference, m_Settings.m_StencilSettings.stencilCompareFunction,
                    m_Settings.m_StencilSettings.passOperation, m_Settings.m_StencilSettings.failOperation, m_Settings.m_StencilSettings.zFailOperation);
            }
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.cameraType == CameraType.Preview ||
                UniversalRenderer.IsOffscreenDepthTexture(in renderingData.cameraData))
            {
                return;
            }
            renderer.EnqueuePass(m_ParticleRenderPass);
        }
    }
}
