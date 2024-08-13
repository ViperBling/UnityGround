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
    
        private ComputeBuffer m_ParticleBuffer;
        private ComputeBuffer m_ConstantBuffer;
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
            SetBuffers();
        }

        private void OnDisable()
        {
            ParticleSimRenderPass.OnUpdateCommandBuffer -= UpdateCommandBuffer;
            ReleaseBuffers();
        }

        // 这个函数通过委托调用，每帧通过Renderpass执行
        public void UpdateCommandBuffer(ScriptableRenderContext context, CommandBuffer cmdBuffer)
        {
            m_ConstantBuffer.SetData(new[] { Time.time });
            
            cmdBuffer.DispatchCompute(m_ComputeShader, m_Kernel, 64, 64, 1);
            cmdBuffer.DrawMeshInstancedIndirect(m_ParticleMesh, 0, m_Material, 0, m_IndirectArgsBuffer);
        }
    
        void CreateBuffers()
        {
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
        }

        void SetBuffers()
        {
            m_ComputeShader.SetBuffer(m_Kernel, "ConstantBufferCS", m_ConstantBuffer);
            m_ComputeShader.SetBuffer(m_Kernel, "ParticleBufferCS", m_ParticleBuffer);
            // 通过ComputeShader来Dispatch的话，会在Camera.Render外执行
            // m_ComputeShader.Dispatch(m_Kernel, 64, 64, 1);
            
            m_Material.SetPass(0);
            m_Material.SetBuffer("ParticleBuffer", m_ParticleBuffer);
            // m_Material.SetBuffer("ColorBuffer", m_ColorBuffer);
        }
    
        void ReleaseBuffers()
        {
            
            m_ConstantBuffer.Release();
            
            m_ParticleBuffer.Release();
            m_IndirectArgsBuffer.Release();
        }
    }
}

