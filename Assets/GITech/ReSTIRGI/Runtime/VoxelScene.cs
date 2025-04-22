using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering; // Required for CommandBuffer and RenderTextures

[ExecuteInEditMode] // Optional: Allows running in the editor
public class VoxelScene : MonoBehaviour
{
    [Header("Voxel Grid Settings")]
    public Vector3Int voxelResolution = new Vector3Int(128, 128, 128);
    public float voxelGridWorldSize = 100.0f; // The size of the cubic voxel grid in world units
    public ComputeShader voxelizerComputeShader; // Assign your Voxelizer Compute Shader here

    [Header("Voxel Data Textures")]
    [SerializeField, HideInInspector] // Hide but serialize to keep the reference
    private RenderTexture voxelAlbedoTexture;
    [SerializeField, HideInInspector]
    private RenderTexture voxelNormalTexture;
    // Add more RenderTextures if needed (e.g., Emission, Metallic/Smoothness)

    private Bounds voxelGridBounds;
    private Matrix4x4 worldToVoxelMatrix;
    private int voxelizerKernelID = -1;

    // Public accessors for other systems (like GI)
    public RenderTexture VoxelAlbedoTexture => voxelAlbedoTexture;
    public RenderTexture VoxelNormalTexture => voxelNormalTexture;
    public Bounds VoxelGridBounds => voxelGridBounds;
    public Matrix4x4 WorldToVoxelMatrix => worldToVoxelMatrix;
    public Vector3Int VoxelResolution => voxelResolution;


    void OnEnable()
    {
        InitializeResources();
        // Optional: Trigger voxelization immediately or based on some condition
        // VoxelizeStaticScene();
    }

    void OnDisable()
    {
        ReleaseResources();
    }

    void Update()
    {
        // Update bounds and matrix if the transform moves
        UpdateVoxelGridTransform();

        // Example: Voxelize every frame if needed (expensive!)
        // Or trigger based on scene changes
        #if UNITY_EDITOR
        if (Application.isPlaying == false) {
             // Optionally update in Edit mode for visualization
             // VoxelizeStaticScene();
        }
        #endif
    }

    void InitializeResources()
    {
        if (voxelizerComputeShader == null)
        {
            Debug.LogError("Voxelizer Compute Shader is not assigned!");
            this.enabled = false;
            return;
        }

        voxelizerKernelID = voxelizerComputeShader.FindKernel("CSMain"); // Make sure your kernel is named "CSMain"

        // Ensure resolution is positive
        voxelResolution.x = Mathf.Max(1, voxelResolution.x);
        voxelResolution.y = Mathf.Max(1, voxelResolution.y);
        voxelResolution.z = Mathf.Max(1, voxelResolution.z);

        // Create RenderTextures
        voxelAlbedoTexture = CreateVoxelTexture("VoxelAlbedo", RenderTextureFormat.ARGB32); // RGBA8 for Albedo
        voxelNormalTexture = CreateVoxelTexture("VoxelNormal", RenderTextureFormat.ARGBHalf); // Higher precision for Normals (e.g., ARGBHalf or ARGB2101010)

        UpdateVoxelGridTransform();

        // Set textures globally for easy shader access (optional)
        Shader.SetGlobalTexture("_VoxelAlbedoTexture", voxelAlbedoTexture);
        Shader.SetGlobalTexture("_VoxelNormalTexture", voxelNormalTexture);
    }

    RenderTexture CreateVoxelTexture(string texName, RenderTextureFormat format)
    {
        // Check if texture already exists and matches description
        RenderTexture tex = GetExistingTextureReference(texName); // Helper to potentially reuse existing textures
        if (tex != null && tex.IsCreated() &&
            tex.dimension == TextureDimension.Tex3D &&
            tex.width == voxelResolution.x &&
            tex.height == voxelResolution.y &&
            tex.volumeDepth == voxelResolution.z &&
            tex.format == format &&
            tex.enableRandomWrite)
        {
            return tex; // Reuse existing texture
        }

        // Release old texture if it exists but doesn't match
        if (tex != null)
        {
            tex.Release();
            DestroyImmediate(tex); // Important in Edit mode
        }

        // Create new texture
        tex = new RenderTexture(voxelResolution.x, voxelResolution.y, 0, format)
        {
            dimension = TextureDimension.Tex3D,
            volumeDepth = voxelResolution.z,
            enableRandomWrite = true, // Crucial for Compute Shader UAV access
            name = texName,
            wrapMode = TextureWrapMode.Clamp,
            filterMode = FilterMode.Bilinear // Or Point depending on usage
        };
        tex.Create();
        ClearRenderTexture(tex); // Clear to default value (e.g., black)
        return tex;
    }

