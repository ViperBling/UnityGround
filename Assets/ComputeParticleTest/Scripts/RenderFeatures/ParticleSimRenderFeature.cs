using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ParticleSimTest
{
    public class ParticleSimRenderFeature : ScriptableRendererFeature
    {
        ParticleSimRenderPass m_ParticleSimRenderPass;

        /// <inheritdoc/>
        public override void Create()
        {
            m_ParticleSimRenderPass = new ParticleSimRenderPass();

            // Configures where the render pass should be injected.
            m_ParticleSimRenderPass.renderPassEvent = RenderPassEvent.AfterRenderingGbuffer;
        }

        // Here you can inject one or multiple render passes in the renderer.
        // This method is called when setting up the renderer once per-camera.
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(m_ParticleSimRenderPass);
        }
    }
}



