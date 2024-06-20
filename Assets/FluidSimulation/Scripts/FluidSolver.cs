using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using Random = UnityEngine.Random;


public class FluidSolver : MonoBehaviour
{
    Vector4 GetPlaneEq(Vector3 p, Vector3 n)
    {
        return new Vector4(n.x, n.y, n.z, -Vector3.Dot(p, n));
    }

    void Start()
    {
        mainCamera = Camera.main;

        Particle[] particles = new Particle[NumParticles];

        Vector3 StartPos1 = new Vector3(
            Mathf.Lerp(MinBounds.x, MaxBounds.x, 0.25f),
            MinBounds.y + InitPoolSize * 0.5f,
            Mathf.Lerp(MinBounds.z, MaxBounds.z, 0.25f)
        );
        Vector3 StartPos2 = new Vector3(
            Mathf.Lerp(MinBounds.x, MaxBounds.x, 0.75f),
            MinBounds.y + InitPoolSize * 0.5f,
            Mathf.Lerp(MinBounds.z, MaxBounds.z, 0.75f)
        );

        for (int i = 0; i < NumParticles; i++)
        {
            Vector3 pos = new Vector3(
                Random.Range(0.0f, 1.0f) * InitPoolSize - InitPoolSize * 0.5f,
                Random.Range(0.0f, 1.0f) * InitPoolSize - InitPoolSize * 0.5f,
                Random.Range(0.0f, 1.0f) * InitPoolSize - InitPoolSize * 0.5f
            );
            pos += (i % 2 == 0) ? StartPos1 : StartPos2;
            particles[i].Position = pos;
        }

        SolverShader.SetInt("NumHashes", numHashes);
        SolverShader.SetInt("NumParticles", NumParticles);
        SolverShader.SetFloat("Radius", Radius);
        SolverShader.SetFloat("Radius2", Radius * Radius);
        
        hashesBuffer = new ComputeBuffer(NumParticles, 4);
        globalHashCountBuffer = new ComputeBuffer(numHashes, 4);
    }
    
    public int NumParticles = 1024;
    public float InitPoolSize = 10;
    public float Radius = 0.5f;
    
    public Vector3 MinBounds = new Vector3(-10, -10, -10);
    public Vector3 MaxBounds = new Vector3(10, 10, 10);
    
    public ComputeShader SolverShader;
    
    public Material ParticleMaterial;
    
    public Mesh ParticleMesh;
    public float ParticleRenderSize = 0.5f;
    
    public Color PrimaryColor = Color.white;
    
    private Camera mainCamera;
    
    private const int numHashes = 1 << 20;
    private const int numThreads = 1 << 10;

    private ComputeBuffer hashesBuffer;
    private ComputeBuffer globalHashCountBuffer;
    
    // private int solverFrame = 0;
    // private int moveParticleBeginIndex = 0;
    // private double lastFrameTimeStamp = 0;
    // private double totalFrameTime = 0;
    
    
    struct Particle
    {
        public Vector4 Position;
        public Vector4 Velocity;
    }
    
    private CommandBuffer commandBuffer;
    private Mesh screenQuadMesh;
}
