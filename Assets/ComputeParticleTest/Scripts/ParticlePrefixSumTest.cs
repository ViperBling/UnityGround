using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace ParticleSimTest
{
    [ExecuteAlways]
    public class ParticlePrefixSum : MonoBehaviour
    {
        public Mesh m_ParticleMesh;
        public Material m_Material;
        public ComputeShader m_ComputeShader;
        public int m_NumParticles = 32 * 32 * 32;
        public int m_NumThreads = 64;
    
        private ComputeBuffer m_OffsetBuffer;
        private ComputeBuffer m_ParticleBuffer;
        private ComputeBuffer m_ConstantBuffer;
        private ComputeBuffer m_IndirectArgsBuffer;

        private ComputeBuffer m_GlobalHashCounterBuffer;
        private ComputeBuffer m_HashesBuffer;
        private ComputeBuffer m_LocalIndicesBuffer;
        private ComputeBuffer m_GroupArrayBuffer;
        
        private uint[] m_Args = new uint[5] { 0, 0, 0, 0, 0 };
        private int m_Kernel;
        private int m_ParticlePerGroup;

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
            SetBuffers();
        }

        private void Update()
        {
        }

        private void OnDisable()
        {
            ParticleSimRenderPass.OnUpdateCommandBuffer -= UpdateCommandBuffer;
            ReleaseBuffers();
        }

        public void UpdateCommandBuffer(ScriptableRenderContext context, CommandBuffer cmdBuffer)
        {
            // cmdBuffer.DispatchCompute(m_ComputeShader, m_Kernel, 64, 64, 1);
            cmdBuffer.DispatchCompute(m_ComputeShader, m_ComputeShader.FindKernel("ResetCounter"), m_ParticlePerGroup, 1, 1);
            cmdBuffer.DispatchCompute(m_ComputeShader, m_ComputeShader.FindKernel("InsertToBucket"), m_ParticlePerGroup, 1, 1);

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
            
            m_ParticlePerGroup = Mathf.CeilToInt(m_NumParticles / (float)m_NumThreads);
            m_GlobalHashCounterBuffer = new ComputeBuffer(m_NumParticles, 4);
            m_GroupArrayBuffer = new ComputeBuffer(m_ParticlePerGroup, 4);
            m_HashesBuffer = new ComputeBuffer(m_NumParticles, 4);
            m_LocalIndicesBuffer = new ComputeBuffer(m_NumParticles, 4);
        }

        void SetBuffers()
        {
            m_ConstantBuffer.SetData(new[] { Time.time });
            
            m_ComputeShader.SetBuffer(m_Kernel, "ConstantBufferCS", m_ConstantBuffer);
            m_ComputeShader.SetBuffer(m_Kernel, "OffsetBufferCS", m_OffsetBuffer);
            m_ComputeShader.SetBuffer(m_Kernel, "ParticleBufferCS", m_ParticleBuffer);
            
            m_Material.SetPass(0);
            m_Material.SetBuffer("ParticleBuffer", m_ParticleBuffer);
        }
    
        void ReleaseBuffers()
        {
            m_OffsetBuffer.Release();
            m_ConstantBuffer.Release();
            m_ParticleBuffer.Release();
            m_IndirectArgsBuffer.Release();
            
            m_HashesBuffer.Dispose();
            m_LocalIndicesBuffer.Dispose();
        }
    }
}