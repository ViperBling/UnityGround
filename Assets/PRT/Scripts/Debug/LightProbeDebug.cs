using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

namespace PRT
{
    [CustomEditor(typeof(LightProbe))]
    public class LightProbeDebug : Editor
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
        
        void BatchSetShader(GameObject[] gameObjects, Shader shader)
        {
            foreach(var go in gameObjects)
            {
                MeshRenderer meshRenderer = go.GetComponent<MeshRenderer>();
                if(meshRenderer != null)
                {
                    meshRenderer.sharedMaterial.shader = shader;
                }
            }
        }
    }
}