    // Helper to find existing texture by name (implement if needed for robust reuse)
    RenderTexture GetExistingTextureReference(string texName) {
        if (texName == "VoxelAlbedo" && voxelAlbedoTexture != null) return voxelAlbedoTexture;
        if (texName == "VoxelNormal" && voxelNormalTexture != null) return voxelNormalTexture;
        return null;
    }


    void UpdateVoxelGridTransform()
    {
        voxelGridBounds = new Bounds(transform.position, Vector3.one * voxelGridWorldSize);
        // Calculate the matrix to transform world positions to voxel grid coordinates [0, resolution]
        Matrix4x4 translation = Matrix4x4.Translate(-voxelGridBounds.min); // Move corner to origin
        Matrix4x4 scale = Matrix4x4.Scale(new Vector3(voxelResolution.x / voxelGridBounds.size.x,
                                                      voxelResolution.y / voxelGridBounds.size.y,
                                                      voxelResolution.z / voxelGridBounds.size.z));
        worldToVoxelMatrix = scale * translation;

        // Set global shader variables for bounds and matrix
        Shader.SetGlobalVector("_VoxelGridCenter", voxelGridBounds.center);
        Shader.SetGlobalVector("_VoxelGridSize", voxelGridBounds.size);
        Shader.SetGlobalVector("_VoxelResolution", new Vector4(voxelResolution.x, voxelResolution.y, voxelResolution.z, 0));
        Shader.SetGlobalVector("_VoxelResolutionInv", new Vector4(1.0f/voxelResolution.x, 1.0f/voxelResolution.y, 1.0f/voxelResolution.z, 0));
        Shader.SetGlobalMatrix("_WorldToVoxelMatrix", worldToVoxelMatrix);
    }

    void ReleaseResources()
    {
        if (voxelAlbedoTexture != null)
        {
            voxelAlbedoTexture.Release();
            DestroyImmediate(voxelAlbedoTexture); // Use DestroyImmediate if running in Edit mode
            voxelAlbedoTexture = null;
        }
        if (voxelNormalTexture != null)
        {
            voxelNormalTexture.Release();
            DestroyImmediate(voxelNormalTexture);
            voxelNormalTexture = null;
        }
    }

    void ClearRenderTexture(RenderTexture rt)
    {
        // Clearing 3D RTs can be tricky, using a temporary command buffer is reliable
        CommandBuffer cmd = new CommandBuffer();
        cmd.SetRenderTarget(rt); // Set the 3D texture as the target
        cmd.ClearRenderTarget(false, true, Color.clear); // Clear color to transparent black
        Graphics.ExecuteCommandBuffer(cmd);
        cmd.Release();
    }

