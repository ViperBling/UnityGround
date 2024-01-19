using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

namespace PRT
{
    [CustomEditor(typeof(LightProbeVolume))]
    public class LightProbeVolumeDebug : Editor
    {
        public override void OnInspectorGUI() 
        {
            DrawDefaultInspector();

            if(GUILayout.Button("Probe Capture")) 
            {
                LightProbeVolume probeVolume = (LightProbeVolume)target;
                probeVolume.GenerateProbes();
            }
            
            if(GUILayout.Button("Capture Scene Probes")) 
            {
                LightProbeVolume probeVolume = (LightProbeVolume)target;
                probeVolume.ProbeCapture();
            }
        }
    }
}