using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using Random = UnityEngine.Random;

public class Solver : MonoBehaviour
{
    Vector4 GetPlaneEq(Vector3 p, Vector3 n)
    {
        return new Vector4(n.x, n.y, n.z, -Vector3.Dot(p, n));
    }

    void UpdateParams()
    {
        if (Input.GetKeyDown(KeyCode.X))
        {
            _boundState++;
        }

        Vector4[] currPlanes;
        switch (_boundState)
        {
        case 0 : 
            currPlanes = _boxPlanes;
            break;
        case 1 : 
            currPlanes = _wavePlanes;
            break;
        default: 
            currPlanes = _groundPlanes;
            break;
        }

        if (currPlanes == _wavePlanes)
        {
            _waveTime += deltaTime;
        }

        _boxPlanes[0] = GetPlaneEq(new Vector3(0, 0, 0), Vector3.up);
        _boxPlanes[1] = GetPlaneEq(new Vector3(0, 100, 0), Vector3.down);
        _boxPlanes[2] = GetPlaneEq(new Vector3(-50, 0, 0), Vector3.right);
        _boxPlanes[3] = GetPlaneEq(new Vector3(50, 0, 0), Vector3.left);
        _boxPlanes[4] = GetPlaneEq(new Vector3(0, 0, -50), Vector3.forward);
        _boxPlanes[5] = GetPlaneEq(new Vector3(0, 0, 50), Vector3.back);

        _wavePlanes[0] = GetPlaneEq(new Vector3(0, 0, 0), Vector3.up);
        _wavePlanes[1] = GetPlaneEq(new Vector3(0, 100, 0), Vector3.down);
        _wavePlanes[2] = GetPlaneEq(new Vector3(-50 + Mathf.Pow(Mathf.Sin(_waveTime * 0.2f),8) * 25f, 0, 0), Vector3.right);
        _wavePlanes[3] = GetPlaneEq(new Vector3(50, 0, 0), Vector3.left);
        _wavePlanes[4] = GetPlaneEq(new Vector3(0, 0, -50), Vector3.forward);
        _wavePlanes[5] = GetPlaneEq(new Vector3(0, 0, 50), Vector3.back);

        _groundPlanes[0] = GetPlaneEq(new Vector3(0, 0, 0), Vector3.up);
        _groundPlanes[1] = GetPlaneEq(new Vector3(0, 100, 0), Vector3.down);

        solverShader.SetVectorArray("Planes", currPlanes);
    }
    
