using System;
using System.Collections;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

namespace PRT
{
    [Serializable]
    [CreateAssetMenu(fileName = "LightProbeVolumeData", menuName = "LightProbeVolumeData")]
    public class LightProbeVolumeData : ScriptableObject
    {
        public void StorageSurfelData(LightProbeVolume volume)
        {
            int probeNum = volume.ProbeSizeX * volume.ProbeSizeY * volume.ProbeSizeZ;
            int surfelPerProbe = 512;
            int floatPerSurfel = 10;
            
            Array.Resize<float>(ref SurfelStorageBuffer, probeNum * surfelPerProbe * floatPerSurfel);

            int cnt = 0;
            for (int i = 0; i < volume.Probes.Length; i++)
            {
                LightProbe probe = volume.Probes[i].GetComponent<LightProbe>();
                foreach (var surfel in probe.ReadBackBuffer)
                {
                    SurfelStorageBuffer[cnt++] = surfel.position.x;
                    SurfelStorageBuffer[cnt++] = surfel.position.y;
                    SurfelStorageBuffer[cnt++] = surfel.position.z;
                    SurfelStorageBuffer[cnt++] = surfel.normal.x;
                    SurfelStorageBuffer[cnt++] = surfel.normal.y;
                    SurfelStorageBuffer[cnt++] = surfel.normal.z;
                    SurfelStorageBuffer[cnt++] = surfel.albedo.x;
                    SurfelStorageBuffer[cnt++] = surfel.albedo.y;
                    SurfelStorageBuffer[cnt++] = surfel.albedo.z;
                    SurfelStorageBuffer[cnt++] = surfel.skyMask;
                }
            }

            VolumePosition = volume.gameObject.transform.position;
            EditorUtility.SetDirty(this);
            UnityEditor.AssetDatabase.SaveAssets();
        }
        
        public void TryLoadSurfelData(LightProbeVolume volume)
        {
            int probeNum = volume.ProbeSizeX * volume.ProbeSizeY * volume.ProbeSizeZ;
            int surfelPerProbe = 512;
            int floatPerSurfel = 10;
            bool dataDirty = SurfelStorageBuffer.Length != probeNum * surfelPerProbe * floatPerSurfel;
            bool posDirty = volume.gameObject.transform.position != VolumePosition;

            if (posDirty || dataDirty)
            {
                Debug.LogWarning("Volume Data is out of date, please recompute it.");
                return;
            }

            int cnt = 0;
            foreach (var go in volume.Probes)
            {
                LightProbe probe = go.GetComponent<LightProbe>();
                for (int i = 0; i < probe.ReadBackBuffer.Length; i++)
                {
                    probe.ReadBackBuffer[i].position.x = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].position.y = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].position.z = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].normal.x = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].normal.y = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].normal.z = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].albedo.x = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].albedo.y = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].albedo.z = SurfelStorageBuffer[cnt++];
                    probe.ReadBackBuffer[i].skyMask = SurfelStorageBuffer[cnt++];
                }
                probe.Surfels.SetData(probe.ReadBackBuffer);
            }
        }
        
        [SerializeField]
        public Vector3 VolumePosition;
        [SerializeField]
        public float[] SurfelStorageBuffer;
    }
}