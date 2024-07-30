using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace ParticleSimTest
{
    [ExecuteAlways]
    public class ParticleSim : MonoBehaviour
    {
        public Mesh m_ParticleMesh;
        public Material m_Material;
        public ComputeShader m_ComputeShader;
        public int m_NumParticles = 32 * 32 * 32;
    
        private ComputeBuffer m_OffsetBuffer;
        private ComputeBuffer m_ParticleBuffer;
        private ComputeBuffer m_ConstantBuffer;
        private ComputeBuffer m_ColorBuffer;
        private ComputeBuffer m_IndirectArgsBuffer;
        private uint[] m_Args = new uint[5] { 0, 0, 0, 0, 0 };
        private int m_Kernel;

        struct Particle
        {
            public Vector4 Position;
            public Vector4 Color;
        }
        
        private void OnEnable()
        {
            m_IndirectArgsBuffer = new ComputeBuffer(1, m_Args.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
            ParticleSimRenderPass.OnUpdateCommandBuffer += UpdateCommandBuffer;
            CreateBuffers();
        }

        private void Update()
        {
            m_ConstantBuffer.SetData(new[] { Time.time });
            
            m_ComputeShader.SetBuffer(m_Kernel, "ConstantBufferCS", m_ConstantBuffer);
            m_ComputeShader.SetBuffer(m_Kernel, "OffsetBufferCS", m_OffsetBuffer);
            m_ComputeShader.SetBuffer(m_Kernel, "ParticleBufferCS", m_ParticleBuffer);
            // m_ComputeShader.SetBuffer(m_Kernel, "ColorBufferCS", m_ColorBuffer);
            // 通过ComputeShader来Dispatch的话，会在Camera.Render外执行
            // m_ComputeShader.Dispatch(m_Kernel, 64, 64, 1);
            
            m_Material.SetPass(0);
            m_Material.SetBuffer("ParticleBuffer", m_ParticleBuffer);
            // m_Material.SetBuffer("ColorBuffer", m_ColorBuffer);
        }

        private void OnDisable()
        {
            ParticleSimRenderPass.OnUpdateCommandBuffer -= UpdateCommandBuffer;
            ReleaseBuffers();
        }

        public void UpdateCommandBuffer(ScriptableRenderContext context, CommandBuffer cmdBuffer)
        {
            cmdBuffer.DispatchCompute(m_ComputeShader, m_Kernel, 64, 64, 1);
            cmdBuffer.DrawMeshInstancedIndirect(m_ParticleMesh, 0, m_Material, 0, m_IndirectArgsBuffer);
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
            // m_ColorBuffer = new ComputeBuffer(m_NumParticles, 12);
            m_ParticleBuffer = new ComputeBuffer(m_NumParticles, 3 * 4 * 2);

            if (m_ParticleMesh != null)
            {
                m_Args[0] = m_ParticleMesh.GetIndexCount(0);
                m_Args[1] = (uint)m_NumParticles;
                m_Args[2] = m_ParticleMesh.GetIndexStart(0);
                m_Args[3] = m_ParticleMesh.GetBaseVertex(0);
            }
            else
            {
                m_Args[0] = m_Args[1] = m_Args[2] = m_Args[3] = 0;
            }
            m_IndirectArgsBuffer.SetData(m_Args);
        }
    
        void ReleaseBuffers()
        {
            if (m_OffsetBuffer != null)
            {
                m_OffsetBuffer.Release();
            }
            m_OffsetBuffer = null;
            if (m_ConstantBuffer != null)
            {
                m_ConstantBuffer.Release();
            }
            m_ConstantBuffer = null;
            if (m_ParticleBuffer != null)
            {
                m_ParticleBuffer.Release();
            }
            m_ParticleBuffer = null;
            if (m_IndirectArgsBuffer != null)
            {
                m_IndirectArgsBuffer.Release();
            }
            m_IndirectArgsBuffer = null;
        }
    }
}

