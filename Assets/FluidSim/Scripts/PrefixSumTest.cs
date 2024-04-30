using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class PrefixSumTest : MonoBehaviour
{
    private void Start()
    {
        int[] testArray = new int[1024 * 1024];
        for (int i = 0; i < testArray.Length; i++)
        {
            testArray[i] = UnityEngine.Random.Range(0, 1024);
        }
        
        ComputeBuffer buffer = new ComputeBuffer(testArray.Length, 4);
        buffer.SetData(testArray);

        ComputeBuffer groupBuffer = new ComputeBuffer(testArray.Length / 1024, 4);
        groupBuffer.SetData(new int[testArray.Length / 1024]);

        for (int i = 0; i < 3; i++)
        {
            computeShader.SetBuffer(i, "GlobalHashCounter", buffer);
            computeShader.SetBuffer(i, "GroupArray", groupBuffer);
        }

        int[] result = new int[testArray.Length];
        int[] groupResult = new int[testArray.Length];

        double startTime;
        
        Debug.Log("Prefix sum benchmark:");

        startTime = Time.realtimeSinceStartupAsDouble;

        result[0] = testArray[0];
        for (int i = 1; i < testArray.Length; i++)
        {
            result[i] = testArray[i] + result[i - 1];
        }
        
        Debug.Log("CPU: " + Mathf.RoundToInt((float)((Time.realtimeSinceStartupAsDouble - startTime) * 1000)) + "ms.");
        
        // GPU
        startTime = Time.realtimeSinceStartupAsDouble;
        
        computeShader.Dispatch(0, 1024, 1, 1);
        computeShader.Dispatch(1, 1, 1, 1);
        computeShader.Dispatch(2, 1024, 1, 1);
        
        buffer.GetData(groupResult);
        
        Debug.Log("GPU: " + Mathf.RoundToInt((float)((Time.realtimeSinceStartupAsDouble - startTime) * 1000)) + "ms.");

        bool pass = true;
        for (int i = 0; i < testArray.Length; i++)
        {
            if (result[i] != groupResult[i])
            {
                pass = false;
                // Debug.LogError("Mismatch at index " + i + ": " + result[i] + " != " + groupResult[i]);
            }
        }
        Debug.Log("Equal: " + pass);
        
        buffer.Dispose();
        groupBuffer.Dispose();
    }

    public ComputeShader computeShader;
}
