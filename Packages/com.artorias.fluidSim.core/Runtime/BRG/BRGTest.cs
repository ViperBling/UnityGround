using System;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using Unity.Jobs;
using UnityEngine;
using UnityEngine.Rendering;

namespace Art.Fluid.BRG
{

    public class BRGTest : MonoBehaviour
    {
        public Mesh m_Mesh;
        public Material m_Material;

        private BatchRendererGroup m_BRG;

        private GraphicsBuffer m_InstanceDataBuffer;
        private BatchID m_BatchID;
        private BatchMeshID m_MeshID;
        private BatchMaterialID m_MaterialID;

        private const int k_SizeOfMatrix = sizeof(float) * 16;
        private const int k_SizeOfPackedMatrix = sizeof(float) * 12;
        private const int k_SizeOfFloat4 = sizeof(float) * 4;
        private const int k_BytesPerInstance = k_SizeOfPackedMatrix * 2 + k_SizeOfFloat4;
        private const int k_ExtraBytes = k_SizeOfMatrix * 2;
        private const int k_NumInstances = 27;

        struct PackedMatrix
        {
            public float c0x;
            public float c0y;
            public float c0z;
            public float c1x;
            public float c1y;
            public float c1z;
            public float c2x;
            public float c2y;
            public float c2z;
            public float c3x;
            public float c3y;
            public float c3z;

            public PackedMatrix(Matrix4x4 m)
            {
                c0x = m.m00;
                c0y = m.m10;
                c0z = m.m20;
                c1x = m.m01;
                c1y = m.m11;
                c1z = m.m21;
                c2x = m.m02;
                c2y = m.m12;
                c2z = m.m22;
                c3x = m.m03;
                c3y = m.m13;
                c3z = m.m23;
            }
        }

        private void Start()
        {
            m_BRG = new BatchRendererGroup(this.OnPerformCulling, IntPtr.Zero);
            m_MeshID = m_BRG.RegisterMesh(m_Mesh);
            m_MaterialID = m_BRG.RegisterMaterial(m_Material);

            AllocateInstanceDataBuffer();
            PopulateInstanceDataBuffer();
        }

        private void OnDisable() 
        {
            m_BRG.Dispose();    
        }

        public unsafe JobHandle OnPerformCulling(BatchRendererGroup rendererGroup, BatchCullingContext cullingContext, BatchCullingOutput cullingOutput, IntPtr userContext)
        {
            int alignment = UnsafeUtility.AlignOf<long>();

            var drawCommands = (BatchCullingOutputDrawCommands*)cullingOutput.drawCommands.GetUnsafePtr();

            drawCommands->drawCommands = (BatchDrawCommand*)UnsafeUtility.Malloc(UnsafeUtility.SizeOf<BatchDrawCommand>(), alignment, Allocator.TempJob);
            drawCommands->drawRanges = (BatchDrawRange*)UnsafeUtility.Malloc(UnsafeUtility.SizeOf<BatchDrawRange>(), alignment, Allocator.TempJob);
            drawCommands->visibleInstances = (int*)UnsafeUtility.Malloc(k_NumInstances * sizeof(int), alignment, Allocator.TempJob);
            drawCommands->drawCommandPickingInstanceIDs = null;

            drawCommands->drawCommandCount = 1;
            drawCommands->drawRangeCount = 1;
            drawCommands->visibleInstanceCount = k_NumInstances;

            drawCommands->instanceSortingPositions = null;
            drawCommands->instanceSortingPositionFloatCount = 0;

            drawCommands->drawCommands[0].visibleOffset = 0;
            drawCommands->drawCommands[0].visibleCount = k_NumInstances;
            drawCommands->drawCommands[0].batchID = m_BatchID;
            drawCommands->drawCommands[0].meshID = m_MeshID;
            drawCommands->drawCommands[0].materialID = m_MaterialID;
            drawCommands->drawCommands[0].submeshIndex = 0;
            drawCommands->drawCommands[0].splitVisibilityMask = 0xff;
            drawCommands->drawCommands[0].flags = 0;
            drawCommands->drawCommands[0].sortingPosition = 0;

            drawCommands->drawRanges[0].drawCommandsBegin = 0;
            drawCommands->drawRanges[0].drawCommandsCount = 1;

            drawCommands->drawRanges[0].filterSettings = new BatchFilterSettings { renderingLayerMask = 0xffffffff, };

            for (int i = 0; i < k_NumInstances; ++i)
            drawCommands->visibleInstances[i] = i;

            return new JobHandle();
        }

