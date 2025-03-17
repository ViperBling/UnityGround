using System;
using System.Collections.Generic;
using Unity.Collections;
using Unity.Jobs;
using UnityEditor.Graphs;
using UnityEngine;
using UnityEngine.Profiling;
using UnityEngine.UI;

namespace InstancedGrass
{
    [ExecuteAlways]
    public class InstancedIndirectGrassRenderer : MonoBehaviour
    {
        [Header("Settings")]
        public float m_DrawDistance = 125.0f;

        public Material m_GrassMaterial;

        [Header("Internal")]
        public ComputeShader m_CullingComputeShader;

        [NonSerialized]
        public List<Vector3> m_GrassPositions = new List<Vector3>();

        [HideInInspector]
        public static InstancedIndirectGrassRenderer m_Instance;

        // public List<Mesh> m_GrassMeshList = new List<Mesh>();

        private int m_CellCountX = -1;
        private int m_CellCountZ = -1;
        private int m_DispatchCount = -1;

        private float m_CellSizeX = 10;
        private float m_CellSizeZ = 10;

        private int m_InstanceCountCache = -1;

        private ComputeBuffer m_InstancePositionBuffer;
        private ComputeBuffer m_VisibleInstanceIndexBuffer;
        private ComputeBuffer m_ArgsBuffer;

        private List<Vector3>[] m_CellPositionList;

        private float m_MinX, m_MinZ, m_MaxX, m_MaxZ;

        private List<int> m_VisibleCellIDList = new List<int>();
        private Plane[] m_FrustumPlanes = new Plane[6];

        private bool m_ShouldBatchDispatch = true;

        private Mesh m_CachedMesh;

        private void OnEnable()
        {
            m_Instance = this;
        }

        private void OnDisable()
        {
            if (m_InstancePositionBuffer != null)
            {
                m_InstancePositionBuffer.Release();
                m_InstancePositionBuffer = null;
            }
            if (m_VisibleInstanceIndexBuffer != null)
            {
                m_VisibleInstanceIndexBuffer.Release();
                m_VisibleInstanceIndexBuffer = null;
            }
            if (m_ArgsBuffer != null)
            {
                m_ArgsBuffer.Release();
                m_ArgsBuffer = null;
            }
            m_Instance = null;
        }

        private void LateUpdate() 
        {
            UpdateAllInstanceTransformBufferIfNeeded();

            m_VisibleCellIDList.Clear();
            Camera camera = Camera.main;

            float cameraOriginalFarPlane = camera.farClipPlane;
            camera.farClipPlane = m_DrawDistance;
            GeometryUtility.CalculateFrustumPlanes(camera, m_FrustumPlanes);
            camera.farClipPlane = cameraOriginalFarPlane;

            Profiler.BeginSample("CPU Cell Frustum Culling");

            for (int i = 0; i < m_CellPositionList.Length; i++)
            {
                Vector3 centerPosWS = new Vector3(i % m_CellCountX + 0.5f, 0, i / m_CellCountX + 0.5f);
                centerPosWS.x = Mathf.Lerp(m_MinX, m_MaxX, centerPosWS.x / m_CellCountX);
                centerPosWS.z = Mathf.Lerp(m_MinZ, m_MaxZ, centerPosWS.z / m_CellCountZ);
                Vector3 sizeWS = new Vector3(Mathf.Abs(m_MaxX - m_MinX) / m_CellCountX, 0, Mathf.Abs(m_MaxX - m_MinX) / m_CellCountX);
                Bounds cellBounds = new Bounds(centerPosWS, sizeWS);

                if (GeometryUtility.TestPlanesAABB(m_FrustumPlanes, cellBounds))
                {
                    m_VisibleCellIDList.Add(i);
                }
            }
            Profiler.EndSample();

            var viewMatrix = camera.worldToCameraMatrix;
            var projMatrix = camera.projectionMatrix;
            var viewProjMatrix = projMatrix * viewMatrix;

            m_VisibleInstanceIndexBuffer.SetCounterValue(0);

            m_CullingComputeShader.SetMatrix("_VPMatrix", viewProjMatrix);
            m_CullingComputeShader.SetFloat("_MaxDrawDistance", m_DrawDistance);

            m_DispatchCount = 0;
            for (int i = 0; i < m_VisibleCellIDList.Count; i++)
            {
                int targetCellFlattenID = m_VisibleCellIDList[i];
                int memoryOffset = 0;
                for (int j = 0; j < targetCellFlattenID; j++)
                {
                    memoryOffset += m_CellPositionList[j].Count;
                }
                m_CullingComputeShader.SetInt("_StartOffset", memoryOffset);
                int jobLength = m_CellPositionList[targetCellFlattenID].Count;

                if (m_ShouldBatchDispatch)
                {
                    while ((i < m_VisibleCellIDList.Count - 1) && (m_VisibleCellIDList[i + 1] == m_VisibleCellIDList[i] + 1))
                    {
                        jobLength += m_CellPositionList[m_VisibleCellIDList[i + 1]].Count;
                        i++;
                    }
                }
                m_CullingComputeShader.Dispatch(0, Mathf.CeilToInt(jobLength / 64.0f), 1, 1);
                m_DispatchCount++;
            }

            ComputeBuffer.CopyCount(m_VisibleInstanceIndexBuffer, m_ArgsBuffer, 4);

            Bounds renderBound = new Bounds();
            renderBound.SetMinMax(new Vector3(m_MinX, 0, m_MinZ), new Vector3(m_MaxX, 0, m_MaxZ));
            Graphics.DrawMeshInstancedIndirect(GetGrassMeshCache(), 0, m_GrassMaterial, renderBound, m_ArgsBuffer);
        }