    // Start is called before the first frame update
    void Start()
    {
        _mainCamera = Camera.main;
        
        Particle[] particles = new Particle[numParticles];

        // 流体起始位置，两个角落
        Vector3 origin1 = new Vector3(
            Mathf.Lerp(minBounds.x, maxBounds.x, 0.25f),
            minBounds.y + initSize * 0.5f,
            Mathf.Lerp(minBounds.z, maxBounds.z, 0.25f)
        );
        Vector3 origin2 = new Vector3(
            Mathf.Lerp(minBounds.x, maxBounds.x, 0.75f),
            minBounds.y + initSize * 0.5f,
            Mathf.Lerp(minBounds.z, maxBounds.z, 0.75f)
        );

        for (int i = 0; i < numParticles; i++)
        {
            Vector3 pos = new Vector3(
                Random.Range(0.0f, 1.0f) * initSize - initSize * 0.5f,
                Random.Range(0.0f, 1.0f) * initSize - initSize * 0.5f,
                Random.Range(0.0f, 1.0f) * initSize - initSize * 0.5f
            );
            pos += (i % 2 == 0) ? origin1 : origin2;
            particles[i].Position = pos;
        }
        
        solverShader.SetInt("NumHashes", NumHashes);
        solverShader.SetInt("NumParticles", numParticles);
        
        solverShader.SetFloat("RadiusSqr", radius * radius);
        solverShader.SetFloat("Radius", radius);
        solverShader.SetFloat("GasConstant", gasConstant);
        solverShader.SetFloat("RestDensity", restDensity);
        solverShader.SetFloat("Mass", mass);
        solverShader.SetFloat("Viscosity", viscosity);
        solverShader.SetFloat("Gravity", gravity);
        solverShader.SetFloat("DeltaTime", deltaTime);
        
        float poly6 = 315.0f / (64.0f * Mathf.PI * Mathf.Pow(radius, 9.0f));
        float spiky = 45.0f / (Mathf.PI * Mathf.Pow(radius, 6.0f));
        float visco = 45.0f / (Mathf.PI * Mathf.Pow(radius, 6.0f));
        
        solverShader.SetFloat("Poly6Kernel", poly6);
        solverShader.SetFloat("SpikyKernel", spiky);
        solverShader.SetFloat("ViscosityKernel", visco * viscosity);
        
        UpdateParams();

        _hashesBuffer = new ComputeBuffer(numParticles, 4);
        _globalHashCounterBuffer = new ComputeBuffer(NumHashes, 4);
        
        _localIndicesBuffer = new ComputeBuffer(numParticles, 4);
        _inverseIndicesBuffer = new ComputeBuffer(numParticles, 4);

        _particlesBuffer = new ComputeBuffer(numParticles, 4 * 8);
        _particlesBuffer.SetData(particles);
        
        _sortedBuffer = new ComputeBuffer(numParticles, 4 * 8);
        _forcesBuffer = new ComputeBuffer(numParticles * 2, 4 * 4);

        int groupArrayLen = Mathf.CeilToInt(NumHashes / (float)NumThreads);
        _groupArrayBuffer = new ComputeBuffer(groupArrayLen, 4);

        _hashDebugBuffer = new ComputeBuffer(4, 4);
        _hashValueDebugBuffer = new ComputeBuffer(numParticles, 4 * 3);

        _meanBuffer = new ComputeBuffer(numParticles, 4 * 4);
        _covBuffer = new ComputeBuffer(numParticles * 2, 4 * 3);
        _principleBuffer = new ComputeBuffer(numParticles * 4, 4 * 3);
        _hashRangeBuffer = new ComputeBuffer(NumHashes, 4 * 2);

        // 对每个Compute Shader的Kernel分别绑定Buffer
        for (int i = 0; i < 13; i++)
        {
            solverShader.SetBuffer(i, "Hashes", _hashesBuffer);
            solverShader.SetBuffer(i, "GlobalHashCounter", _globalHashCounterBuffer);
            solverShader.SetBuffer(i, "LocalIndices", _localIndicesBuffer);
            solverShader.SetBuffer(i, "InverseIndices", _inverseIndicesBuffer);
            solverShader.SetBuffer(i, "Particles", _particlesBuffer);
            solverShader.SetBuffer(i, "Sorted", _sortedBuffer);
            solverShader.SetBuffer(i, "Forces", _forcesBuffer);
            solverShader.SetBuffer(i, "GroupArray", _groupArrayBuffer);
            solverShader.SetBuffer(i, "HashDebug", _hashDebugBuffer);
            solverShader.SetBuffer(i, "Mean", _meanBuffer);
            solverShader.SetBuffer(i, "CovBuffer", _covBuffer);
            solverShader.SetBuffer(i, "PrincipleBuffer", _principleBuffer);
            solverShader.SetBuffer(i, "HashRangeBuffer", _hashRangeBuffer);
            solverShader.SetBuffer(i, "HashValueDebug", _hashValueDebugBuffer);
        }
        
        renderMat.SetBuffer("Particles", _particlesBuffer);
        renderMat.SetBuffer("Principle", _principleBuffer);
        renderMat.SetFloat("Radius", particleRenderSize * 0.5f);

        _quadInstancedArgsBuffer = new ComputeBuffer(1, sizeof(uint) * 5, ComputeBufferType.IndirectArguments);
        uint[] args = new uint[5];
        args[0] = particleMesh.GetIndexCount(0);
        args[1] = (uint)numParticles;
        args[2] = particleMesh.GetIndexStart(0);
        args[3] = particleMesh.GetBaseVertex(0);
        args[4] = 0;
        _quadInstancedArgsBuffer.SetData(args);

        _sphereInstancedArgsBuffer = new ComputeBuffer(1, sizeof(uint) * 5, ComputeBufferType.IndirectArguments);
        uint[] args2 = new uint[5];
        args2[0] = sphereMesh.GetIndexCount(0);
        args2[1] = (uint)numParticles;
        args2[2] = sphereMesh.GetIndexStart(0);
        args2[3] = sphereMesh.GetBaseVertex(0);
        args2[4] = 0;
        _sphereInstancedArgsBuffer.SetData(args2);

        _screenQuadMesh = new Mesh();
        _screenQuadMesh.vertices = new Vector3[4]
        {
            new Vector3( 1.0f , 1.0f,  0.0f),
            new Vector3(-1.0f , 1.0f,  0.0f),
            new Vector3(-1.0f ,-1.0f,  0.0f),
            new Vector3( 1.0f ,-1.0f,  0.0f),
        };
        _screenQuadMesh.uv = new Vector2[4]
        {
            new Vector2(1, 0),
            new Vector2(0, 0),
            new Vector2(0, 1),
            new Vector2(1, 1)
        };
        _screenQuadMesh.triangles = new int[6] {0, 1, 2, 2, 3, 0};

        _commandBuffer = new CommandBuffer();
        _commandBuffer.name = "FluidRender";
        
        UpdateCommandBuffer();
        if (_mainCamera != null)
        {
            _mainCamera.AddCommandBuffer(CameraEvent.BeforeSkybox, _commandBuffer);
        }
    }

