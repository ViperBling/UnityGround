using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using Random = UnityEngine.Random;

public class FluidSolver : MonoBehaviour
{
    public int      m_NumParticles = 1024;
    public float    m_InitSize = 10;
    public float    m_SmoothRadius = 1;
    public float    m_DeltaTime = 0.001f;
    
    public Vector3 m_MinBounds = new Vector3(-10, -10, -10);
    public Vector3 m_MaxBounds = new Vector3( 10,  10,  10);
    
    public ComputeShader m_SolverCS;
    public Material m_ParticleMaterial;
    
    public Mesh m_ParticleMesh;
    public float m_ParticleSizeScale = 1.0f;
    
    public Color m_PrimaryColor;
    
    private ComputeBuffer m_ParticleBuffer;
    private ComputeBuffer m_ParticleMeshIndirectBuffer;
    private int m_CSKernel;
    
    private double m_LastFrameTimestamp;
    private double m_TotalFrameTime;

    private Vector4[] m_BoxPlanes = new Vector4[7];

    struct Particle
    {
        public Vector4 Position;
        public Vector4 Velocity;
    }

    private CommandBuffer m_CommandBuffer;
    private Mesh m_ScreenQuadMesh;

    private void OnEnable()
    {
        m_ParticleMeshIndirectBuffer = new ComputeBuffer(1, 4 * sizeof(uint), ComputeBufferType.IndirectArguments);
        UpdateBuffers();
    }

    private void Update()
    {
        // TODO : Parameter Update
        // TODO : Kernel Dispatch
    }

    private void OnDisable()
    {
        // TODO : Render Source Release
    }

    public void UpdateCommandBuffer(CommandBuffer cmdBuffer)
    {
        
    }

    void UpdateBuffers()
    {
        Particle[] particles = new Particle[m_NumParticles];

        Vector3 origin = new Vector3(
            Mathf.Lerp(m_MinBounds.x, m_MaxBounds.x, 0.5f),
            m_MinBounds.y + m_InitSize * 0.5f,
            Mathf.Lerp(m_MinBounds.z, m_MaxBounds.z, 0.5f));

        for (int i = 0; i < m_NumParticles; i++)
        {
            Vector3 pos = new Vector3(
                Random.Range(0.0f, 1.0f) * m_InitSize - m_InitSize * 0.5f,
                Random.Range(0.0f, 1.0f) * m_InitSize - m_InitSize * 0.5f,
                Random.Range(0.0f, 1.0f) * m_InitSize - m_InitSize * 0.5f
            );
            pos += origin;
            particles[i].Position = pos;
        }
        
    }
}
