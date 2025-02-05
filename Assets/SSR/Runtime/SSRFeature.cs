using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR
{
    [DisallowMultipleRendererFeature("ScreenSpaceReflection")]
    public partial class ScreenSpaceReflection : ScriptableRendererFeature
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