    // Update is called once per frame
    void Update()
    {
        UpdateParams();

        if (Input.GetMouseButton(0))
        {
            Ray mouseRay = _mainCamera.ScreenPointToRay(Input.mousePosition);
            RaycastHit hit;
            if (Physics.Raycast(mouseRay, out hit))
            {
                Vector3 pos = new Vector3(
                    Mathf.Clamp(hit.point.x, minBounds.x, maxBounds.x),
                    maxBounds.y - 1.0f,
                    Mathf.Clamp(hit.point.z, minBounds.z, maxBounds.z));
                
                solverShader.SetInt("MoveBeginIndex", _moveParticleBeginIndex);
                solverShader.SetInt("MoveSize", moveParticles);
                solverShader.SetVector("MovePosition", pos);
                solverShader.SetVector("MoveVelocity", Vector3.down * 70);
                
                solverShader.Dispatch(solverShader.FindKernel("MoveParticles"), 1, 1, 1);

                _moveParticleBeginIndex = (_moveParticleBeginIndex + moveParticles * moveParticles) % numParticles;
            }
        }

        if (Input.GetKeyDown(KeyCode.Space))
        {
            _paused = !_paused;
        }

        if (Input.GetKeyDown(KeyCode.Z))
        {
            _usePositionSmoothing = !_usePositionSmoothing;
            Debug.Log("UsePositionSmoothing: " + _usePositionSmoothing);
        }

        renderMat.SetColor("PrimaryColor", primaryColor.linear);
        renderMat.SetColor("SecondaryColor", secondaryColor.linear);
        renderMat.SetInt("UsePositionSmoothing", _usePositionSmoothing ? 1 : 0);

        double solverStart = Time.realtimeSinceStartupAsDouble;
        
        solverShader.Dispatch(solverShader.FindKernel("ResetCounter"), Mathf.CeilToInt((float)NumHashes / NumThreads), 1, 1);
        solverShader.Dispatch(solverShader.FindKernel("InsertToBucket"), Mathf.CeilToInt((float)numParticles / NumThreads), 1, 1);
        
        // Debug
        if (Input.GetKeyDown(KeyCode.C))
        {
            uint[] debugResult = new uint[4];

            _hashDebugBuffer.SetData(debugResult);
            
            solverShader.Dispatch(solverShader.FindKernel("DebugHash"), Mathf.CeilToInt((float)NumHashes / NumThreads), 1, 1);

            _hashDebugBuffer.GetData(debugResult);
            
            uint usedHashBuckets = debugResult[0];
            uint maxSameHash = debugResult[1];
            
            Debug.Log($"Total buckets: {NumHashes}, Used buckets: {usedHashBuckets}, Used rate: {(float)usedHashBuckets / NumHashes * 100}%");
            Debug.Log($"Avg hash collision: {(float)numParticles / usedHashBuckets}, Max hash collision: {maxSameHash}");
        }
        
        solverShader.Dispatch(solverShader.FindKernel("PrefixSum1"), Mathf.CeilToInt((float)NumHashes / NumThreads), 1, 1);
        
        // @Important: Because of the way prefix sum algorithm implemented,
        // Currently maximum NumHashes value is NumThreads^2.
        Debug.Assert(NumHashes <= NumThreads * NumThreads);
        solverShader.Dispatch(solverShader.FindKernel("PrefixSum2"), 1, 1, 1);
        
        solverShader.Dispatch(solverShader.FindKernel("PrefixSum3"), Mathf.CeilToInt((float)NumHashes / NumThreads), 1, 1);
        solverShader.Dispatch(solverShader.FindKernel("Sort"), Mathf.CeilToInt((float)numParticles / NumThreads), 1, 1);
        solverShader.Dispatch(solverShader.FindKernel("CalcHashRange"), Mathf.CeilToInt((float)NumHashes / NumThreads), 1, 1);
        
        // Debug
        if (Input.GetKeyDown(KeyCode.C))
        {
            uint[] debugResult = new uint[4];
            int[] values = new int[numParticles * 3];
            
            _hashDebugBuffer.SetData(debugResult);
            solverShader.Dispatch(solverShader.FindKernel("DebugHash"), Mathf.CeilToInt((float)NumHashes / NumThreads), 1, 1);
            _hashDebugBuffer.GetData(debugResult);

            uint totalAccessCount = debugResult[2];
            uint totalNeighborCount = debugResult[3];
            
            Debug.Log($"Total access: {totalAccessCount}, Avg access: {(float)totalAccessCount / numParticles}, Avg accept: {(float)totalNeighborCount / numParticles}");
            Debug.Log($"Avg accept rate: {(float)totalNeighborCount / totalAccessCount * 100}%");
            
            _hashValueDebugBuffer.GetData(values);

            HashSet<Vector3Int> set = new HashSet<Vector3Int>();
            for (int i = 0; i < numParticles; i++)
            {
                Vector3Int hash = new Vector3Int(values[i * 3], values[i * 3 + 1], values[i * 3 + 2]);
                set.Add(hash);
            }
            Debug.Log($"Total unique hash: {set.Count}, Ideal bucket load: {(float)set.Count / NumHashes * 100}%");
        }

        if (!_paused)
        {
            for (int iter = 0; iter < 1; iter++)
            {
                solverShader.Dispatch(solverShader.FindKernel("CalcPressure"), Mathf.CeilToInt((float)numParticles / 128), 1, 1);
                solverShader.Dispatch(solverShader.FindKernel("CalcForces"), Mathf.CeilToInt((float)numParticles / 128), 1, 1);
                solverShader.Dispatch(solverShader.FindKernel("CalcPCA"), Mathf.CeilToInt((float)numParticles / NumThreads), 1, 1);
                solverShader.Dispatch(solverShader.FindKernel("Update"), Mathf.CeilToInt((float)numParticles / NumThreads), 1, 1);
            }

            _solverFrame++;

            if (_solverFrame > 1)
            {
                _totalFrameTime += Time.realtimeSinceStartupAsDouble - _lastFrameTimestamp;
            }

            if (_solverFrame == 400 || _solverFrame == 1200)
            {
                Debug.Log($"Avg frame time at #{_solverFrame}: {_totalFrameTime / (_solverFrame - 1) * 1000}ms.");
            }
        }
        _lastFrameTimestamp = Time.realtimeSinceStartupAsDouble;
    }

