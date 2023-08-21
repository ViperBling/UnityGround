using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class WindSimulationRenderFeature : ScriptableRendererFeature
{
    class CustomRenderPass : ScriptableRenderPass
    {
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            throw new System.NotImplementedException();
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }
    }
    public override void Create()
    {
        m_ScriptablePass = new CustomRenderPass();
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRendering;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var cameraData = renderingData.cameraData;
        if ((cameraData.camera.cameraType == CameraType.Game ||
             cameraData.camera.cameraType == CameraType.SceneView) &&
            cameraData.renderType == CameraRenderType.Base)
        {
            renderer.EnqueuePass(m_ScriptablePass);
        }
    }

    CustomRenderPass m_ScriptablePass;
}
