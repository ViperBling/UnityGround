using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using Random = UnityEngine.Random;
using Vector3 = UnityEngine.Vector3;

public class TestSolver : MonoBehaviour
{
    public int      m_NumParticles = 1024;
    public float    m_InitSize = 10;
    public float    m_SmoothRadius = 1;
    public float    m_DeltaTime = 0.001f;

    public Vector3 m_MinBounds = new Vector3(-10, -10, -10);
    public Vector3 m_MaxBounds = new Vector3( 10,  10,  10);

    public ComputeShader m_TestSolverCS;

    public Shader m_RenderShader;
    public Material m_ParticleMaterial;

    public Mesh m_ParticleMesh;
    public float m_ParticleRenderSize = 1.0f;

    public Color m_PrimaryColor;
    
    private ComputeBuffer m_ParticleBuffer;
    
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

    private Camera m_MainCamera;
    
    Vector4 GetPlaneEq(Vector3 p, Vector3 n)
    {
        return new Vector4(n.x, n.y, n.z, -Vector3.Dot(p, n));
    }

    void UpdateBoundState()
    {
        m_BoxPlanes[0] = GetPlaneEq(new Vector3( 0,  0,   0),  Vector3.up);
        m_BoxPlanes[1] = GetPlaneEq(new Vector3( 0,  100, 0),  Vector3.down);
        m_BoxPlanes[2] = GetPlaneEq(new Vector3(-50, 0,   0),  Vector3.right);
        m_BoxPlanes[3] = GetPlaneEq(new Vector3( 50, 0,   0),  Vector3.left);
        m_BoxPlanes[4] = GetPlaneEq(new Vector3( 0,  0,  -50), Vector3.forward);
        m_BoxPlanes[5] = GetPlaneEq(new Vector3( 0,  0,   50), Vector3.back);
        
        m_TestSolverCS.SetVectorArray("BoundPlanes", m_BoxPlanes);
    }

    void Start()
    {
        m_MainCamera = Camera.main;
        
        Particle[] particles = new Particle[m_NumParticles];
        
        Vector3 startOrigin1 = new Vector3(
            Mathf.Lerp(m_MinBounds.x, m_MaxBounds.x, 0.25f),
            m_MinBounds.y + m_InitSize * 0.5f,
            Mathf.Lerp(m_MinBounds.z, m_MaxBounds.z, 0.25f)
        );
        Vector3 startOrigin2 = new Vector3(
            Mathf.Lerp(m_MinBounds.x, m_MaxBounds.x, 0.75f),
            m_MinBounds.y + m_InitSize * 0.5f,
            Mathf.Lerp(m_MinBounds.z, m_MaxBounds.z, 0.75f)
        );
        
        for (int i = 0; i < m_NumParticles; i++)
        {
            Vector3 pos = new Vector3(
                Random.Range(0.0f, 1.0f) * m_InitSize - m_InitSize * 0.5f,
                Random.Range(0.0f, 1.0f) * m_InitSize - m_InitSize * 0.5f,
                Random.Range(0.0f, 1.0f) * m_InitSize - m_InitSize * 0.5f
            );
            pos += (i % 2 == 0) ? startOrigin1 : startOrigin2;
            particles[i].Position = pos;
        }
        
        m_TestSolverCS.SetInt("NumParticles", m_NumParticles);
        
        m_TestSolverCS.SetFloat("SmoothRadiusSqr", m_SmoothRadius * m_SmoothRadius);
        m_TestSolverCS.SetFloat("SmoothRadius", m_SmoothRadius);
        m_TestSolverCS.SetFloat("DeltaTime", m_DeltaTime);
        
        UpdateBoundState();
        
        m_ParticleBuffer = new ComputeBuffer(m_NumParticles, 4 * 8);
        m_ParticleBuffer.SetData(particles);
        
        m_ParticleMaterial.SetBuffer("ParticlesBuffer", m_ParticleBuffer);
        m_ParticleMaterial.SetFloat("ParticleSize", m_ParticleRenderSize * 0.5f);


        m_ScreenQuadMesh = new Mesh();
        m_ScreenQuadMesh.vertices = new Vector3[4]
        {
            new Vector3(1.0f, 1.0f, 0.0f),
            new Vector3(-1.0f, 1.0f, 0.0f),
            new Vector3(-1.0f, -1.0f, 0.0f),
            new Vector3(1.0f, -1.0f, 0.0f),
        };
        m_ScreenQuadMesh.uv = new Vector2[4]
        {
            new Vector2(1, 0),
            new Vector2(0, 0),
            new Vector2(0, 1),
            new Vector2(1, 1)
        };
        m_ScreenQuadMesh.triangles = new int[6] { 0, 1, 2, 2, 3, 0 };

        m_CommandBuffer = new CommandBuffer();
        m_CommandBuffer.name = "Particle Sim";
        
        UpdateCommandBuffer();
        m_MainCamera.AddCommandBuffer(CameraEvent.AfterForwardAlpha, m_CommandBuffer);
    }

    void UpdateCommandBuffer()
    {
        m_CommandBuffer.Clear();
        m_CommandBuffer.DrawMesh(m_ScreenQuadMesh, Matrix4x4.identity, m_ParticleMaterial);
    }
}