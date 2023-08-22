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
    public Vector3 Position;
    public float RadiusSq;
    public Vector3 Force;
}

public struct MotorOmni
{
    public Vector3 Position;
    public float RadiusSq;
    public float Force;
}

public struct MotorVortex
{
    public Vector3 Position;
    public Vector3 Axis;
    public float RadiusSq;
    public float Force;
}

public struct MotorMoving
{
    public Vector3 PrePosition;
    public float MoveLength;
    public Vector3 MoveDir;
    public float RadiusSq;
    public float Force;
}

public struct MotorCylinder
{
    public Vector3 Position;
    public Vector3 Axis;
    public float Height;
    public float BottomRadiusSq;
    public float TopRadiusSq;
    public float Force;
}

public class WindMotor : MonoBehaviour
{
    #region BasicFunction
    private void Start()
    {
        _createTime = Time.fixedTime;
    }

    private void OnEnable()
    {
        if (WindManager.Instance == null) return;
        WindManager.Instance.AddWindMotor(this);
        _createTime = Time.fixedTime;
    }

    private void OnDisable()
    {
        if (WindManager.Instance == null) return;
        WindManager.Instance.RemoveWindMotor(this);
    }

    private void OnDestroy()
    {
        if (WindManager.Instance == null) return;
        WindManager.Instance.RemoveWindMotor(this);
    }
    #endregion

    #region MainFunction
    void CheckMotorDead()
    {
        float curDuration = Time.fixedTime - _createTime;
        if (curDuration > lifeTime)
        {
            if (loop)
            {
                _createTime = Time.fixedTime;
            }
            else
            {
                _createTime = 0.0f;
                WindPool.Instance.PushWindMotor(this.gameObject);
            }
        }
    }
    #endregion

    #region UpdateForceAndOtherProperties
    public void UpdateWindMotor()
    {
        switch (MotorType)
        {
            case MotorType.Directional:
                UpdateDirectionalWind();
                break;
            case MotorType.Omni:
                UpdateOmniWind();
                break;
            case MotorType.Vortex:
                UpdateVortexWind();
                break;
            case MotorType.Moving:
                UpdateMovingWind();
                break;
        }
    }

    private float GetForce(float time)
    {
        return Mathf.Clamp(forceCurve.Evaluate(time) * force, -12f, 12f);
    }

    private void UpdateDirectionalWind()
    {
        float curDuration = Time.fixedTime - _createTime;
        float timePerCall = curDuration / lifeTime;
        duration = timePerCall;
        float rad = radius * radiusCurve.Evaluate(timePerCall);
        MotorDirectional = new MotorDirectional()
        {
            Position = transform.position,
            RadiusSq = rad * rad,
            Force = transform.forward * GetForce(timePerCall)
        };
        CheckMotorDead();
    }
    
    private void UpdateOmniWind()
    {
        float curDuration = Time.fixedTime - _createTime;
        float timePerCall = curDuration / lifeTime;
        duration = timePerCall;
        float rad = radius * radiusCurve.Evaluate(timePerCall);
        MotorOmni = new MotorOmni()
        {
            Position = transform.position,
            RadiusSq = rad * rad,
            Force = GetForce(timePerCall)
        };
        CheckMotorDead();
    }
    
    private void UpdateVortexWind()
    {
        float curDuration = Time.fixedTime - _createTime;
        float timePerCall = curDuration / lifeTime;
        duration = timePerCall;
        float rad = radius * radiusCurve.Evaluate(timePerCall);
        MotorVortex = new MotorVortex()
        {
            Position = transform.position,
            Axis = Vector3.Normalize(axis),
            RadiusSq = rad * rad,
            Force = GetForce(timePerCall)
        };
        CheckMotorDead();
    }
    
    private void UpdateMovingWind()
    {
        float curDuration = Time.fixedTime - _createTime;
        float timePerCall = curDuration / lifeTime;
        duration = timePerCall;
        float rad = radius * radiusCurve.Evaluate(timePerCall);
        float moveLen = moveLength * moveLengthCurve.Evaluate(timePerCall);
        Vector3 pos = transform.position;
        Vector3 prePos = _prePosition == Vector3.zero ? pos : _prePosition;
        Vector3 moveDir = pos - prePos;
        MotorMoving = new MotorMoving()
        {
            PrePosition = prePos,
            MoveLength = moveLen,
            MoveDir = moveDir,
            RadiusSq = rad * rad,
            Force = GetForce(timePerCall)
        };
        _prePosition = pos;
        CheckMotorDead();
    }
    
    private void UpdateCylinderWind()
    {
        
    }
    #endregion

    public void TransferMotorToECSEntity()
    {
        
    }
    
    public static MotorDirectional GetEmptyMotorDirectional()
    {
        return _emptyMotorDirectional;
    }

    public static MotorOmni GetEmptyMotorOmni()
    {
        return _emptyMotorOmni;
    }
    
    public static MotorVortex GetEmptyMotorVortex()
    {
        return _emptyMotorVortex;
    }
    
    public static MotorMoving GetEmptyMotorMoving()
    {
        return _emptyMotorMoving;
    }

    public static MotorCylinder GetEmptyMotorCylinder()
    {
        return _emptyMotorCylinder;
    }
    
    public bool loop = true;
    public float lifeTime = 5.0f;
    
    [Range(0.001f, 100f)] public float radius = 1.0f;
    public AnimationCurve radiusCurve = AnimationCurve.Linear(1, 1, 1, 1);
    public Vector3 axis = Vector3.up;

    [Range(-12f, 12f)] public float force = 1.0f;
    public AnimationCurve forceCurve = AnimationCurve.Linear(1, 1, 1, 1);
    public float duration = 0.0f;
    public float moveLength;
    public AnimationCurve moveLengthCurve = AnimationCurve.Linear(1, 1, 1, 1);

    private Vector3 _prePosition = Vector3.zero;
    
    private float _createTime;

    public MotorType MotorType;
    public MotorDirectional MotorDirectional;
    public MotorOmni MotorOmni;
    public MotorVortex MotorVortex;
    public MotorMoving MotorMoving;
    public MotorCylinder MotorCylinder;
    
    private static MotorDirectional _emptyMotorDirectional = new MotorDirectional();
    private static MotorOmni _emptyMotorOmni = new MotorOmni();
    private static MotorVortex _emptyMotorVortex = new MotorVortex();
    private static MotorMoving _emptyMotorMoving = new MotorMoving();
    private static MotorCylinder _emptyMotorCylinder = new MotorCylinder();
}