    // --- Voxelization Trigger ---
    // Call this method to perform the voxelization
    public void VoxelizeStaticScene()
    {
        if (voxelizerComputeShader == null || voxelizerKernelID < 0 || !voxelAlbedoTexture || !voxelNormalTexture)
        {
            Debug.LogError("Voxelization resources not ready.");
            return;
        }

        // 1. Clear Textures (optional, depends if you accumulate or overwrite)
        ClearRenderTexture(voxelAlbedoTexture);
        ClearRenderTexture(voxelNormalTexture);

        // 2. Find Renderers
        // Consider filtering by layer, tag, or static status for optimization
        MeshRenderer[] renderers = FindObjectsOfType<MeshRenderer>();
        // SkinnedMeshRenderer[] skinnedRenderers = FindObjectsOfType<SkinnedMeshRenderer>(); // If needed

        // 3. Prepare Command Buffer
        CommandBuffer cmd = new CommandBuffer { name = "Scene Voxelization" };

        // 4. Set Global Compute Shader Resources (already done in Update/Initialize)
        cmd.SetComputeTextureParam(voxelizerComputeShader, voxelizerKernelID, "_VoxelAlbedoTextureUAV", voxelAlbedoTexture);
        cmd.SetComputeTextureParam(voxelizerComputeShader, voxelizerKernelID, "_VoxelNormalTextureUAV", voxelNormalTexture);
        cmd.SetComputeMatrixParam(voxelizerComputeShader, "_WorldToVoxelMatrix", worldToVoxelMatrix); // Already global, but can be set per-dispatch

        // 5. Iterate and Dispatch per Renderer/Mesh
        foreach (MeshRenderer renderer in renderers)
        {
            if (!renderer.enabled || renderer.sharedMaterial == null) continue;

            MeshFilter meshFilter = renderer.GetComponent<MeshFilter>();
            if (meshFilter == null || meshFilter.sharedMesh == null) continue;

            Mesh mesh = meshFilter.sharedMesh;
            Material material = renderer.sharedMaterial; // Use sharedMaterial to avoid instancing

            // --- Set Per-Object Data ---
            cmd.SetComputeMatrixParam(voxelizerComputeShader, "_LocalToWorldMatrix", renderer.localToWorldMatrix);

            // Pass Material Properties (Example: Base Color Texture)
            if (material.HasTexture("_BaseMap")) // URP Lit Shader uses _BaseMap
            {
                cmd.SetComputeTextureParam(voxelizerComputeShader, voxelizerKernelID, "_ObjectAlbedoTexture", material.GetTexture("_BaseMap"));
            }
            else // Fallback or handle other shaders
            {
                 // Provide a default white texture or handle differently
                 cmd.SetComputeTextureParam(voxelizerComputeShader, voxelizerKernelID, "_ObjectAlbedoTexture", Texture2D.whiteTexture);
            }
             if (material.HasTexture("_BumpMap")) // URP Lit Shader uses _BumpMap for Normal Map
            {
                cmd.SetComputeTextureParam(voxelizerComputeShader, voxelizerKernelID, "_ObjectNormalTexture", material.GetTexture("_BumpMap"));
            }
             else
            {
                 // Provide a default normal texture (flat blue) or handle differently
                 cmd.SetComputeTextureParam(voxelizerComputeShader, voxelizerKernelID, "_ObjectNormalTexture", Texture2D.normalTexture);
            }
            // Pass other properties like color tint, tiling/offset if needed
            cmd.SetComputeVectorParam(voxelizerComputeShader, "_BaseColor", material.HasProperty("_BaseColor") ? material.GetColor("_BaseColor") : Color.white);
            cmd.SetComputeVectorParam(voxelizerComputeShader, "_BaseMap_ST", material.HasProperty("_BaseMap_ST") ? material.GetVector("_BaseMap_ST") : new Vector4(1,1,0,0));
            cmd.SetComputeVectorParam(voxelizerComputeShader, "_BumpMap_ST", material.HasProperty("_BumpMap_ST") ? material.GetVector("_BumpMap_ST") : new Vector4(1,1,0,0));


            // --- Dispatch ---
            // The compute shader needs to iterate through triangles.
            // A common way is to dispatch one thread group per triangle or a fixed number of triangles.
            // Here, we dispatch based on triangle count. Adjust thread group size in compute shader accordingly.
            int triangleCount = mesh.triangles.Length / 3;
            // Example: If your compute shader processes one triangle per thread, and group size is 64:
            // int threadGroups = Mathf.CeilToInt(triangleCount / 64.0f);
            // cmd.DispatchCompute(voxelizerComputeShader, voxelizerKernelID, threadGroups, 1, 1);

            // !! Simplification for now: Dispatch enough groups to cover all voxels.
            //    The compute shader will need logic to figure out which triangles affect which voxels.
            //    A more advanced approach involves passing triangle data in buffers.
            //    This basic dispatch assumes the compute shader iterates internally or uses a different strategy.
             int threadsX = Mathf.CeilToInt((float)voxelResolution.x / 8); // Assuming 8x8x8 thread group size in compute
             int threadsY = Mathf.CeilToInt((float)voxelResolution.y / 8);
             int threadsZ = Mathf.CeilToInt((float)voxelResolution.z / 8);
             // !! This dispatch structure is for a voxel-centric approach (one thread per voxel)
             // !! You'll need a different dispatch if your compute shader is triangle-centric.
             // cmd.DispatchCompute(voxelizerComputeShader, voxelizerKernelID, threadsX, threadsY, threadsZ);

             // TODO: Implement actual dispatch based on chosen compute shader strategy
             //       (e.g., pass mesh buffers and dispatch per triangle)
             Debug.LogWarning("Voxelization dispatch logic needs implementation based on Compute Shader strategy.");

        }

        // 6. Execute Command Buffer
        Graphics.ExecuteCommandBuffer(cmd);

        // 7. Release Command Buffer
        cmd.Release();

        Debug.Log("Scene Voxelization Dispatched (Implementation Pending)");
    }
}