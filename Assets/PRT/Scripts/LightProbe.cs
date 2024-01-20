using System;
using System.Collections;
using System.Drawing;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;
using Color = UnityEngine.Color;

namespace PRT
{
    public struct Surfel
    {
        public Vector3 position;
        public Vector3 normal;
        public Vector3 albedo;
        public float skyMask;
    }

    public enum LightProbeDebugMode
    {
        None = 0,
        SphereDistribution = 1,
        SampleDirection = 2,
        Surfel = 3,
        SurfelRadiance = 4
    }

    [ExecuteAlways]
    public class LightProbe : MonoBehaviour
    {
        public void TryInit()
        {
            if (Surfels == null)
            {
                Surfels = new ComputeBuffer(_rayNum, _surfelByteSize);
            }
            
            if (CoefficientSH9 == null)
            {
                CoefficientSH9 = new ComputeBuffer(27, sizeof(int));
                _coefficientClearValue = new int[27];
                for (int i = 0; i < 27; i++)
                {
                    _coefficientClearValue[i] = 0;
                }
            }

            if (ReadBackBuffer == null) ReadBackBuffer = new Surfel[_rayNum];

            if (SurfelRadiance == null) SurfelRadiance = new ComputeBuffer(_rayNum, sizeof(float) * 3);
            
            if (_radianceDebugBuffer == null) _radianceDebugBuffer = new Vector3[_rayNum];
            
            if (_matPropBlock == null) _matPropBlock = new MaterialPropertyBlock();
            
            if (_tempBuffer == null) _tempBuffer = new ComputeBuffer(1, 4);
        }

        public void CaptureGBufferCubeMaps()
        {
            TryInit();

            GameObject go = new GameObject("CubeMapCamera");
            go.transform.position = transform.position;
            go.transform.rotation = Quaternion.identity;
            go.AddComponent<Camera>();
            Camera cam = go.GetComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.0f, 0.0f, 0.0f, 0.0f);

            GameObject[] gameObjects = FindObjectsOfType(typeof(GameObject)) as GameObject[];
            
            BatchSetShader(gameObjects, Shader.Find("UnityGround/GBufferWorldPos"));
            cam.RenderToCubemap(RT_WorldPos);
            
            BatchSetShader(gameObjects, Shader.Find("UnityGround/GBufferNormal"));
            cam.RenderToCubemap(RT_Normal);
            
            BatchSetShader(gameObjects, Shader.Find("Universal Render Pipeline/Unlit"));
            cam.RenderToCubemap(RT_Albedo);
            
            BatchSetShader(gameObjects, Shader.Find("Universal Render Pipeline/Lit"));
            
            SampleSurfels(RT_WorldPos, RT_Normal, RT_Albedo);
            
            DestroyImmediate(go);
        }

        public void ReLight(CommandBuffer cmd)
        {
            var kid = SurfelReLightCS.FindKernel("MainCS");

            Vector3 pos = gameObject.transform.position;
            cmd.SetComputeVectorParam(SurfelReLightCS, "_ProbePos", new Vector4(pos.x, pos.y, pos.z, 1.0f));
            cmd.SetComputeBufferParam(SurfelReLightCS, kid, "_Surfels", Surfels);
            cmd.SetComputeBufferParam(SurfelReLightCS, kid, "_CoefficientSH9", CoefficientSH9);
            cmd.SetComputeBufferParam(SurfelReLightCS, kid, "_SurfelRadiance", SurfelRadiance);

            var parent = transform.parent;
            LightProbeVolume probeVolume = parent == null ? null : parent.GetComponent<LightProbeVolume>();
            ComputeBuffer coefficientVoxel = probeVolume == null ? _tempBuffer : probeVolume.CoefficientVoxel;
            cmd.SetComputeBufferParam(SurfelReLightCS, kid, "_CoefficientVoxel", coefficientVoxel);
            cmd.SetComputeFloatParam(SurfelReLightCS, "_IndexInProbeVolume", IndexInProbeVolume);
            
            cmd.SetBufferData(CoefficientSH9, _coefficientClearValue);
            cmd.DispatchCompute(SurfelReLightCS, kid, 1, 1, 1);
        }
        
        private void Start()
        {
            TryInit();
        }

        private void OnDestroy()
        {
            if (Surfels != null) Surfels.Release();
            if (CoefficientSH9 != null) CoefficientSH9.Release();
            if (SurfelRadiance != null) SurfelRadiance.Release();
            if (_tempBuffer != null) _tempBuffer.Release();
        }

