using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Scripting.APIUpdating;

namespace ParticleSimTest
{
    public class ParticleRenderPass : ScriptableRenderPass
    {
        public Material m_OverrideMaterial;
        public int m_OverrideMaterialPassIndex;
        
        private RenderQueueType m_RenderQueueType;
        FilteringSettings m_FilteringSettings;
        string m_ProfilerTag;
        ProfilingSampler m_ProfilingSampler;
        RenderStateBlock m_RenderStateBlock;
        List<ShaderTagId> m_ShaderTagIdList = new List<ShaderTagId>();

        public ParticleRenderPass(string profilerTag, RenderPassEvent renderPassEvent, string[] shaderTags, RenderQueueType renderQueueType, int layerMask)
        {
            base.profilingSampler = new ProfilingSampler(nameof(ParticleRenderPass));
            
            m_ProfilerTag = profilerTag;
            m_ProfilingSampler = new ProfilingSampler(profilerTag);
            this.renderPassEvent = renderPassEvent;
            m_RenderQueueType = renderQueueType;
            m_OverrideMaterial = null;
            m_OverrideMaterialPassIndex = 0;

            RenderQueueRange renderQueueRange = (renderQueueType == RenderQueueType.Transparent)
                ? RenderQueueRange.transparent
                : RenderQueueRange.opaque;
            m_FilteringSettings = new FilteringSettings(renderQueueRange, layerMask);

            if (shaderTags != null && shaderTags.Length > 0)
            {
                foreach (var passName in shaderTags)
                {
                    m_ShaderTagIdList.Add(new ShaderTagId(passName));
                }
            }
            else
            {
                m_ShaderTagIdList.Add(new ShaderTagId("SRPDefaultUnlit"));
                m_ShaderTagIdList.Add(new ShaderTagId("UniversalForward"));
                m_ShaderTagIdList.Add(new ShaderTagId("UniversalForwardOnly"));
            }

            m_RenderStateBlock = new RenderStateBlock(RenderStateMask.Nothing);
            // No Custom Camera Setting
        }
        
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            SortingCriteria sortingCriteria = (m_RenderQueueType == RenderQueueType.Transparent) ? SortingCriteria.CommonTransparent : SortingCriteria.CommonOpaque;

            DrawingSettings drawingSettings = CreateDrawingSettings(m_ShaderTagIdList, ref renderingData, sortingCriteria);
            drawingSettings.overrideMaterial = m_OverrideMaterial;
            drawingSettings.overrideMaterialPassIndex = m_OverrideMaterialPassIndex;
            
            var cmdBuffer = CommandBufferPool.Get(m_ProfilerTag);
            // using (new ProfilingScope(cmdBuffer, m_ProfilingSampler))
            // {
            //     var activeDebugHandler = GetActiveDebugHandler(ref renderingData);
            //     if (activeDebugHandler != null)
            //     {
            //         activeDebugHandler.DrawWithDebugRenderState(context, cmdBuffer, ref renderingData, ref drawingSettings, ref m_FilteringSettings, ref m_RenderStateBlock,
            //             (ScriptableRenderContext ctx, ref RenderingData data, ref DrawingSettings ds, ref FilteringSettings fs, ref RenderStateBlock rsb) =>
            //             {
            //                 ctx.DrawRenderers(data.cullResults, ref ds, ref fs, ref rsb);
            //             });
            //     }
            //     else
            //     {
                    context.ExecuteCommandBuffer(cmdBuffer);
                    cmdBuffer.Clear();
                
                    context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings, ref m_RenderStateBlock);
            //     }
            // }
            CommandBufferPool.Release(cmdBuffer);
        }
        

        public void SetDepthState(bool writeEnabled, CompareFunction function = CompareFunction.Less)
        {
            m_RenderStateBlock.mask |= RenderStateMask.Depth;
            m_RenderStateBlock.depthState = new DepthState(writeEnabled, function);
        }
        
        public void SetStencilState(int reference, CompareFunction compareFunction, StencilOp passOp, StencilOp failOp, StencilOp zFailOp)
        {
            StencilState stencilState = StencilState.defaultValue;
            stencilState.enabled = true;
            stencilState.SetCompareFunction(compareFunction);
            stencilState.SetPassOperation(passOp);
            stencilState.SetFailOperation(failOp);
            stencilState.SetZFailOperation(zFailOp);

            m_RenderStateBlock.mask |= RenderStateMask.Stencil;
            m_RenderStateBlock.stencilReference = reference;
            m_RenderStateBlock.stencilState = stencilState;
        }
    }
}