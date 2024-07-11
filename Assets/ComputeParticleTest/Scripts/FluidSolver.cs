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
    // public float    m_SmoothRadius = 1;
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
        
    }

    private void OnDisable()
    {
        
    }

    public void UpdateCommandBuffer(CommandBuffer cmdBuffer)
    {
        
    }

    void UpdateBuffers()
    {
        
    }
}
