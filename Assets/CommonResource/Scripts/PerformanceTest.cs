using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

namespace ShaderTest.Scripts
{
    public class PerformanceTest : MonoBehaviour
    {
        private bool m_IsShow = false;
        private List<GameObject> m_JadeObjets = new List<GameObject>();

        private void Start()
        {
            Application.targetFrameRate = 120;
            
            Renderer[] renderers = FindObjectsOfType<Renderer>();
            foreach (var rd in renderers)
            {
                if (rd.sharedMaterial != null && rd.sharedMaterial.shader.name == "VFXTest/JadeShader_Baked_SH_H")
                {
                    m_JadeObjets.Add(rd.gameObject);
                }
            }
        }

        private void OnGUI()
        {
            if (GUI.Button(new Rect(20, 20, 120, 40), "ShowOrHiddenObjects"))
            {
                m_IsShow = !m_IsShow;
                foreach (var obj in m_JadeObjets)
                {
                    obj.SetActive(m_IsShow);
                }
            }
            
            GUI.Label(new Rect(20, 70, 120, 40), "FPS: " + (1.0f / Time.deltaTime).ToString("F2"));
            GUI.Label(new Rect(20, 140, 120, 40), "Frame Time: " + (Time.deltaTime * 1000).ToString("F2") + "ms");
        }
    }
}