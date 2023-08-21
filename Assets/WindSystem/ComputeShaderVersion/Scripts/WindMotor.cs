using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public enum MotorType
{
    Directional,
    Omni,
    Vortex,
    Moving,
    Cylinder,
}

public struct MotorDirectional
{
    public Vector3 position;
    public float radiusSq;
    public Vector3 force;
}

public struct MotorOmni
{
    public Vector3 position;
    public float radiusSq;
    public float force;
}

public struct MotorVortex
{
    public Vector3 position;
    public Vector3 axis;
    public float radiusSq;
    public float force;
}

public struct MotorMoving
{
    public Vector3 prePosition;
    public float moveLen;
    public Vector3 moveDir;
    public float radiusSq;
    public float force;
}

public struct MotorCylinder
{
    public Vector3 position;
    public Vector3 axis;
    public float height;
    public float radiusBottonSq;
    public float radiusTopSq;
    public float force;
}

public class WindMotor : MonoBehaviour
{
    public void TransferMotorToECSEntity()
    {
        // if (WindManagerECS.Instance == null) return;
        // WindManagerECS.Instance.TransferMotorToECSEntity(this);
    }
}