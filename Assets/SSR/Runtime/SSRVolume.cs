using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR
{
    [Serializable, VolumeComponentMenuForRenderPipeline("Lighting/Screen Space Reflection", typeof(UniversalRenderPipeline))]
    public class ScreenSpaceReflectionEffect : VolumeComponent, IPostProcessComponent
    {
        [InspectorName("State (Opaque)"), Tooltip("When set to Enabled, URP processes SSR on opaque objects for Cameras in the influence of this effect's Volume.")]
        public SSRStateParameter m_State = new(value: SSRState.Disabled, overrideState: true);
        
        [InspectorName("Render Mode"), Tooltip("Determines the method used to compute reflections.")]
        public SSRRenderModeParameter m_RenderMode = new(value: SSRRenderMode.Approximation, overrideState: false);
        
        [InspectorName("Minimum Smoothness")]
        public ClampedFloatParameter m_MinSmoothness = new(value: 0.5f, min: 0.0f, max: 1.0f, overrideState: false);
        
        [InspectorName("Smoothness Fade Start")]
        public ClampedFloatParameter m_FadeSmoothness = new(value: 0.6f, min: 0.0f, max: 1.0f, overrideState: false);

        [InspectorName("Screen Edge Fade Distance"), Tooltip("The distance from the edge of the screen where SSR fades out.")]
        public ClampedFloatParameter m_EdgeFade = new(value: 0.1f, min: 0.0f, max: 1.0f, overrideState: true);
        
        [Tooltip("The thickness mode of SSR.")]
        public SSRThicknessParameter m_ThicknessMode = new(value: ThicknessMode.Constant, overrideState: false);
        
        [InspectorName("Object Thickness"), Tooltip("The thickness of all scene objects. This is also the fallback thickness for automatic thickness mode.")]
        public ClampedFloatParameter m_ObjThickness = new(value: 0.25f, min: 0.0f, max: 1.0f, overrideState: true);
        
        [InspectorName("Quality"), Tooltip("Determines the quality of the SSR effect.")]
        public SSRQualityParameter m_Quality = new(value: SSRQuality.High, overrideState: false);

        [InspectorName("Max Ray Steps"), Tooltip("The maximum number of steps SSR can take.")]
        public ClampedIntParameter m_MaxStep = new(value: 16, min: 4, max: 512, overrideState: false);
        
        
        public bool IsActive()
        {
            return m_State.value == SSRState.Enabled && SystemInfo.supportedRenderTargetCount >= 3;
        }

        public bool IsTileCompatible() => false;
        
        public enum SSRState
        {
            [Tooltip("Disable SSR")]
            Disabled = 0,
            [Tooltip("Enable SSR")]
            Enabled = 1
        }
        [Serializable]
        public sealed class SSRStateParameter : VolumeParameter<SSRState>
        {
            /// <summary>
            /// Creates a new <see cref="SSRStateParameter"/> instance.
            /// </summary>
            /// <param name="value">The initial value to store in the parameter.</param>
            /// <param name="overrideState">The initial override state for the parameter.</param>
            public SSRStateParameter(SSRState value, bool overrideState = false) : base(value, overrideState) {}
        }
        
        public enum SSRRenderMode
        {
            [Tooltip("Cast rays in deterministic directions to compute reflections.")]
            Approximation = 0,

            [InspectorName("PBR Accumulation"), Tooltip("Cast rays in stochastic directions and accumulate multiple frames to compute rough reflections.")]
            PBRAccumulation = 1
        }
        [Serializable]
        public sealed class SSRRenderModeParameter : VolumeParameter<SSRRenderMode>
        {
            /// <summary>
            /// Creates a new <see cref="SSRRenderModeParameter"/> instance.
            /// </summary>
            /// <param name="value">The initial value to store in the parameter.</param>
            /// <param name="overrideState">The initial override state for the parameter.</param>
            public SSRRenderModeParameter(SSRRenderMode value, bool overrideState = false) : base(value, overrideState) { }
        }

        public enum ThicknessMode
        {
            [Tooltip("Apply constant thickness to the reflections.")]
            Constant = 0,
            [InspectorName("Automatic"), Tooltip("Automatic mode renders the back-faces of scene objects to compute thickness.")]
            ComputeBackface = 1
        }
        [Serializable]
        public sealed class SSRThicknessParameter : VolumeParameter<ThicknessMode>
        {
            /// <summary>
            /// Creates a new <see cref="SSRThicknessParameter"/> instance.
            /// </summary>
            /// <param name="value">The initial value to store in the parameter.</param>
            /// <param name="overrideState">The initial override state for the parameter.</param>
            public SSRThicknessParameter(ThicknessMode value, bool overrideState = false) : base(value, overrideState) {}
        }
        
        public enum SSRQuality
        {
            [Tooltip("Low quality mode with 16 ray steps.")]
            Low = 0,
            [Tooltip("Medium quality mode with 32 ray steps.")]
            Medium = 1,
            [Tooltip("High quality mode with 64 ray steps.")]
            High = 2,
            [Tooltip("Custom quality mode with 16 ray steps by default.")]
            Custom = 3
        }
        [Serializable]
        public sealed class SSRQualityParameter : VolumeParameter<SSRQuality>
        {
            /// <summary>
            /// Creates a new <see cref="SSRQualityParameter"/> instance.
            /// </summary>
            /// <param name="value">The initial value to store in the parameter.</param>
            /// <param name="overrideState">The initial override state for the parameter.</param>
            public SSRQualityParameter(SSRQuality value, bool overrideState = false) : base(value, overrideState) { }
        }
    }
}

