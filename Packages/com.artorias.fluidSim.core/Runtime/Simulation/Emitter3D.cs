using System;
using System.Collections.Generic;
using Unity.Mathematics;
using UnityEngine;

namespace Art.FluidSim
{


    public class Emitter : MonoBehaviour
    {
        public struct EmitterData
        {
            public float3[] m_Positions;
            public float3[] m_Velocities;
        }

        [Serializable]
        public struct EmitterRegion
        {
            public Vector3 m_Center;
            public float m_Size;
            public Color m_DebugColor;
            public float Volume => m_Size * m_Size * m_Size;

            public int CalculateParticleCountPerAxis(int particleDensity)
            {
                int targetParticleCount = (int)(Volume * particleDensity);
                int particlesPerAxis = (int)Math.Cbrt(targetParticleCount);
                return particlesPerAxis;
            }
        }

        public int m_EmitterDensity = 600;
        public float3 m_InitialVelocity;
        public float m_JitterStrength;
        public bool m_ShowEmitterBounds;
        public EmitterRegion[] m_EmitterRegions;

        [Header("Debug Info")]
        public int m_DebugNumParticles;
        public float m_DebugVolume;

        public EmitterData GetEmitterData()
        {
            List<float3> allParticles = new List<float3>();
            List<float3> allVelocities = new List<float3>();

            foreach (EmitterRegion region in m_EmitterRegions)
            {
                int particlePerAxis = region.CalculateParticleCountPerAxis(m_EmitterDensity);
                (float3[] positions, float3[] velocities) = EmitterCube(particlePerAxis, region.m_Center, Vector3.one * region.m_Size);
                allParticles.AddRange(positions);
                allVelocities.AddRange(velocities);
            }

            return new EmitterData() { m_Positions = allParticles.ToArray(), m_Velocities = allVelocities.ToArray() };
        }

        (float3[] p, float3[] v) EmitterCube(int numPerAxis, Vector3 center, Vector3 size)
        {
            int numParticles = numPerAxis * numPerAxis * numPerAxis;
            float3[] positions = new float3[numParticles];
            float3[] velocities = new float3[numParticles];

            int i = 0;

            for (int x = 0; x < numPerAxis; x++)
            {
                for (int y = 0; y < numPerAxis; y++)
                {
                    for (int z = 0; z < numPerAxis; z++)
                    {
                        float tX = x / (numPerAxis - 1.0f);
                        float tY = y / (numPerAxis - 1.0f);
                        float tZ = z / (numPerAxis - 1.0f);

                        float pX = (tX - 0.5f) * size.x + center.x;
                        float pY = (tY - 0.5f) * size.y + center.y;
                        float pZ = (tZ - 0.5f) * size.z + center.z;

                        float3 jitter = UnityEngine.Random.insideUnitSphere * m_JitterStrength;
                        positions[i] = new float3(pX, pY, pZ) + jitter;
                        velocities[i] = m_InitialVelocity;
                        i++;
                    }
                }
            }
            return (positions, velocities);
        }

        void OnValidate()
        {
            m_DebugVolume = 0;
            m_DebugNumParticles = 0;

            if (m_EmitterRegions != null)
            {
                foreach (EmitterRegion region in m_EmitterRegions)
                {
                    m_DebugVolume += region.Volume;
                    int numPerAxis = region.CalculateParticleCountPerAxis(m_EmitterDensity);
                    m_DebugNumParticles += numPerAxis * numPerAxis * numPerAxis;
                }
            }
        }

        void OnDrawGizmos()
        {
            if (m_ShowEmitterBounds)
            {
                foreach (EmitterRegion region in m_EmitterRegions)
                {
                    Gizmos.color = region.m_DebugColor;
                    Gizmos.DrawWireCube(region.m_Center + this.transform.position, Vector3.one * region.m_Size);
                }
            }
        }
    }
}