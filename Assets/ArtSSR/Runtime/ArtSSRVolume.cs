using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.UI;

namespace ArtSSR
{
    [Serializable, VolumeComponentMenuForRenderPipeline("Lighting/Art SSR", typeof(UniversalRenderPipeline))]
    public class ArtScreenSpaceReflection : VolumeComponent, IPostProcessComponent
    {
        [InspectorName("State"), Tooltip("When set to Enabled, URP processes SSR on opaque objects for Cameras in the influence of this effect's Volume.")]
        public SSRStateParameter m_State = new(value: SSRState.Disabled, overrideState: true);

        [InspectorName("Tracing Mode")]
        public SSRMarchingModeParameter m_MarchingMode = new(value: RayMarchingMode.LinearScreenSpaceTracing, overrideState: true);

        [InspectorName("BRDF Bias")]
        public ClampedFloatParameter m_BRDFBias = new(value: 0.5f, min: 0.0f, max: 1.0f, overrideState: true);
        [InspectorName("Thickness Scale")]
        public ClampedFloatParameter m_ThicknessScale = new(value: 2.0f, min: 0.001f, max: 30.0f, overrideState: true);
        [InspectorName("Screen Edge Fade Distance"), Tooltip("The distance from the edge of the screen where SSR fades out.")]
        public ClampedFloatParameter m_EdgeFade = new(value: 0.1f, min: 0.0f, max: 1.0f, overrideState: true);

        [Header("HiZ Trace")]
        public BoolParameter m_HiZUseCompute = new(value: true, overrideState: true);

        [Header("Linear Trace")]
        public ClampedIntParameter m_LinearRayDistance = new(value: 512, min: 128, max: 512, overrideState: true);
        [InspectorName("Linear Ray Steps")]
        public ClampedIntParameter m_LinearRaySteps = new(value: 256, min: 1, max: 512, overrideState: true);
        [InspectorName("Linear Ray Step Size")]
        public ClampedFloatParameter m_LinearRayStepSize = new(value: 0.5f, min: 0.1f, max: 20.0f, overrideState: true);

        [Header("Filter Properties")]
        [InspectorName("Blue Noise Texture")]
        public Texture2DParameter m_BlueNoiseTexture = new Texture2DParameter(null, true);
        [InspectorName("BRDF LUT")]
        public Texture2DParameter m_BRDFLUT = new Texture2DParameter(null, true);

        [InspectorName("Enable Temporal Filter")]
        public BoolParameter m_UseTemporalFilter = new(value: false, overrideState: true);

        public ClampedFloatParameter m_TemporalScale = new(value: 0.5f, min: 0.0f, max: 10.0f, overrideState: true);
        public ClampedFloatParameter m_TemporalWeight = new(value: 0.5f, min: 0.0f, max: 0.99f, overrideState: true);

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
    }
}