        private void OnGUI()
        {
            GUI.contentColor = Color.black;
            GUI.Label(new Rect(10, 0, 400, 60),
                $"After CPU cell frustum culling,\n" +
                $"-Visible cell count = {m_VisibleCellIDList.Count}/{m_CellCountX * m_CellCountZ}\n" +
                $"-Real compute dispatch count = {m_DispatchCount} (saved by batching = {m_VisibleCellIDList.Count - m_DispatchCount})");

            m_ShouldBatchDispatch = GUI.Toggle(new Rect(10, 300, 200, 100), m_ShouldBatchDispatch, "ShouldBatchDispatch");
        }

        Mesh GetGrassMeshCache()
        {
            if (!m_CachedMesh)
            {
                //if not exist, create a 3 vertices hardcode triangle grass mesh
                m_CachedMesh = new Mesh();

                //single grass (vertices)
                Vector3[] verts = new Vector3[3];
                verts[0] = new Vector3(-0.15f, 0);
                verts[1] = new Vector3(+0.15f, 0);
                verts[2] = new Vector3(-0.0f, 1);
                //single grass (Triangle index)
                int[] trinagles = new int[3] { 2, 1, 0, }; //order to fit Cull Back in grass shader

                m_CachedMesh.SetVertices(verts);
                m_CachedMesh.SetTriangles(trinagles, 0);
            }
            return m_CachedMesh;
        }

        void UpdateAllInstanceTransformBufferIfNeeded()
        {
            m_GrassMaterial.SetVector("_PivotPosWS", transform.position);
            m_GrassMaterial.SetVector("_BoundSize", new Vector2(transform.localScale.x, transform.localScale.z));

            if (m_InstanceCountCache == m_GrassPositions.Count
                && m_ArgsBuffer != null
                && m_InstancePositionBuffer != null
                && m_VisibleInstanceIndexBuffer != null)
            {
                return;
            }

            if (m_InstancePositionBuffer != null) m_InstancePositionBuffer.Release();
            m_InstancePositionBuffer = new ComputeBuffer(m_GrassPositions.Count, sizeof(float) * 3);

            if (m_VisibleInstanceIndexBuffer != null) m_VisibleInstanceIndexBuffer.Release();
            m_VisibleInstanceIndexBuffer = new ComputeBuffer(m_GrassPositions.Count, sizeof(int), ComputeBufferType.Append);

            m_MinX = float.MaxValue;
            m_MinZ = float.MaxValue;
            m_MaxX = float.MinValue;
            m_MaxZ = float.MinValue;
            for (int i = 0; i < m_GrassPositions.Count; i++)
            {
                Vector3 target = m_GrassPositions[i];
                m_MinX = Mathf.Min(m_MinX, target.x);
                m_MinZ = Mathf.Min(m_MinZ, target.z);
                m_MaxX = Mathf.Max(m_MaxX, target.x);
                m_MaxZ = Mathf.Max(m_MaxZ, target.z);
            }

            m_CellCountX = Mathf.CeilToInt((m_MaxX - m_MinX) / m_CellSizeX);
            m_CellCountZ = Mathf.CeilToInt((m_MaxZ - m_MinZ) / m_CellSizeZ);

            m_CellPositionList = new List<Vector3>[m_CellCountX * m_CellCountZ];
            for (int i = 0; i < m_CellPositionList.Length; i++)
            {
                m_CellPositionList[i] = new List<Vector3>();
            }

            for (int i = 0; i < m_GrassPositions.Count; i++)
            {
                Vector3 pos = m_GrassPositions[i];

                int xID = Mathf.Min(m_CellCountX - 1, Mathf.FloorToInt(Mathf.InverseLerp(m_MinX, m_MaxX, pos.x) * m_CellCountX));
                int zID = Mathf.Min(m_CellCountZ - 1, Mathf.FloorToInt(Mathf.InverseLerp(m_MinZ, m_MaxZ, pos.z) * m_CellCountZ));
                m_CellPositionList[xID + zID * m_CellCountX].Add(pos);
            }

            int offset = 0;
            Vector3[] allGrassPosSortedByCell = new Vector3[m_GrassPositions.Count];
            for (int i = 0; i < m_CellPositionList.Length; i++)
            {
                for (int j = 0; j < m_CellPositionList[i].Count; j++)
                {
                    allGrassPosSortedByCell[offset] = m_CellPositionList[i][j];
                    offset++;
                }
            }

            m_InstancePositionBuffer.SetData(allGrassPosSortedByCell);
            m_GrassMaterial.SetBuffer("_InstancePositionBuffer", m_InstancePositionBuffer);
            m_GrassMaterial.SetBuffer("_VisibleInstanceIndexBuffer", m_VisibleInstanceIndexBuffer);

            if (m_ArgsBuffer != null) m_ArgsBuffer.Release();
            uint[] args = new uint[5] { 0, 0, 0, 0, 0 };
            m_ArgsBuffer = new ComputeBuffer(1, args.Length * sizeof(uint), ComputeBufferType.IndirectArguments);

            args[0] = (uint)GetGrassMeshCache().GetIndexCount(0);
            args[1] = (uint)m_GrassPositions.Count;
            args[2] = (uint)GetGrassMeshCache().GetIndexStart(0);
            args[3] = (uint)GetGrassMeshCache().GetBaseVertex(0);
            args[4] = 0;
            m_ArgsBuffer.SetData(args);

            m_InstanceCountCache = m_GrassPositions.Count;

            m_CullingComputeShader.SetBuffer(0, "_InstancePositionBuffer", m_InstancePositionBuffer);
            m_CullingComputeShader.SetBuffer(0, "_VisibleInstanceIndexBuffer", m_VisibleInstanceIndexBuffer);
        }
    }
}
