using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace InstancedGrass
{
    [ExecuteAlways]
    public class InstancedGrassGenerator : MonoBehaviour
    {
        [Range(1, 50000000)]
        public int m_InstanceCount = 10000000;
        public float m_DrawDistance = 125.0f;

        private int m_CurrentCacheCount = -1;

        // Start is called before the first frame update
        void Start()
        {
            UpdatePositionIfNeeded();
        }

        // Update is called once per frame
        void Update()
        {
            UpdatePositionIfNeeded();
        }

        private void OnGUI()
        {
            GUI.Label(new Rect(10, 50, 200, 30), "Instance Count: " + m_InstanceCount / 1000000 + "Million");
            m_InstanceCount = Mathf.Max(1, (int)(GUI.HorizontalSlider(new Rect(10, 100, 200, 30), m_InstanceCount / 1000000f, 1, 10)) * 1000000);

            GUI.Label(new Rect(10, 150, 200, 30), "Draw Distance: " + m_DrawDistance);
            m_DrawDistance = Mathf.Max(1, (int)(GUI.HorizontalSlider(new Rect(10, 200, 200, 30), m_DrawDistance / 25f, 1, 8)) * 25);
            InstancedIndirectGrassRenderer.m_Instance.m_DrawDistance = m_DrawDistance;
        }

        private void UpdatePositionIfNeeded()
        {
            if (m_InstanceCount == m_CurrentCacheCount) return;

            Debug.Log("UpdatePos (Slow)");

            //same seed to keep grass visual the same
            UnityEngine.Random.InitState(123);

            //auto keep density the same
            float scale = Mathf.Sqrt((m_InstanceCount / 4)) / 2f;
            transform.localScale = new Vector3(scale, transform.localScale.y, scale);

            //////////////////////////////////////////////////////////////////////////
            //can define any posWS in this section, random is just an example
            //////////////////////////////////////////////////////////////////////////
            List<Vector3> positions = new List<Vector3>(m_InstanceCount);
            for (int i = 0; i < m_InstanceCount; i++)
            {
                Vector3 pos = Vector3.zero;

                pos.x = UnityEngine.Random.Range(-1f, 1f) * transform.lossyScale.x;
                pos.z = UnityEngine.Random.Range(-1f, 1f) * transform.lossyScale.z;

                //transform to posWS in C#
                pos += transform.position;

                positions.Add(new Vector3(pos.x, pos.y, pos.z));
            }

            //send all posWS to renderer
            InstancedIndirectGrassRenderer.m_Instance.m_GrassPositions = positions;
            m_CurrentCacheCount = positions.Count;
        }
    }

}