    void UpdateCommandBuffer()
    {
        _commandBuffer.Clear();

        int[] worldPosBufferIDs = new int[]
        {
            Shader.PropertyToID("WorldPosBuffer0"),
            Shader.PropertyToID("WorldPosBuffer1"),
        };
        _commandBuffer.GetTemporaryRT(worldPosBufferIDs[0], Screen.width, Screen.height, 0, FilterMode.Point, RenderTextureFormat.ARGBFloat);
        _commandBuffer.GetTemporaryRT(worldPosBufferIDs[1], Screen.width, Screen.height, 0, FilterMode.Point, RenderTextureFormat.ARGBFloat);
        
        int depthID = Shader.PropertyToID("DepthBuffer");
        _commandBuffer.GetTemporaryRT(depthID,  Screen.width, Screen.height, 32, FilterMode.Point, RenderTextureFormat.Depth);
        _commandBuffer.SetRenderTarget((RenderTargetIdentifier)worldPosBufferIDs[0], (RenderTargetIdentifier)depthID);
        _commandBuffer.ClearRenderTarget(true, true, Color.clear);
        _commandBuffer.DrawMeshInstancedIndirect(sphereMesh, 0, renderMat, 0, _sphereInstancedArgsBuffer);

        int depthID1 = Shader.PropertyToID("DepthBuffer1");
        _commandBuffer.GetTemporaryRT(depthID1,  Screen.width, Screen.height, 32, FilterMode.Point, RenderTextureFormat.Depth);
        _commandBuffer.SetRenderTarget((RenderTargetIdentifier)worldPosBufferIDs[0], (RenderTargetIdentifier)depthID1);
        _commandBuffer.ClearRenderTarget(true, true, Color.clear);
        _commandBuffer.SetGlobalTexture("DepthBuffer", depthID);
        _commandBuffer.DrawMesh(_screenQuadMesh, Matrix4x4.identity, renderMat, 0, 1);
        
        int normalBufferID = Shader.PropertyToID("NormalBuffer");
        _commandBuffer.GetTemporaryRT(normalBufferID,  Screen.width, Screen.height, 0, FilterMode.Point, RenderTextureFormat.ARGBHalf);
        
        int colorBufferID = Shader.PropertyToID("ColorBuffer");
        _commandBuffer.GetTemporaryRT(colorBufferID,  Screen.width, Screen.height, 0, FilterMode.Point, RenderTextureFormat.RGHalf);
        
        _commandBuffer.SetRenderTarget(new RenderTargetIdentifier[] {normalBufferID, colorBufferID}, (RenderTargetIdentifier)depthID1);
        _commandBuffer.ClearRenderTarget(false, true, Color.clear);
        
        _commandBuffer.SetGlobalTexture("WorldPosBuffer", worldPosBufferIDs[0]);
        _commandBuffer.DrawMeshInstancedIndirect(particleMesh, 0, renderMat, 2, _quadInstancedArgsBuffer);
        
        _commandBuffer.SetGlobalTexture("NormalBuffer", normalBufferID);
        _commandBuffer.SetGlobalTexture("ColorBuffer", colorBufferID);
        _commandBuffer.SetRenderTarget(BuiltinRenderTextureType.CameraTarget);
        
        _commandBuffer.DrawMesh(_screenQuadMesh, Matrix4x4.identity, renderMat, 0, 3);
    }

