using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace PRT
{
    public class PRTComposite : ScriptableRendererFeature
    {
        class CustomRenderPass : ScriptableRenderPass
        {
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTextureDescriptor rtDesc = renderingData.cameraData.cameraTargetDescriptor;
                cmd.GetTemporaryRT(TempRTHandle.GetInstanceID(), rtDesc, FilterMode.Point);

                BlitSrc = renderingData.cameraData.renderer.cameraColorTargetHandle;
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get();
                RenderTargetIdentifier tempRT = TempRTHandle.GetInstanceID();

                LightProbeVolume[] volumes = GameObject.FindObjectsOfType(typeof(LightProbeVolume)) as LightProbeVolume[];
                LightProbeVolume volume = volumes.Length == 0 ? null : volumes[0];
                if (volume != null)
                {
                    cmd.Blit(BlitSrc, tempRT, BlitMaterial);
                    cmd.Blit(tempRT, BlitSrc);
                }
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                CommandBufferPool.Release(cmd);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                cmd.ReleaseTemporaryRT(TempRTHandle.GetInstanceID());
            }
            
            public Material BlitMaterial;
            public RTHandle TempRTHandle;
            public RenderTargetIdentifier BlitSrc;
        }

        public override void Create()
        {
            _customPass = new CustomRenderPass();

            _customPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            _customPass.BlitMaterial = CompositeMaterial;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(_customPass);
        }

        public Material CompositeMaterial;
        private CustomRenderPass _customPass;
    }
}