using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ArtSSR
{
    [Serializable, VolumeComponentMenuForRenderPipeline("Lighting/Art SSR", typeof(UniversalRenderPipeline))]
    public class ArtSSREffect : VolumeComponent, IPostProcessComponent
    {
        [InspectorName("State"), Tooltip("When set to Enabled, URP processes SSR on opaque objects for Cameras in the influence of this effect's Volume.")]
        public ArtSSRStateParameter m_State = new(value: SSRState.Disabled, overrideState: true);

        [InspectorName("Tracing Mode")]
        public ArtSSRMarchingModeParameter m_MarchingMode = new(value: RayMarchingMode.LinearViewSpaceTracing, overrideState: false);
        
        [InspectorName("Dither Mode")]
        public ArtSSRDitherModeParameter m_DitherMode = new(value: DitherMode.Disabled, overrideState: false);
        
        [InspectorName("Thickness Scale")]
        public ClampedFloatParameter m_ThicknessScale = new(value: 2.0f, min: 0.001f, max: 30.0f, overrideState: false);
        
        [InspectorName("Minimum Smoothness")]
        public ClampedFloatParameter m_MinSmoothness = new(value: 0.5f, min: 0.0f, max: 1.0f, overrideState: false);
        
        [InspectorName("Smoothness Fade Start")]
        public ClampedFloatParameter m_FadeSmoothness = new(value: 0.6f, min: 0.0f, max: 1.0f, overrideState: false);

        [InspectorName("Ray Step Length")]
        public ClampedFloatParameter m_StepStrideLength = new(value: 0.03f, min: 0.001f, max: 1.0f, overrideState: false);
        
        [InspectorName("Screen Edge Fade Distance"), Tooltip("The distance from the edge of the screen where SSR fades out.")]
        public ClampedFloatParameter m_EdgeFade = new(value: 0.1f, min: 0.0f, max: 1.0f, overrideState: true);
        
        public ClampedIntParameter m_MaxSteps = new(value: 64, min: 32, max: 512, overrideState: false);
        
        public ClampedIntParameter m_DownSample = new(value: 0, min: 0, max: 1, overrideState: false);
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
        public sealed class ArtSSRStateParameter : VolumeParameter<SSRState>
        {
            /// <summary>
            /// Creates a new <see cref="ArtSSRStateParameter"/> instance.
            /// </summary>
            /// <param name="value">The initial value to store in the parameter.</param>
            /// <param name="overrideState">The initial override state for the parameter.</param>
            public ArtSSRStateParameter(SSRState value, bool overrideState = false) : base(value, overrideState) {}
        }

        public enum RayMarchingMode
        {
            [Tooltip("Linear tracing mode.")]
            LinearViewSpaceTracing = 0,
            [Tooltip("2D SS tracing mode.")]
            LinearScreenSpaceTracing = 1,
            [Tooltip("Hi-Z tracing mode.")]
            HiZTracing = 2
        }
        [Serializable]
        public sealed class ArtSSRMarchingModeParameter : VolumeParameter<RayMarchingMode>
        {
            /// <summary>
            /// Creates a new <see cref="ArtSSRMarchingModeParameter"/> instance.
            /// </summary>
            /// <param name="value">The initial value to store in the parameter.</param>
            /// <param name="overrideState">The initial override state for the parameter.</param>
            public ArtSSRMarchingModeParameter(RayMarchingMode value, bool overrideState = false) : base(value, overrideState) {}
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
            public ArtSSRDitherModeParameter(DitherMode value, bool overrideState = false) : base(value, overrideState) {}
        }
    }
}