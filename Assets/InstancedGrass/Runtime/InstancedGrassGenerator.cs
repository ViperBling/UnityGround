using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace InstancedGrass
{
    [ExecuteAlways]
    public class InstancedGrassGenerator : MonoBehaviour
    {
        [Range(1, 50000000)]
        public int m_InstanceCount = 10000;
        public float m_DrawDistance = 125.0f;

        [Header("Distribution Box")]
        public Vector3 m_BoxSize = new Vector3(100, 1, 100);
        public Vector3 m_BoxCenter = new Vector3(0, 0, 0);

        [Range(0.1f, 5.0f)]
        public float m_DensityFactor = 1.0f;

        private Vector3 m_LastBoxSize;
        private Vector3 m_LastBoxCenter;
        private float m_LastDensityFactor;

        private int m_CurrentCacheCount = -1;

        // Start is called before the first frame update
        void Start()
        {
            UpdatePositionIfNeeded();
        }

        void OnEnable()
        {
            UpdatePositionIfNeeded();
        }

        // Update is called once per frame
        void Update()
        {
            if (m_LastBoxSize != m_BoxSize || m_LastBoxCenter != m_BoxCenter || m_LastDensityFactor != m_DensityFactor)
            {
                m_CurrentCacheCount = -1; // 强制更新
                m_LastBoxSize = m_BoxSize;
                m_LastBoxCenter = m_BoxCenter;
                m_LastDensityFactor = m_DensityFactor;
            }

            UpdatePositionIfNeeded();
        }

        private void OnGUI()
        {
            GUI.Label(new Rect(10, 50, 200, 30), "Instance Count: " + m_InstanceCount / 1000000 + "Million");
            m_InstanceCount = Mathf.Max(1, (int)(GUI.HorizontalSlider(new Rect(10, 100, 200, 30), m_InstanceCount / 1000000f, 1, 10)) * 1000000);

            GUI.Label(new Rect(10, 150, 200, 30), "Draw Distance: " + m_DrawDistance);
            m_DrawDistance = Mathf.Max(1, (int)(GUI.HorizontalSlider(new Rect(10, 200, 200, 30), m_DrawDistance / 25f, 1, 8)) * 25);
            // 添加密度控制
            GUI.Label(new Rect(10, 250, 200, 30), "Density: " + m_DensityFactor.ToString("F1"));
            float newDensity = GUI.HorizontalSlider(new Rect(10, 300, 200, 30), m_DensityFactor, 0.1f, 5.0f);
            if (newDensity != m_DensityFactor)
            {
                m_DensityFactor = newDensity;
                m_CurrentCacheCount = -1; // 强制更新
            }
            
            if (InstancedIndirectGrassRenderer.m_Instance != null)
            {
                InstancedIndirectGrassRenderer.m_Instance.m_DrawDistance = m_DrawDistance;
            }
        }

        private void OnDrawGizmos()
        {
            // 绘制分布范围的Box
            Gizmos.color = new Color(0.3f, 1.0f, 0.3f, 0.3f);
            Vector3 boxWorldCenter = transform.position + m_BoxCenter;
            Gizmos.DrawWireCube(boxWorldCenter, m_BoxSize);
            
            // 绘制地面
            Gizmos.color = new Color(0.3f, 0.8f, 0.3f, 0.1f);
            Vector3 groundCenter = boxWorldCenter;
            groundCenter.y = boxWorldCenter.y - m_BoxSize.y * 0.5f + 0.01f;
            Vector3 groundSize = new Vector3(m_BoxSize.x, 0.02f, m_BoxSize.z);
            Gizmos.DrawCube(groundCenter, groundSize);
        }

        private void UpdatePositionIfNeeded()
        {
            if (InstancedIndirectGrassRenderer.m_Instance == null) return;

            if (m_InstanceCount == m_CurrentCacheCount) return;

            Debug.Log("UpdatePos (Slow)");

            //same seed to keep grass visual the same
            UnityEngine.Random.InitState(123);

            Vector3 boxSize = m_BoxSize;
            Vector3 boxCenter = m_BoxCenter + transform.position;

            Vector3 boxMin = boxCenter - boxSize * 0.5f;
            Vector3 boxMax = boxCenter + boxSize * 0.5f;

            List<Vector3> positions = new List<Vector3>(m_InstanceCount);

            // 方法1：完全随机分布
            if (m_DensityFactor >= 1.0f)
            {
                // 高密度均匀随机分布
                for (int i = 0; i < m_InstanceCount; i++)
                {
                    Vector3 pos = new Vector3(
                        UnityEngine.Random.Range(boxMin.x, boxMax.x),
                        boxMin.y, // 使用Box的底部Y坐标
                        UnityEngine.Random.Range(boxMin.z, boxMax.z)
                    );
                    
                    positions.Add(pos);
                }
            }
            else
            {
                // 低密度分布（更集中的草丛）
                int clusterCount = Mathf.CeilToInt(m_InstanceCount / 50);
                List<Vector3> clusterCenters = new List<Vector3>(clusterCount);
                
                // 先生成草丛中心点
                for (int i = 0; i < clusterCount; i++)
                {
                    Vector3 center = new Vector3(
                        UnityEngine.Random.Range(boxMin.x, boxMax.x),
                        boxMin.y,
                        UnityEngine.Random.Range(boxMin.z, boxMax.z)
                    );
                    clusterCenters.Add(center);
                }
                
                // 在草丛中心点周围生成草
                float clusterRadius = Mathf.Min(m_BoxSize.x, m_BoxSize.z) * 0.05f * m_DensityFactor;
                for (int i = 0; i < m_InstanceCount; i++)
                {
                    // 选择一个草丛中心
                    Vector3 center = clusterCenters[i % clusterCenters.Count];
                    
                    // 在中心点附近随机生成
                    float angle = UnityEngine.Random.Range(0, Mathf.PI * 2);
                    float distance = UnityEngine.Random.Range(0, clusterRadius);
                    
                    Vector3 pos = center + new Vector3(
                        Mathf.Cos(angle) * distance,
                        0,
                        Mathf.Sin(angle) * distance
                    );
                    
                    // 确保在Box范围内
                    pos.x = Mathf.Clamp(pos.x, boxMin.x, boxMax.x);
                    pos.z = Mathf.Clamp(pos.z, boxMin.z, boxMax.z);
                    
                    positions.Add(pos);
                }
            }


            //send all posWS to renderer
            InstancedIndirectGrassRenderer.m_Instance.m_GrassPositions = positions;
            m_CurrentCacheCount = positions.Count;
        }
    }
}