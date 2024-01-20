using System;
using System.Collections;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

namespace PRT
{
    public enum LightProbeVolumeDebugMode
    {
        None = 0,
        ProbeGrid = 1,
        ProbeRadiance = 2
    }
    
    [ExecuteAlways]
    public class LightProbeVolume : MonoBehaviour
    {
        public void GenerateProbes()
        {
            if (Probes != null)
            {
                for (int i = 0; i < Probes.Length; i++) DestroyImmediate(Probes[i]);
            }
            
            if (CoefficientVoxel != null) CoefficientVoxel.Release();
            if (LastFrameCoefficientVoxel != null) LastFrameCoefficientVoxel.Release();

            int probeNum = ProbeSizeX * ProbeSizeY * ProbeSizeZ;

            Probes = new GameObject[probeNum];
            for (int x = 0; x < ProbeSizeX; x++)
            {
                for (int y = 0; y < ProbeSizeY; y++)
                {
                    for (int z = 0; z < ProbeSizeZ; z++)
                    {
                        Vector3 relativePos = new Vector3(x, y, z) * ProbeGridSize;
                        var goTransform = gameObject.transform;

                        int index = x * ProbeSizeY * ProbeSizeZ + y * ProbeSizeZ + z;
                        Probes[index] = Instantiate(ProbePrefab, goTransform) as GameObject;
                        Probes[index].transform.position = relativePos + goTransform.position;
                        Probes[index].GetComponent<LightProbe>().IndexInProbeVolume = index;
                        Probes[index].GetComponent<LightProbe>().TryInit();
                    }
                }
            }
            // 3x9 = 27, SH Coefficients
            CoefficientVoxel = new ComputeBuffer(probeNum * 27, sizeof(int));
            LastFrameCoefficientVoxel = new ComputeBuffer(probeNum * 27, sizeof(int));
            _coefficientVoxelClearValue = new int[probeNum * 27];
            for (int i = 0; i < _coefficientVoxelClearValue.Length; i++) _coefficientVoxelClearValue[i] = 0;
        }
        
        public void ProbeCapture()
        {
            foreach (var go in Probes)
            {
                go.GetComponent<MeshRenderer>().enabled = false;
            }

            foreach (var go in Probes)
            {
                LightProbe probe = go.GetComponent<LightProbe>();
                probe.CaptureGBufferCubeMaps();
            }
            VolumeData.StorageSurfelData(this);
        }
        
        public void ClearCoefficientVoxel(CommandBuffer cmd)
        {
            if (CoefficientVoxel == null || _coefficientVoxelClearValue == null) return;
            cmd.SetBufferData(CoefficientVoxel, _coefficientVoxelClearValue);
        }

        public void SwapLastFrameCoefficientVoxel()
        {
            if (CoefficientVoxel == null || LastFrameCoefficientVoxel == null) return;
            (CoefficientVoxel, LastFrameCoefficientVoxel) = (LastFrameCoefficientVoxel, CoefficientVoxel);
        }

        public Vector3 GetVoxelMinCorner()
        {
            return gameObject.transform.position;
        }
        
        private void Start()
        {
            GenerateProbes();
            VolumeData.TryLoadSurfelData(this);
            DebugMode = LightProbeVolumeDebugMode.ProbeGrid;
        }

        private void Update()
        {
            
        }

        private void OnDestroy()
        {
            if (CoefficientVoxel != null) CoefficientVoxel.Release();
            if (LastFrameCoefficientVoxel != null) LastFrameCoefficientVoxel.Release();
        }

        private void OnDrawGizmos()
        {
            Gizmos.DrawCube(GetVoxelMinCorner(), new Vector3(1, 1, 1));

            if (Probes != null)
            {
                foreach (var go in Probes)
                {
                    LightProbe probe = go.GetComponent<LightProbe>();
                    if (DebugMode == LightProbeVolumeDebugMode.ProbeGrid)
                    {
                        Vector3 cubeSize = new Vector3(ProbeGridSize / 2, ProbeGridSize / 2, ProbeGridSize / 2);
                        Gizmos.DrawWireCube(probe.transform.position + cubeSize, cubeSize * 2.0f);
                    }

                    MeshRenderer meshRenderer = go.GetComponent<MeshRenderer>();
                    if (Application.isPlaying) meshRenderer.enabled = false;
                    if (DebugMode == LightProbeVolumeDebugMode.None) meshRenderer.enabled = false;
                }
            }
        }
        
        public GameObject ProbePrefab;
        
        private RenderTexture RT_WorldPos;
        private RenderTexture RT_Normal;
        private RenderTexture RT_Albedo;

        public int ProbeSizeX = 8;
        public int ProbeSizeY = 4;
        public int ProbeSizeZ = 8;
        public float ProbeGridSize = 2.0f;

        public LightProbeVolumeData VolumeData;
        
        public ComputeBuffer CoefficientVoxel;              // array for each probe's SH coefficient
        public ComputeBuffer LastFrameCoefficientVoxel;     // last frame for inf bounce
        int[] _coefficientVoxelClearValue;

        [Range(0.0f, 50.0f)] public float SkyLightIntensity = 1.0f;
        [Range(0.0f, 50.0f)] public float GIIntensity = 1.0f;
        
        public LightProbeVolumeDebugMode DebugMode = LightProbeVolumeDebugMode.ProbeRadiance;

        public GameObject[] Probes;
    }
}