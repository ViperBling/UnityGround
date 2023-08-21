using System;
using Unity.Collections;
using Unity.Entities;
using Unity.Mathematics;

[Serializable]
public struct CWindMotorLifeTime : IComponentData
{
    public float CreateTime;
    public bool Loop;
    public float LifeTime;
    public float LeftTime;
    public bool bIsUnused;
}

[Serializable]
public struct CWindMotorDirectional : IComponentData
{
    public int id;
    public float3 PosWS;
    public float Radius;
    public float RadiusSq;
    public float Velocity;
    public float3 VelocityDir;
}

[Serializable]
public struct CWindMotorOmni : IComponentData
{
    public int id;
    public float3 PosWS;
    public float Radius;
    public float RadiusSq;
    public float Velocity;
}

[Serializable]
public struct CWindMotorVortex : IComponentData
{
    public int id;
    public float3 PosWS;
    public float3 Axis;
    public float Radius;
    public float RadiusSq;
    public float Velocity;
}

[Serializable]
public struct CWindMotorMoving : IComponentData
{
    public int id;
    public float3 PrePosWS;
    public float3 PosWS;
    public float MoveLen;
    public float3 MoveDir;
    public float Radius;
    public float RadiusSq;
    public float Velocity;
}