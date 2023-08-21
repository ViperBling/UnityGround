using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Entities;
using Unity.Mathematics;
using UnityEngine;

[Serializable]
public struct CWindPosID : IComponentData
{
    public int ID;
    public int3 Pos;
}

[Serializable]
public struct CWindTempData1 : IComponentData
{
    public float3 Value;
}

[Serializable]
public struct CWindTempData2 : IComponentData
{
    public float3 Value;
}