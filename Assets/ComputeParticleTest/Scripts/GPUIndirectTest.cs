// using System;
using UnityEngine;
using UnityEngine.Rendering;

// using System.Collections;

[ExecuteAlways]
public class GPUIndirectTest : MonoBehaviour
{
    public int m_InstanceCount = 1000000;
    public Mesh m_InstanceMesh;
    public Material m_InstanceMaterial;
    public int m_SubMeshIndex = 0;

    private int m_CachedInstanceCount = -1;
    private int m_CachedSubMeshIndex = -1;
    private ComputeBuffer m_PositionBuffer;
    private ComputeBuffer m_IndirectArgsBuffer;
    private uint[] m_Args = new uint[5] { 0, 0, 0, 0, 0 };

    private void OnEnable()
    {
        m_IndirectArgsBuffer = new ComputeBuffer(1, m_Args.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
        UpdateBuffers();
    }
    
    void LateUpdate()
    {
        if (m_CachedInstanceCount != m_InstanceCount || m_CachedSubMeshIndex != m_SubMeshIndex) { UpdateBuffers(); }

        if (Input.GetAxisRaw("Horizontal") != 0.0f)
        {
            m_InstanceCount = (int)Mathf.Clamp(m_InstanceCount + Input.GetAxis("Horizontal") * 4000, 1.0f, 5000000.0f);
        }
        Graphics.DrawMeshInstancedIndirect(m_InstanceMesh, m_SubMeshIndex, m_InstanceMaterial, new Bounds(Vector3.zero, Vector3.one * 1000), m_IndirectArgsBuffer);
    }

    private void OnGUI()
    {
        GUI.Label(new Rect(265, 25, 200, 30), "Instance Count: " + m_InstanceCount.ToString());
        m_InstanceCount = (int)GUI.HorizontalSlider(new Rect(25, 20, 200, 30), (float)m_InstanceCount, 1.0f, 5000000.0f);
    }

    private void OnDisable()
    {
        if (m_PositionBuffer != null)
        {
            m_PositionBuffer.Release();
        }
        m_PositionBuffer = null;
        
        if (m_IndirectArgsBuffer != null)
        {
            m_IndirectArgsBuffer.Release();
        }
        m_IndirectArgsBuffer = null;
    }

    void UpdateBuffers()
    {
        if (m_InstanceMesh != null)
        {
            m_SubMeshIndex = Mathf.Clamp(m_SubMeshIndex, 0, m_InstanceMesh.subMeshCount - 1);
        }
        if (m_PositionBuffer != null) { m_PositionBuffer.Release(); }

        m_PositionBuffer = new ComputeBuffer(m_InstanceCount, 16);

        Vector4[] positions = new Vector4[m_InstanceCount];

        for (int i = 0; i < m_InstanceCount; i++)
        {
            float angle = Random.Range(0.0f, Mathf.PI * 2.0f);
            float distance = Random.Range(20.0f, 100.0f);
            float height = Random.Range(-2.0f, 2.0f);
            float size = Random.Range(0.05f, 0.25f);
            positions[i] = new Vector4(Mathf.Sin(angle) * distance, height, Mathf.Cos(angle) * distance, size);
        }
        m_PositionBuffer.SetData(positions);
        m_InstanceMaterial.SetBuffer("PositionBuffer", m_PositionBuffer);

        if (m_InstanceMesh != null)
        {
            m_Args[0] = (uint)m_InstanceMesh.GetIndexCount(m_SubMeshIndex);
            m_Args[1] = (uint)m_InstanceCount;
            m_Args[2] = (uint)m_InstanceMesh.GetIndexStart(m_SubMeshIndex);
            m_Args[3] = (uint)m_InstanceMesh.GetBaseVertex(m_SubMeshIndex);
        }
        else
        {
            m_Args[0] = m_Args[1] = m_Args[2] = m_Args[3] = 0;
        }
        m_IndirectArgsBuffer.SetData(m_Args);

        m_CachedInstanceCount = m_InstanceCount;
        m_CachedSubMeshIndex = m_SubMeshIndex;
    }
}