        private void AllocateInstanceDataBuffer()
        {
            m_InstanceDataBuffer = new GraphicsBuffer(GraphicsBuffer.Target.Raw, BufferCountForInstances(k_BytesPerInstance, k_NumInstances, k_ExtraBytes), sizeof(int));
        }

        private void PopulateInstanceDataBuffer()
        {
            var zero = new Matrix4x4[1] { Matrix4x4.zero };

            var matrices = new Matrix4x4[k_NumInstances];
            int index = 0;
            for (int z = -1; z <= 1; z++)
            {
                for (int y = -1; y <= 1; y++)
                {
                    for (int x = -1; x <= 1; x++)
                    {
                        matrices[index++] = Matrix4x4.TRS(new Vector3(x, y + 2, z), Quaternion.identity, Vector3.one * 50);
                    }
                }
            }

            var objectToWorld = new PackedMatrix[k_NumInstances];
            for (int i = 0; i < k_NumInstances; i++)
            {
                objectToWorld[i] = new PackedMatrix(matrices[i]);
            }

            var worldToObject = new PackedMatrix[k_NumInstances];
            for (int i = 0; i < k_NumInstances; i++)
            {
                worldToObject[i] = new PackedMatrix(matrices[i].inverse);
            }

            var colors = new Vector4[k_NumInstances];
            for (int i = 0; i < k_NumInstances; i++)
            {
                // Create gradient colors based on cube position
                Vector3 position = matrices[i].GetPosition();
                // Normalize position from [-1,1] to [0,1] range
                Vector3 normalizedPos = (position + Vector3.one) * 0.5f;
                // Create vibrant gradient colors
                colors[i] = new Vector4(
                    Mathf.Lerp(0.2f, 1.0f, normalizedPos.x),
                    Mathf.Lerp(0.3f, 0.9f, normalizedPos.y),
                    Mathf.Lerp(0.5f, 1.0f, normalizedPos.z),
                    1.0f);
            }

            uint byteAddressObjectToWorld = k_SizeOfPackedMatrix * 2;
            uint byteAddressWorldToObject = byteAddressObjectToWorld + k_SizeOfPackedMatrix * k_NumInstances;
            uint byteAddressColor = byteAddressWorldToObject + k_SizeOfPackedMatrix * k_NumInstances;

            m_InstanceDataBuffer.SetData(zero, 0, 0, 1);
            m_InstanceDataBuffer.SetData(objectToWorld, 0, (int)(byteAddressObjectToWorld / k_SizeOfPackedMatrix), objectToWorld.Length);
            m_InstanceDataBuffer.SetData(worldToObject, 0, (int)(byteAddressWorldToObject / k_SizeOfPackedMatrix), worldToObject.Length);
            m_InstanceDataBuffer.SetData(colors, 0, (int)(byteAddressColor / k_SizeOfFloat4), colors.Length);

            var metaData = new NativeArray<MetadataValue>(3, Allocator.Temp);
            metaData[0] = new MetadataValue { NameID = Shader.PropertyToID("unity_ObjectToWorld"), Value = 0x80000000 | byteAddressObjectToWorld };
            metaData[1] = new MetadataValue { NameID = Shader.PropertyToID("unity_WorldToObject"), Value = 0x80000000 | byteAddressWorldToObject };
            metaData[2] = new MetadataValue { NameID = Shader.PropertyToID("_BaseColor"), Value = 0x80000000 | byteAddressColor };

            m_BatchID = m_BRG.AddBatch(metaData, m_InstanceDataBuffer.bufferHandle);
        }

        int BufferCountForInstances(int bytesPerInstance, int numInstance, int extraBytes = 0)
        {
            bytesPerInstance = (bytesPerInstance + sizeof(int) - 1) / sizeof(int) * sizeof(int);
            extraBytes = (extraBytes + sizeof(int) - 1) / sizeof(int) * sizeof(int);
            int totalBytes = bytesPerInstance * numInstance + extraBytes;
            return totalBytes / sizeof(int);
        }
    }
    
}