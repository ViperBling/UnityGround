using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR
{
    [DisallowMultipleRendererFeature("ScreenSpaceReflection")]
    public class ScreenSpaceReflection : ScriptableRendererFeature
    {
        public override void Create()
        {
            throw new NotImplementedException();
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            throw new NotImplementedException();
        }
    }
}