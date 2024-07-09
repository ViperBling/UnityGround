using System;
using System.Collections;
using System.Collections.Generic;
using Unity.VisualScripting;
using UnityEngine;
using UnityEngine.UI;

public class ParticleSim : MonoBehaviour
{
    public Shader m_Shader;
    public ComputeShader m_ComputeShader;
    public const int m_NumParticles = 32 * 32 * 32;        // 64 * 64 * 4 * 4 (Group * ThreadsPerGroup)

    private ComputeBuffer m_OffsetBuffer;
    private ComputeBuffer m_PositionBuffer;
    private ComputeBuffer m_ConstantBuffer;
    private ComputeBuffer m_ColorBuffer;
    private int m_Kernel;
    private Material m_Material;

    [ExecuteInEditMode]
    void Start()
    {
        CreateBuffers();
        CreateMaterial();
        m_Kernel = m_ComputeShader.FindKernel("CSMain");
    }

    
    private void OnDisable()
    {
        ReleaseBuffers();
    }
    
    [ExecuteInEditMode]
    private void OnRenderObject()
    {
        Dispatch();

        m_Material.SetPass(0);
        m_Material.SetBuffer("PositionBuffer", m_PositionBuffer);
        m_Material.SetBuffer("ColorBuffer", m_ColorBuffer);
        Graphics.DrawProceduralNow(MeshTopology.Points, m_NumParticles);
    }

    void CreateBuffers()
    {
        // 一个float
        m_OffsetBuffer = new ComputeBuffer(m_NumParticles, 4);
        
        float[] values = new float[m_NumParticles];
        
        for (int i = 0; i < m_NumParticles; i++)
        {
            values[i] = 10 + UnityEngine.Random.value * 2 * Mathf.PI;
        }
        m_OffsetBuffer.SetData(values);

        m_ConstantBuffer = new ComputeBuffer(1, 4);
        // float3
        m_ColorBuffer = new ComputeBuffer(m_NumParticles, 12);
        m_PositionBuffer = new ComputeBuffer(m_NumParticles, 12);
    }

    void CreateMaterial()
    {
        m_Material = new Material(m_Shader);
    }

    void ReleaseBuffers()
    {
        m_ConstantBuffer.Release();
        m_OffsetBuffer.Release();
        m_PositionBuffer.Release();
        
        DestroyImmediate(m_Material);
    }

    void Dispatch()
    {
        m_ConstantBuffer.SetData(new[] { Time.time });
        
        m_ComputeShader.SetBuffer(m_Kernel, "ConstantBufferCS", m_ConstantBuffer);
        m_ComputeShader.SetBuffer(m_Kernel, "OffsetBufferCS", m_OffsetBuffer);
        m_ComputeShader.SetBuffer(m_Kernel, "PositionBufferCS", m_PositionBuffer);
        m_ComputeShader.SetBuffer(m_Kernel, "ColorBufferCS", m_ColorBuffer);
        // 确保ThreadGroup和ThreadPerGroup能够Cover住所有的Particle
        m_ComputeShader.Dispatch(m_Kernel, 64, 64, 1);
    }
}