        private void OnDrawGizmos()
        {
            Vector3 probePos = gameObject.transform.position;

            MeshRenderer meshRenderer = gameObject.GetComponent<MeshRenderer>();
            meshRenderer.enabled = !Application.isPlaying;
            meshRenderer.sharedMaterial.shader = Shader.Find("UnityGround/SHDebug");
            _matPropBlock.SetBuffer("_CoefficientSH9", CoefficientSH9);
            meshRenderer.SetPropertyBlock(_matPropBlock);

            if (DebugMode == LightProbeDebugMode.None) return;
            
            Surfels.GetData(ReadBackBuffer);
            SurfelRadiance.GetData(_radianceDebugBuffer);

            for (int i = 0; i < _rayNum; i++)
            {
                Surfel surfel = ReadBackBuffer[i];
                Vector3 radiance = _radianceDebugBuffer[i];

                Vector3 pos = surfel.position;
                Vector3 normal = surfel.normal;
                Vector3 color = surfel.albedo;

                Vector3 dir = pos - probePos;
                dir = Vector3.Normalize(dir);

                bool isSky = surfel.skyMask >= 0.995;

                Gizmos.color = Color.cyan;

                if (DebugMode == LightProbeDebugMode.SphereDistribution)
                {
                    if (isSky) Gizmos.color = Color.blue;
                    Gizmos.DrawSphere(dir + probePos, 0.025f);
                }

                if (DebugMode == LightProbeDebugMode.SampleDirection)
                {
                    if (isSky)
                    {
                        Gizmos.color = Color.blue;
                        Gizmos.DrawLine(probePos, probePos + dir * 25.0f);
                    }
                    else
                    {
                        Gizmos.DrawLine(probePos, pos);
                        Gizmos.DrawSphere(pos, 0.05f);
                    }
                }
                
                if (DebugMode == LightProbeDebugMode.Surfel)
                {
                    if(isSky) continue;
                    Gizmos.DrawSphere(pos, 0.05f);
                    Gizmos.color = new Color(color.x, color.y, color.z);
                    Gizmos.DrawLine(pos, pos + normal * 0.25f);
                }
                
                if (DebugMode == LightProbeDebugMode.SurfelRadiance)
                {
                    if(isSky) continue;
                    Gizmos.color = new Color(radiance.x, radiance.y, radiance.z);
                    Gizmos.DrawSphere(pos, 0.05f);
                }
            }
        }

        private void BatchSetShader(GameObject[] gameObjects, Shader shader)
        {
            foreach (var go in gameObjects)
            {
                MeshRenderer meshRenderer = go.GetComponent<MeshRenderer>();
                if (meshRenderer != null)
                {
                    meshRenderer.sharedMaterial.shader = shader;
                }
            }
        }

        private void SampleSurfels(RenderTexture worldPosCube, RenderTexture normalCube, RenderTexture albedoCube)
        {
            var kid = SurfelSampleCS.FindKernel("MainCS");

            Vector3 pos = gameObject.transform.position;
            SurfelSampleCS.SetVector("_ProbePos", new Vector4(pos.x, pos.y, pos.z, 1.0f));
            SurfelSampleCS.SetFloat("_RandSeed", UnityEngine.Random.Range(0.0f, 1.0f));
            SurfelSampleCS.SetTexture(kid, "_WorldPosCube", worldPosCube);
            SurfelSampleCS.SetTexture(kid, "_NormalCube", normalCube);
            SurfelSampleCS.SetTexture(kid, "_AlbedoCube", albedoCube);
            SurfelSampleCS.SetBuffer(kid, "_Surfels", Surfels);
            
            SurfelSampleCS.Dispatch(kid, 1, 1, 1);
            Surfels.GetData(ReadBackBuffer);
        }

        private const int _tX = 32;
        private const int _tY = 16;
        private const int _rayNum = _tX * _tY;
        private const int _surfelByteSize = 3 * 12 + 4;  // sizeof(Surfel)
        
        private MaterialPropertyBlock _matPropBlock;
        
        public Surfel[] ReadBackBuffer; // CPU side surfel array, for debug
        public ComputeBuffer Surfels;   // GPU side surfel array
        
        Vector3[] _radianceDebugBuffer;
        public ComputeBuffer SurfelRadiance;
        
        int[] _coefficientClearValue;
        public ComputeBuffer CoefficientSH9; // GPU side SH9 coefficient, size: 9x3=27

        public RenderTexture RT_WorldPos;
        public RenderTexture RT_Normal;
        public RenderTexture RT_Albedo;

        public ComputeShader SurfelReLightCS;
        public ComputeShader SurfelSampleCS;

        [HideInInspector] public int IndexInProbeVolume = -1;
        private ComputeBuffer _tempBuffer;
        
        public LightProbeDebugMode DebugMode;
    }
}