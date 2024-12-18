using UnityEngine;

namespace ArtSSR
{
    public static class GlobalArtSSRSettings
    {
        const string GlobalScaleShaderProperty = "_ArtSSR_GlobalScale";
        const string GlobalInverseScaleShaderProperty = "_ArtSSR_GlobalInvScale";
        private static float m_GlobaScale = 1.0f;

        public static float GlobalResolutionScale
        {
            get { return m_GlobaScale; }
            internal set
            {
                value = Mathf.Clamp(value, 0.1f, 2.0f);
                m_GlobaScale = value;
                Shader.SetGlobalFloat(GlobalScaleShaderProperty, m_GlobaScale);
                Shader.SetGlobalFloat(GlobalInverseScaleShaderProperty, 1.0f / m_GlobaScale);
            }
        }
    }

    public enum RayTracingMode
    {
        LinearTracing = 0,
        HiZTracing = 1
    }

    public enum DitherMode
    {
        Dither8x8 = 0,
        InterleavedGradient = 1
    }

    public struct ScreenSpaceReflectionSettings
    {
        /// <summary>
        /// Only applies when TracingMode is set to LinearTracing. Ray march step length.
        /// </summary>
        public float StepStrideLength;
        /// <summary>
        /// Max steps the SSR will perform.
        /// </summary>
        public float MaxSteps;
        /// <summary>
        /// Sets working resolution, 0 = current rendering resolution, 1 = half of current rendering resolution
        /// </summary>
        public uint Downsample;
        /// <summary>
        /// Min smoothness value a material needs in order to show SSR
        /// </summary>
        public float MinSmoothness;
        /// <summary>
        /// Tracing mode for SSR
        /// </summary>
        public RayTracingMode TracingMode;
        /// <summary>
        /// Dithering type for SSR
        /// </summary>
        public DitherMode DitherMode;

        public static ScreenSpaceReflectionSettings HiZDefault => new()
        {
            MaxSteps = 128,
            StepStrideLength = 0.03f,
            Downsample = 1,
            MinSmoothness = 0.25f,
            TracingMode = RayTracingMode.HiZTracing,
            DitherMode = DitherMode.InterleavedGradient
        };

        public static ScreenSpaceReflectionSettings LinearDefault => new()
        {
            MaxSteps = 128,
            StepStrideLength = 0.03f,
            Downsample = 1,
            MinSmoothness = 0.25f,
            TracingMode = RayTracingMode.LinearTracing,
            DitherMode = DitherMode.Dither8x8
        };
    }
}