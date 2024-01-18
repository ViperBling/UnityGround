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
                LightProbeVolume probe = (LightProbeVolume)target;
                probe.GenerateProbes();
            }
            
            if(GUILayout.Button("Capture Scene Probes")) 
            {
                LightProbeVolume probe = (LightProbeVolume)target;
                probe.ProbeCapture();
            }
        }
    }
}