using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace SSR
{
    [Serializable, VolumeComponentMenuForRenderPipeline("Lighting/Screen Space Reflection", typeof(UniversalRenderPipeline))]
    public class ScreenSpaceReflectionEffect : VolumeComponent, IPostProcessComponent
    {
        [InspectorName("State"), Tooltip("When set to Enabled, URP processes SSR on opaque objects for Cameras in the influence of this effect's Volume.")]
        public SSRStateParameter m_State = new(value: SSRState.Disabled, overrideState: true);

        [InspectorName("Tracing Mode")]
        public SSRMarchingModeParameter m_MarchingMode = new(value: RayMarchingMode.LinearScreenSpaceTracing, overrideState: true);
        
        [InspectorName("Dither Mode")]
        public ArtSSRDitherModeParameter m_DitherMode = new(value: DitherMode.Disabled, overrideState: true);
        
        [InspectorName("Thickness Scale")]
        public ClampedFloatParameter m_ThicknessScale = new(value: 2.0f, min: 0.001f, max: 30.0f, overrideState: true);
        
        [InspectorName("Minimum Smoothness")]
        public ClampedFloatParameter m_MinSmoothness = new(value: 0.5f, min: 0.0f, max: 1.0f, overrideState: true);
        
        [InspectorName("Smoothness Fade Start")]
        public ClampedFloatParameter m_FadeSmoothness = new(value: 0.6f, min: 0.0f, max: 1.0f, overrideState: true);

        [InspectorName("Step Stride")]
        public ClampedFloatParameter m_StepStrideLength = new(value: 0.03f, min: 0.001f, max: 50.0f, overrideState: true);
        
        [InspectorName("Screen Edge Fade Distance"), Tooltip("The distance from the edge of the screen where SSR fades out.")]
        public ClampedFloatParameter m_EdgeFade = new(value: 0.1f, min: 0.0f, max: 1.0f, overrideState: true);
        
        public ClampedIntParameter m_MaxSteps = new(value: 64, min: 32, max: 512, overrideState: true);
        
        public ClampedIntParameter m_DownSample = new(value: 0, min: 0, max: 1, overrideState: true);
        public BoolParameter m_UseTemporalFilter = new(value: false, overrideState: true);
        public ClampedFloatParameter m_BRDFBias = new(value: 0.5f, min: 0.0f, max: 1.0f, overrideState: true);
        [InspectorName("Blue Noise Texture")]
        public Texture2DParameter m_BlueNoiseTexture = new Texture2DParameter(null, true);
        [InspectorName("BRDF LUT")]
        public Texture2DParameter m_BRDFLUT = new Texture2DParameter(null, true);

        public BoolParameter m_ReflectSky = new(value: false, overrideState: true);

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
            public SSRStateParameter(SSRState value, bool overrideState = false) : base(value, overrideState) { }
        }

        public enum RayMarchingMode
        {
            [Tooltip("2D SS tracing mode.")]
            LinearScreenSpaceTracing = 0,
            [Tooltip("Hi-Z tracing mode.")]
            HiZTracing = 1
        }
        [Serializable]
        public sealed class SSRMarchingModeParameter : VolumeParameter<RayMarchingMode>
        {
            /// <summary>
            /// Creates a new <see cref="ArtSSRMarchingModeParameter"/> instance.
            /// </summary>
            /// <param name="value">The initial value to store in the parameter.</param>
            /// <param name="overrideState">The initial override state for the parameter.</param>
            public SSRMarchingModeParameter(RayMarchingMode value, bool overrideState = false) : base(value, overrideState) { }
        }

        public enum DitherMode
        {
            [Tooltip("Disable dither.")]
            Disabled = 0,
            [Tooltip("Dither 8x8.")]
            Dither8x8 = 1,
            [Tooltip("Dither with interleaved gradient.")]
            InterleavedGradient = 2
        }
        [Serializable]
        public sealed class ArtSSRDitherModeParameter : VolumeParameter<DitherMode>
        {
            /// <summary>
            /// Creates a new <see cref="ArtSSRDitherModeParameter"/> instance.
            /// </summary>
            /// <param name="value">The initial value to store in the parameter.</param>
            /// <param name="overrideState">The initial override state for the parameter.</param>
            public ArtSSRDitherModeParameter(DitherMode value, bool overrideState = false) : base(value, overrideState) { }
        }
    }
}

