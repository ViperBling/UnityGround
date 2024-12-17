using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

namespace PRT
{
    [CustomEditor(typeof(LightProbe))]
    public class LightProbeDebug : UnityEditor.Editor
    {
        public override void OnInspectorGUI() 
        {
            DrawDefaultInspector();

            if(GUILayout.Button("Probe Capture")) 
            {
                LightProbe probe = (LightProbe)target;
                probe.CaptureGBufferCubeMaps();
            }
        }
    }
}