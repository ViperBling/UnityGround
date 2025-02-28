using UnityEngine;
using Art.Fluid.Simulation;
using Art.Fluid.Utilities;

namespace Art.Fluid.Rendering
{
    public class ParticleRendering : MonoBehaviour
    {
        public enum RenderingMode
        {
            None,
            Shaded3D,
            Billboard,
        }

        [Header("Rendering Settings")] public RenderingMode m_RenderingMode = RenderingMode.Billboard;
        public float m_Scale;
        public Gradient m_ColorGradient;
        public int m_GradientResolution;
        public float m_VelocityDisplayMax;
        public int m_MeshResolution;

        // [Header("References")] public Fl

        private void OnValidate()
        {
            
        }

        void Oestroy()
        {
            
        }

        void UpdateSettings()
        {

        }

        public static void TextureFromGradient(ref Texture2D texture, int width, int height, Gradient gradient, FilterMode filterMode = FilterMode.Bilinear)
        {

        }
    }
}