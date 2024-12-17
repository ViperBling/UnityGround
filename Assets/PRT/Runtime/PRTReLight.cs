using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace PRT
{
    [ExecuteAlways]
    public class PRTReLight : ScriptableRendererFeature
    {
        class CustomRenderPass : ScriptableRenderPass
        {
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get();
                
                LightProbeVolume[] volumes = FindObjectsOfType(typeof(LightProbeVolume)) as LightProbeVolume[];
                LightProbeVolume volume = volumes.Length == 0 ? null : volumes[0];
                if (volume != null)
                {
                    volume.SwapLastFrameCoefficientVoxel();
                    volume.ClearCoefficientVoxel(cmd);

                    Vector3 corner = volume.GetVoxelMinCorner();
                    Vector4 voxelCorner = new Vector4(corner.x, corner.y, corner.z, 1);
                    Vector4 voxelSize = new Vector4(volume.ProbeSizeX, volume.ProbeSizeY, volume.ProbeSizeZ, 1);
                    
                    cmd.SetGlobalFloat("_CoefficientVoxelGridSize", volume.ProbeGridSize);
                    cmd.SetGlobalVector("_CoefficientVoxelSize", voxelSize);
                    cmd.SetGlobalVector("_CoefficientVoxelCorner", voxelCorner);
                    cmd.SetGlobalBuffer("_CoefficientVoxel", volume.CoefficientVoxel);
                    cmd.SetGlobalBuffer("_LastFrameCoefficientVoxel", volume.LastFrameCoefficientVoxel);
                    cmd.SetGlobalFloat("_SkyLightIntensity", volume.SkyLightIntensity);
                    cmd.SetGlobalFloat("_GIIntensity", volume.GIIntensity);
                }
                
                LightProbe[] probes = FindObjectsOfType(typeof(LightProbe)) as LightProbe[];
                if (probes != null)
                {
                    foreach (var probe in probes)
                    {
                        if (probe == null) continue;
                        probe.TryInit();
                        probe.ReLight(cmd);
                    }
                }
                
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                CommandBufferPool.Release(cmd);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                
            }
        }

        public override void Create()
        {
            m_ScriptablePass = new CustomRenderPass();

            m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(m_ScriptablePass);
        }

        private CustomRenderPass m_ScriptablePass;
    }
}