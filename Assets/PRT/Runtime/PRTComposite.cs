using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace PRT.Editor
{
    public class PRTComposite : ScriptableRendererFeature
    {
        class CustomRenderPass : ScriptableRenderPass
        {
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var rtDesc = renderingData.cameraData.cameraTargetDescriptor;
                rtDesc.depthBufferBits = 0;
                RenderingUtils.ReAllocateIfNeeded(ref TempRTHandle, rtDesc, FilterMode.Point, TextureWrapMode.Clamp, name: "TempRT");
            }
            
            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                DestColor = null;
                DestDepth = null;
            }
            
            public void Setup(RTHandle destColor, RTHandle destDepth)
            {
                DestColor = destColor;
                DestDepth = destDepth;
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get();
                if (DestColor != null && DestDepth != null)
                {
                    CoreUtils.SetRenderTarget(cmd, DestColor, DestDepth, clearFlag, clearColor);
                }

                LightProbeVolume[] volumes = FindObjectsOfType(typeof(LightProbeVolume)) as LightProbeVolume[];
                LightProbeVolume volume = volumes.Length == 0 ? null : volumes[0];
                if (volume != null)
                {
                    cmd.Blit(DestColor, TempRTHandle, BlitMaterial);
                    cmd.Blit(TempRTHandle, DestColor);
                }
                
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                CommandBufferPool.Release(cmd);
            }
            
            void Dispose()
            {
                TempRTHandle?.Release();
            }
            
            public Material BlitMaterial;
            public RTHandle TempRTHandle;
            public RTHandle DestColor;
            public RTHandle DestDepth;
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

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            _customPass.Setup(renderer.cameraColorTargetHandle, renderer.cameraDepthTargetHandle);
        }

        public Material CompositeMaterial;
        private CustomRenderPass _customPass;
    }
}