    void LateUpdate()
    {
        Matrix4x4 view = _mainCamera.worldToCameraMatrix;

        Shader.SetGlobalMatrix("InverseViewMat", view.inverse);
        Shader.SetGlobalMatrix("InverseProjMat", _mainCamera.projectionMatrix.inverse);
    }

    void OnDisable()
    {
        _hashesBuffer.Dispose();
        _globalHashCounterBuffer.Dispose();
        _localIndicesBuffer.Dispose();
        _inverseIndicesBuffer.Dispose();
        _particlesBuffer.Dispose();
        _sortedBuffer.Dispose();
        _forcesBuffer.Dispose();
        _groupArrayBuffer.Dispose();
        _hashDebugBuffer.Dispose();
        _meanBuffer.Dispose();
        _covBuffer.Dispose();
        _principleBuffer.Dispose();
        _hashRangeBuffer.Dispose();
        
        _quadInstancedArgsBuffer.Dispose();
    }
    
    Camera _mainCamera;
    
    const int NumHashes = 1 << 20;
    const int NumThreads = 1 << 10;     // 1024(Threads Count)
    public int numParticles = 1024;
    public float initSize = 10;
    
    public float radius = 1;
    public float gasConstant = 2000;
    public float restDensity = 10;
    public float mass = 1;
    public float density = 1;
    public float viscosity = 0.01f;
    public float gravity = 9.8f;
    public float deltaTime = 0.001f;

    public Vector3 minBounds = new Vector3(-10, -10, -10);
    public Vector3 maxBounds = new Vector3(10, 10, 10);

    public ComputeShader solverShader;

    // public Shader renderShader;
    public Material renderMat;
    public Material testMat;

    public Mesh particleMesh;
    public float particleRenderSize = 0.5f;

    public Mesh sphereMesh;

    public Color primaryColor;
    public Color secondaryColor;

    private ComputeBuffer _hashesBuffer;
    private ComputeBuffer _globalHashCounterBuffer;
    private ComputeBuffer _localIndicesBuffer;
    private ComputeBuffer _inverseIndicesBuffer;
    private ComputeBuffer _particlesBuffer;
    private ComputeBuffer _sortedBuffer;
    private ComputeBuffer _forcesBuffer;
    private ComputeBuffer _groupArrayBuffer;
    private ComputeBuffer _hashDebugBuffer;
    private ComputeBuffer _hashValueDebugBuffer;
    private ComputeBuffer _meanBuffer;
    private ComputeBuffer _covBuffer;
    private ComputeBuffer _principleBuffer;
    private ComputeBuffer _hashRangeBuffer;

    private ComputeBuffer _quadInstancedArgsBuffer;
    private ComputeBuffer _sphereInstancedArgsBuffer;

    private int _solverFrame = 0;

    private int _moveParticleBeginIndex = 0;
    public int moveParticles = 10;

    private double _lastFrameTimestamp = 0;
    private double _totalFrameTime = 0;

    private int _boundState = 0;
    private float _waveTime = 0;
    private Vector4[] _boxPlanes = new Vector4[7];
    private Vector4[] _wavePlanes = new Vector4[7];
    private Vector4[] _groundPlanes = new Vector4[7];

    struct Particle
    {
        public Vector4 Position;
        public Vector4 Velocity;
    }

    private bool _paused = false;
    private bool _usePositionSmoothing = true;

    private CommandBuffer _commandBuffer;
    private Mesh _screenQuadMesh;
}
