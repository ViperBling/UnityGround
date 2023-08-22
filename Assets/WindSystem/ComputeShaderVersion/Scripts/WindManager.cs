using System;
using System.Collections;
using UnityEditor;
using System.Collections.Generic;
using System.Net.Http.Headers;
using System.Numerics;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Vector3 = UnityEngine.Vector3;

[ExecuteInEditMode]
public class WindManager : MonoBehaviour
{
    public void DoRenderingWindVolume()
    {
        UpdateTargetPosition();
        DoShiftPos(1);
        DoDiffusion(2);
        DoRenderWindVelocityData(1);
        DoAdvection(2);
        DoMergeChannel(1);
    }

    void UpdateTargetPosition()
    {
        _offsetPos = targetTransform == null ? Vector3.zero : targetTransform.position;
        _offsetPos += (targetTransform == null ? Vector3.forward : targetTransform.forward) * cameraCenterOffset.z;
        _offsetPos += (targetTransform == null ? Vector3.right : targetTransform.right) * cameraCenterOffset.x;
        _offsetPos += (targetTransform == null ? Vector3.up : targetTransform.up) * cameraCenterOffset.y;
        _offsetPos -= _halfVolume;
        
        Shader.SetGlobalFloat(_overallPowerTag, overallPower);
        Shader.SetGlobalVector(_volumePosOffsetTag, _offsetPos);
        Shader.SetGlobalVector(_globalAmbientWindTag, globalAmbientWind);
        _windNoiseOffset += windNoiseUVDir + windNoiseUVSpeed * Time.deltaTime;
        Shader.SetGlobalVector(_windNoiseOffsetTag, _windNoiseOffset);
        Shader.SetGlobalVector(_windNoiseUVScaleTag, windNoiseUVScale);
        Shader.SetGlobalVector(_windNoiseOffsetTag, windNoiseScale);
    }

    void DoShiftPos(int form)
    {
        if (shiftPosCS != null)
        {
            var formRTR = form == 1 ? _windBufferRTR1 : _windBufferRTR2;
            var formRTG = form == 1 ? _windBufferRTG1 : _windBufferRTG2;
            var formRTB = form == 1 ? _windBufferRTB1 : _windBufferRTB2;
            var toRTR = form == 1 ? _windBufferRTR2 : _windBufferRTR1;
            var toRTG = form == 1 ? _windBufferRTG2 : _windBufferRTG1;
            var toRTB = form == 1 ? _windBufferRTB2 : _windBufferRTB1;
            Vector3 cellPos = ConvertFloatPointToInt(_offsetPos);
            Vector3 shiftPos = cellPos - _lastOffsetPos;
            shiftPosCS.SetVector(_volumeSizeMinusOneTag, _volumeSizeMinusOne);
            shiftPosCS.SetInt(_shiftPosXTag, (int)(shiftPos.x));
            shiftPosCS.SetInt(_shiftPosYTag, (int)(shiftPos.y));
            shiftPosCS.SetInt(_shiftPosZTag, (int)(shiftPos.z));
            // 这里如果打包了Int发过去会导致同步不了，神秘bug，不知道为什么
            // ShiftPosCS.SetVector(m_ShiftPosId, new Vector4(shiftPos.x, shiftPos.y, shiftPos.z, 0));
            
            shiftPosCS.SetTexture(_shiftPosKernel, _windBufferInputXTag, formRTR);
            shiftPosCS.SetTexture(_shiftPosKernel, _windBufferInputYTag, formRTG);
            shiftPosCS.SetTexture(_shiftPosKernel, _windBufferInputZTag, formRTB);
            shiftPosCS.SetTexture(_shiftPosKernel, _windBufferOutputXTag, toRTR);
            shiftPosCS.SetTexture(_shiftPosKernel, _windBufferOutputYTag, toRTG);
            shiftPosCS.SetTexture(_shiftPosKernel, _windBufferOutputZTag, toRTB);
            
            shiftPosCS.Dispatch(_shiftPosKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            _lastOffsetPos = cellPos;
        }
    }

    void DoDiffusion(int form)
    {
        if (diffusionCS != null)
        {
            var formRTR = form == 1 ? _windBufferRTR1 : _windBufferRTR2;
            var formRTG = form == 1 ? _windBufferRTG1 : _windBufferRTG2;
            var formRTB = form == 1 ? _windBufferRTB1 : _windBufferRTB2;
            var toRTR = form == 1 ? _windBufferRTR2 : _windBufferRTR1;
            var toRTG = form == 1 ? _windBufferRTG2 : _windBufferRTG1;
            var toRTB = form == 1 ? _windBufferRTB2 : _windBufferRTB1;
            
            diffusionCS.SetVector(_volumeSizeMinusOneTag, _volumeSizeMinusOne);
            diffusionCS.SetFloat(_diffusionForceTag, diffusionForce);
            // Do Channel R
            diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, formRTR);
            diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, toRTR);
            diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            // Do Channel G
            diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, formRTG);
            diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, toRTG);
            diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            // Do Channel B
            diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, formRTB);
            diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, toRTB);
            diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);

            if (moreDiffusion)
            {
                // Do Channel R
                diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, toRTR);
                diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, formRTR);
                diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
                // Do Channel G
                diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, toRTG);
                diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, formRTG);
                diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
                // Do Channel B
                diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, toRTB);
                diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, formRTB);
                diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
                
                // Do Channel R
                diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, formRTR);
                diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, toRTR);
                diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
                // Do Channel G
                diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, formRTG);
                diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, toRTG);
                diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
                // Do Channel B
                diffusionCS.SetTexture(_diffusionKernel, _windBufferInputTag, formRTB);
                diffusionCS.SetTexture(_diffusionKernel, _windBufferOutputTag, toRTB);
                diffusionCS.Dispatch(_diffusionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            }
        }
    }

    void DoRenderWindVelocityData(int form)
    {
        if (motorsSpeedCS != null && bufferExchangeCS != null)
        {
            _directionalMotorsList.Clear();
            _omniMotorsList.Clear();
            _vortexMotorsList.Clear();
            _movingMotorsList.Clear();

            int directionalMotorCount = 0;
            int omniMotorCount = 0;
            int vortexMotorCount = 0;
            int movingMotorCount = 0;
            foreach (WindMotor motor in _motorsList)
            {
                motor.UpdateWindMotor();
                switch (motor.MotorType)
                {
                    case MotorType.Directional:
                        if (directionalMotorCount < MAXMOTOR)
                        {
                            _directionalMotorsList.Add(motor.MotorDirectional);
                            directionalMotorCount++;
                        }
                        break;
                    case MotorType.Omni:
                        if (omniMotorCount < MAXMOTOR)
                        {
                            _omniMotorsList.Add(motor.MotorOmni);
                            omniMotorCount++;
                        }
                        break;
                    case MotorType.Vortex:
                        if (vortexMotorCount < MAXMOTOR)
                        {
                            _vortexMotorsList.Add(motor.MotorVortex);
                            vortexMotorCount++;
                        }
                        break;
                    case MotorType.Moving:
                        if (movingMotorCount < MAXMOTOR)
                        {
                            _movingMotorsList.Add(motor.MotorMoving);
                            movingMotorCount++;
                        }
                        break;
                }
            }
            // 往列表数据中插入空的发动机数据
            if (directionalMotorCount < MAXMOTOR)
            {
                MotorDirectional motor = WindMotor.GetEmptyMotorDirectional();
                for (int i = directionalMotorCount; i < MAXMOTOR; i++)
                {
                    _directionalMotorsList.Add(motor);
                }
            }
            if (omniMotorCount < MAXMOTOR)
            {
                MotorOmni motor = WindMotor.GetEmptyMotorOmni();
                for (int i = omniMotorCount; i < MAXMOTOR; i++)
                {
                    _omniMotorsList.Add(motor);
                }
            }
            if (vortexMotorCount < MAXMOTOR)
            {
                MotorVortex motor = WindMotor.GetEmptyMotorVortex();
                for (int i = vortexMotorCount; i < MAXMOTOR; i++)
                {
                    _vortexMotorsList.Add(motor);
                }
            }
            if (movingMotorCount < MAXMOTOR)
            {
                MotorMoving motor = WindMotor.GetEmptyMotorMoving();
                for (int i = movingMotorCount; i < MAXMOTOR; i++)
                {
                    _movingMotorsList.Add(motor);
                }
            }
            _directionalMotorComputeBuffer.SetData(_directionalMotorsList);
            motorsSpeedCS.SetBuffer(_motorSpeedKernel, _directionalMotorBufferTag, _directionalMotorComputeBuffer);
            _omniMotorComputeBuffer.SetData(_omniMotorsList);
            motorsSpeedCS.SetBuffer(_motorSpeedKernel, _omniMotorBufferTag, _omniMotorComputeBuffer);
            _vortexMotorComputeBuffer.SetData(_vortexMotorsList);
            motorsSpeedCS.SetBuffer(_motorSpeedKernel, _vortexMotorBufferTag, _vortexMotorComputeBuffer);
            _movingMotorComputeBuffer.SetData(_movingMotorsList);
            motorsSpeedCS.SetBuffer(_motorSpeedKernel, _movingMotorBufferTag, _movingMotorComputeBuffer);

            motorsSpeedCS.SetFloat(_directionalMotorBufferCountTag, directionalMotorCount);
            motorsSpeedCS.SetFloat(_omniMotorBufferCountTag, omniMotorCount);
            motorsSpeedCS.SetFloat(_vortexMotorBufferCountTag, vortexMotorCount);
            motorsSpeedCS.SetFloat(_movingMotorBufferCountTag, movingMotorCount);
            motorsSpeedCS.SetVector(_volumePosOffsetTag, _offsetPos);
            
            var formRTR = form == 1 ? _windBufferRTR1 : _windBufferRTR2;
            var formRTG = form == 1 ? _windBufferRTG1 : _windBufferRTG2;
            var formRTB = form == 1 ? _windBufferRTB1 : _windBufferRTB2;
            var toRTR = form == 1 ? _windBufferRTR2 : _windBufferRTR1;
            var toRTG = form == 1 ? _windBufferRTG2 : _windBufferRTG1;
            var toRTB = form == 1 ? _windBufferRTB2 : _windBufferRTB1;
            
            motorsSpeedCS.SetTexture(_motorSpeedKernel, _windBufferInputXTag, formRTR);
            motorsSpeedCS.SetTexture(_motorSpeedKernel, _windBufferInputYTag, formRTG);
            motorsSpeedCS.SetTexture(_motorSpeedKernel, _windBufferInputZTag, formRTB);
            motorsSpeedCS.SetTexture(_motorSpeedKernel, _windBufferOutputXTag, toRTR);
            motorsSpeedCS.SetTexture(_motorSpeedKernel, _windBufferOutputYTag, toRTG);
            motorsSpeedCS.SetTexture(_motorSpeedKernel, _windBufferOutputZTag, toRTB);
            motorsSpeedCS.Dispatch(_motorSpeedKernel, _windBrandX / 8, _windBrandY / 8, _windBrandZ);
            // 清除旧Buffer
            bufferExchangeCS.SetTexture(_clearBufferKernel, _windBufferOutputXTag, formRTR);
            bufferExchangeCS.SetTexture(_clearBufferKernel, _windBufferOutputYTag, formRTG);
            bufferExchangeCS.SetTexture(_clearBufferKernel, _windBufferOutputZTag, formRTB);
            bufferExchangeCS.Dispatch(_clearBufferKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
        }
    }

    void DoAdvection(int form)
    {
        if (advectionCS != null && bufferExchangeCS != null)
        {
            var formRTR = form == 1 ? _windBufferRTR1 : _windBufferRTR2;
            var formRTG = form == 1 ? _windBufferRTG1 : _windBufferRTG2;
            var formRTB = form == 1 ? _windBufferRTB1 : _windBufferRTB2;
            var toRTR = form == 1 ? _windBufferRTR2 : _windBufferRTR1;
            var toRTG = form == 1 ? _windBufferRTG2 : _windBufferRTG1;
            var toRTB = form == 1 ? _windBufferRTB2 : _windBufferRTB1;
            advectionCS.SetVector(_volumeSizeMinusOneTag, _volumeSizeMinusOne);
            advectionCS.SetFloat(_advectionForceTag, advectionForce);
            advectionCS.SetTexture(_advectionKernel, _windBufferInputXTag, formRTR);
            advectionCS.SetTexture(_advectionKernel, _windBufferInputYTag, formRTG);
            advectionCS.SetTexture(_advectionKernel, _windBufferInputZTag, formRTB);
            // Do ChannelR
            advectionCS.SetTexture(_advectionKernel, _windBufferTargetTag, formRTR);
            advectionCS.SetTexture(_advectionKernel, _windBufferOutputTag, toRTR);
            advectionCS.Dispatch(_advectionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            // Do ChannelG
            advectionCS.SetTexture(_advectionKernel, _windBufferTargetTag, formRTG);
            advectionCS.SetTexture(_advectionKernel, _windBufferOutputTag, toRTG);
            advectionCS.Dispatch(_advectionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            // Do ChannelB
            advectionCS.SetTexture(_advectionKernel, _windBufferTargetTag, formRTB);
            advectionCS.SetTexture(_advectionKernel, _windBufferOutputTag, toRTB);
            advectionCS.Dispatch(_advectionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            // Exchange Buffer
            bufferExchangeCS.SetTexture(_bufferExchangeKernel, _windBufferInputXTag, toRTR);
            bufferExchangeCS.SetTexture(_bufferExchangeKernel, _windBufferInputYTag, toRTG);
            bufferExchangeCS.SetTexture(_bufferExchangeKernel, _windBufferInputZTag, toRTB);
            bufferExchangeCS.SetTexture(_bufferExchangeKernel, _windBufferOutputXTag, formRTR);
            bufferExchangeCS.SetTexture(_bufferExchangeKernel, _windBufferOutputYTag, formRTG);
            bufferExchangeCS.SetTexture(_bufferExchangeKernel, _windBufferOutputZTag, formRTB);
            bufferExchangeCS.Dispatch(_bufferExchangeKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            // Do reverse Advection
            advectionCS.SetVector(_volumeSizeMinusOneTag, _volumeSizeMinusOne);
            advectionCS.SetFloat(_advectionForceTag, advectionForce);
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferInputXTag, formRTR);
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferInputYTag, formRTG);
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferInputZTag, formRTB);
            // Do ChannelR
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferTargetTag, formRTR);
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferOutputTag, toRTR);
            advectionCS.Dispatch(_reverseAdvectionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            // Do ChannelG
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferTargetTag, formRTG);
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferOutputTag, toRTG);
            advectionCS.Dispatch(_reverseAdvectionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            // Do ChannelB
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferTargetTag, formRTB);
            advectionCS.SetTexture(_reverseAdvectionKernel, _windBufferOutputTag, toRTB);
            advectionCS.Dispatch(_reverseAdvectionKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
        }
    }
    
    
    public void AddWindMotor(WindMotor motor)
    {
        _motorsList.Add(motor);
    }

    public void RemoveWindMotor(WindMotor motor)
    {
        _motorsList.Remove(motor);
    }

    void ClearRenderTexture(ref RenderTexture rt)
    {
        if (rt != null)
        {
            RenderTexture.ReleaseTemporary(rt);
            rt = null;
        }
    }

    public Vector3 GetWindForceByPosAndDeltaTime(Vector3 pos)
    {
        if (!this.gameObject.activeSelf) return Vector3.zero;
        // 计算采样范围，超过范围的不采样
        float posX = pos.x - _offsetPos.x;
        float posY = pos.y - _offsetPos.y;
        float posZ = pos.z - _offsetPos.z;
        if(posX < 0 || posX > _windBrandX || posY < 0 || posY > _windBrandY || posZ < 0 || posZ > _windBrandZ) return Vector3.zero;
        
        // 模拟三线性采样
        int xb = Mathf.FloorToInt(posX);
        int xu = Mathf.CeilToInt(posX);
        int yb = Mathf.FloorToInt(posY);
        int yu = Mathf.CeilToInt(posY);
        int zb = Mathf.FloorToInt(posZ);
        int zu = Mathf.CeilToInt(posZ);

        float lerpX = posX - xb;
        float lerpY = posY - yb;
        float lerpZ = posZ - zb;

        Vector3 data0 = _windDataForCPU[xb + yb * _windBrandX + zb * _windBrandX * _windBrandY];
        Vector3 data1 = _windDataForCPU[xu + yb * _windBrandX + zb * _windBrandX * _windBrandY];
        Vector3 data2 = _windDataForCPU[xb + yu * _windBrandX + zb * _windBrandX * _windBrandY];
        Vector3 data3 = _windDataForCPU[xu + yu * _windBrandX + zb * _windBrandX * _windBrandY];
        Vector3 data4 = _windDataForCPU[xb + yb * _windBrandX + zu * _windBrandX * _windBrandY];
        Vector3 data5 = _windDataForCPU[xu + yb * _windBrandX + zu * _windBrandX * _windBrandY];
        Vector3 data6 = _windDataForCPU[xb + yu * _windBrandX + zu * _windBrandX * _windBrandY];
        Vector3 data7 = _windDataForCPU[xu + yu * _windBrandX + zu * _windBrandX * _windBrandY];

        Vector3 lerpX0 = Vector3.Lerp(data0, data1, lerpX);
        Vector3 lerpX1 = Vector3.Lerp(data4, data5, lerpX);
        Vector3 lerpX2 = Vector3.Lerp(data2, data3, lerpX);
        Vector3 lerpX3 = Vector3.Lerp(data6, data7, lerpX);

        Vector3 lerpZ0 = Vector3.Lerp(lerpX0, lerpX1, lerpZ);
        Vector3 lerpZ1 = Vector3.Lerp(lerpX2, lerpX3, lerpZ);

        Vector3 lerpY0 = Vector3.Lerp(lerpZ0, lerpZ1, lerpY);

        Vector3 windData = lerpY0;

        // CPU段使用的风力数据是否要叠加全局风力
        if (cpuWindUseGlobalWind)
        {
            Vector3 ambientWindUV = pos + _windNoiseOffset;
            ambientWindUV.x *= _windNoiseRCPTexSize.x * windNoiseUVScale.x;
            ambientWindUV.y *= _windNoiseRCPTexSize.y * windNoiseUVScale.y;
            ambientWindUV.z *= _windNoiseRCPTexSize.z * windNoiseUVScale.z;
            Color noiseData = windNoise.GetPixelBilinear(ambientWindUV.x, ambientWindUV.y, ambientWindUV.z, 0);
            Vector3 wNoise = new Vector3(noiseData.r, noiseData.g, noiseData.b) * 2.0f;
            wNoise.x -= 1f;
            wNoise.y -= 1f;
            wNoise.z -= 1f;
            windData += globalAmbientWind + new Vector3(wNoise.x * windNoiseScale.x, wNoise.y * windNoiseScale.y, wNoise.z * windNoiseScale.z);
        }
        
        Vector3 force = windData * overallPower;
        return force;
    }

    Vector3 ConvertFloatPointToInt(Vector3 v)
    {
        Vector3 o;
        o.x = v.x < 0 ? Mathf.Ceil(v.x) : Mathf.Floor(v.x);
        o.y = v.y < 0 ? Mathf.Ceil(v.y) : Mathf.Floor(v.y);
        o.z = v.z < 0 ? Mathf.Ceil(v.z) : Mathf.Floor(v.z);
        return o;
    }

    public void OnDestroy()
    {
        ClearRenderTexture(ref _windBufferRTR1);
        ClearRenderTexture(ref _windBufferRTR2);
        ClearRenderTexture(ref _windBufferRTG1);
        ClearRenderTexture(ref _windBufferRTG2);
        ClearRenderTexture(ref _windBufferRTB1);
        ClearRenderTexture(ref _windBufferRTB2);
        if (_directionalMotorComputeBuffer != null)
        {
            _directionalMotorComputeBuffer.Release();
            _directionalMotorComputeBuffer = null;
        }
        if (_omniMotorComputeBuffer != null)
        {
            _omniMotorComputeBuffer.Release();
            _omniMotorComputeBuffer = null;
        }
        if (_vortexMotorComputeBuffer != null)
        {
            _vortexMotorComputeBuffer.Release();
            _vortexMotorComputeBuffer = null;
        }
        if (_movingMotorComputeBuffer != null)
        {
            _movingMotorComputeBuffer.Release();
            _movingMotorComputeBuffer = null;
        }
    }
    
    private void Awake()
    {
        Application.targetFrameRate = 60;
        _instance = this;
        _volumeSize = new Vector3(_windBrandX, _windBrandY, _windBrandZ);
        _volumeSizeMinusOne = new Vector3(_windBrandX - 1, _windBrandY - 1, _windBrandZ - 1);
        _halfVolume = new Vector3(_windBrandX / 2.0f, _windBrandY / 2.0f, _windBrandZ / 2.0f);

        _offsetPos = targetTransform == null ? Vector3.zero : targetTransform.position;
        _offsetPos += (targetTransform == null ? Vector3.forward : targetTransform.forward) * cameraCenterOffset.z;
        _offsetPos += (targetTransform == null ? Vector3.right : targetTransform.right) * cameraCenterOffset.x;
        _offsetPos += (targetTransform == null ? Vector3.up : targetTransform.up) * cameraCenterOffset.y;
        _offsetPos -= _halfVolume;

        _lastOffsetPos = ConvertFloatPointToInt(_offsetPos);

        _shiftPosKernel = shiftPosCS != null ? shiftPosCS.FindKernel("CSMain") : -1;
        _diffusionKernel = diffusionCS != null ? diffusionCS.FindKernel("CSMain") : -1;
        _motorSpeedKernel = motorsSpeedCS != null ? motorsSpeedCS.FindKernel("WindVolumeRenderMotorCS") : -1;
        _advectionKernel = advectionCS != null ? advectionCS.FindKernel("CSMain") : -1;
        _reverseAdvectionKernel = advectionCS != null ? advectionCS.FindKernel("CSMain1") : -1;
        _bufferExchangeKernel = bufferExchangeCS != null ? bufferExchangeCS.FindKernel("CSMain") : -1;
        _clearBufferKernel = bufferExchangeCS != null ? bufferExchangeCS.FindKernel("CSMain1") : -1;
        _mergeChannelKernel = mergeChannelCS != null ? mergeChannelCS.FindKernel("CSMain") : -1;

        _windChannelDesc.enableRandomWrite = true;
        _windChannelDesc.width = _windBrandX;
        _windChannelDesc.height = _windBrandY;
        _windChannelDesc.volumeDepth = _windBrandZ;
        _windChannelDesc.dimension = TextureDimension.Tex3D;
        _windChannelDesc.colorFormat = RenderTextureFormat.RInt;
        _windChannelDesc.graphicsFormat = GraphicsFormat.R32_SInt;
        _windChannelDesc.msaaSamples = 1;
        
        CreateRenderTexture(ref _windBufferRTR1, ref _windChannelDesc, "WindBufferChannelR1");
        CreateRenderTexture(ref _windBufferRTR2, ref _windChannelDesc, "WindBufferChannelR2");
        CreateRenderTexture(ref _windBufferRTG1, ref _windChannelDesc, "WindBufferChannelG1");
        CreateRenderTexture(ref _windBufferRTG2, ref _windChannelDesc, "WindBufferChannelG2");
        CreateRenderTexture(ref _windBufferRTB1, ref _windChannelDesc, "WindBufferChannelB1");
        CreateRenderTexture(ref _windBufferRTB2, ref _windChannelDesc, "WindBufferChannelB2");
        
        _windVelocityDataDesc.enableRandomWrite = true;
        _windVelocityDataDesc.width = _windBrandX;
        _windVelocityDataDesc.height = _windBrandY;
        _windVelocityDataDesc.volumeDepth = _windBrandZ;
        _windVelocityDataDesc.dimension = TextureDimension.Tex3D;
        _windVelocityDataDesc.colorFormat = RenderTextureFormat.ARGBFloat;
        _windVelocityDataDesc.graphicsFormat = GraphicsFormat.R32G32B32A32_SFloat;
        _windVelocityDataDesc.msaaSamples = 1;
        CreateRenderTexture(ref _windVelocityRT, ref _windVelocityDataDesc, "WindVelocityData");
        
        Shader.SetGlobalVector(_volumeSizeTag, _volumeSize);
        _windNoiseRCPTexSize =
            new Vector3(1.0f / (2 * _windBrandX), 1.0f / (2 * _windBrandY), 1.0f / (2 * _windBrandZ));
        Shader.SetGlobalVector(_windNoiseRCPTexSizeTag, _windNoiseRCPTexSize);
        Shader.SetGlobalTexture(_windBufferChannelR1Tag, _windBufferRTR1);
        Shader.SetGlobalTexture(_windBufferChannelR2Tag, _windBufferRTR2);
        Shader.SetGlobalTexture(_windBufferChannelG1Tag, _windBufferRTG1);
        Shader.SetGlobalTexture(_windBufferChannelG2Tag, _windBufferRTG2);
        Shader.SetGlobalTexture(_windBufferChannelB1Tag, _windBufferRTB1);
        Shader.SetGlobalTexture(_windBufferChannelB2Tag, _windBufferRTB2);
        
        Shader.SetGlobalTexture(_windVelocityDataTag, _windVelocityRT);
        Shader.SetGlobalTexture(_windNoiseTag, windNoise);

        int totalNum = _windBrandX * _windBrandY * _windBrandZ;
        _windDataForCPU = new Vector3[totalNum];
        for (int i = 0; i < totalNum; i++)
        {
            _windDataForCPU[i] = Vector3.zero;
        }

        _directionalMotorComputeBuffer = new ComputeBuffer(MAXMOTOR, 28);
        _omniMotorComputeBuffer = new ComputeBuffer(MAXMOTOR, 20);
        _vortexMotorComputeBuffer = new ComputeBuffer(MAXMOTOR, 32);
        _movingMotorComputeBuffer = new ComputeBuffer(MAXMOTOR, 36);
        _windDataForCPUComputeBuffer = new ComputeBuffer(totalNum, 12);
    }
    
    private void CreateRenderTexture(ref RenderTexture rt, ref RenderTextureDescriptor rtDesc, string name)
    {
        if (rt == null)
        {
            rt = RenderTexture.GetTemporary(rtDesc);
            rt.filterMode = FilterMode.Bilinear;
            rt.name = name;
        }
    }

    private void DoMergeChannel(int form)
    {
        if (mergeChannelCS != null)
        {
            var formRTR = form == 1 ? _windBufferRTR1 : _windBufferRTR2;
            var formRTG = form == 1 ? _windBufferRTG1 : _windBufferRTG2;
            var formRTB = form == 1 ? _windBufferRTB1 : _windBufferRTB2;

            mergeChannelCS.SetInt(_volumeSizeXTag, _windBrandX);
            mergeChannelCS.SetInt(_volumeSizeYTag, _windBrandY);
            mergeChannelCS.SetTexture(_mergeChannelKernel, _windBufferInputXTag, formRTR);
            mergeChannelCS.SetTexture(_mergeChannelKernel, _windBufferInputYTag, formRTG);
            mergeChannelCS.SetTexture(_mergeChannelKernel, _windBufferInputZTag, formRTB);
            mergeChannelCS.SetTexture(_mergeChannelKernel, _windBufferOutputTag, _windVelocityRT);
            mergeChannelCS.SetBuffer(_mergeChannelKernel, _windDataForCPUBufferTag, _windDataForCPUComputeBuffer);
            _windDataForCPUComputeBuffer.SetData(_windDataForCPU);
            mergeChannelCS.Dispatch(_mergeChannelKernel, _windBrandX / 4, _windBrandY / 4, _windBrandZ / 4);
            _windDataForCPUComputeBuffer.GetData(_windDataForCPU);
        }
    }

    private static WindManager _instance;

    public static WindManager Instance
    {
        get { return _instance; }
    }

    public Transform targetTransform;
    public Vector3 cameraCenterOffset;
    public float diffusionForce;
    public float advectionForce;
    public float overallPower = 0.1f;
    public bool moreDiffusion = false;
    public bool cpuWindUseGlobalWind = true;

    public Texture3D windNoise;
    public Vector3 globalAmbientWind = Vector3.zero;
    public Vector3 windNoiseUVDir = Vector3.zero;
    public Vector3 windNoiseUVSpeed = Vector3.zero;
    public Vector3 windNoiseUVScale = Vector3.zero;
    public Vector3 windNoiseScale = Vector3.zero;

    public ComputeShader shiftPosCS;
    public ComputeShader diffusionCS;
    public ComputeShader motorsSpeedCS;
    public ComputeShader advectionCS;
    public ComputeShader bufferExchangeCS;
    public ComputeShader mergeChannelCS;

    private static int MAXMOTOR = 10;

    private static int _windBrandX = 32;
    private static int _windBrandY = 16;
    private static int _windBrandZ = 32;
    
    // Shader ID
    private static int _shiftPosTag = Shader.PropertyToID("ShiftPos");
    private static int _shiftPosXTag = Shader.PropertyToID("ShiftPosX");
    private static int _shiftPosYTag = Shader.PropertyToID("ShiftPosY");
    private static int _shiftPosZTag = Shader.PropertyToID("ShiftPosZ");
    
    private static int _volumePosOffsetTag = Shader.PropertyToID("VolumePosOffset");
    private static int _volumeSizeTag = Shader.PropertyToID("VolumeSize");
    private static int _volumeSizeXTag = Shader.PropertyToID("VolumeSizeX");
    private static int _volumeSizeYTag = Shader.PropertyToID("VolumeSizeY");
    private static int _volumeSizeZTag = Shader.PropertyToID("VolumeSizeZ");
    private static int _volumeSizeMinusOneTag = Shader.PropertyToID("VolumeSizeMinusOne");
    
    private static int _diffusionForceTag = Shader.PropertyToID("DiffusionForce");
    private static int _advectionForceTag = Shader.PropertyToID("AdvectionForce");
    private static int _windNoiseTag = Shader.PropertyToID("WindNoise");
    private static int _overallPowerTag = Shader.PropertyToID("OverallPower");
    private static int _globalAmbientWindTag = Shader.PropertyToID("GlobalAmbientWind");
    private static int _windNoiseRCPTexSizeTag = Shader.PropertyToID("WindNoiseRCPTexSize");
    private static int _windNoiseOffsetTag = Shader.PropertyToID("WindNoiseOffset");
    private static int _windNoiseUVScaleTag = Shader.PropertyToID("WindNoiseUVScale");
    private static int _windNoiseScaleTag = Shader.PropertyToID("WindNoiseScale");
    
    private static int _directionalMotorBufferTag = Shader.PropertyToID("DirectionalMotorBuffer");
    private static int _omniMotorBufferTag = Shader.PropertyToID("OmniMotorBuffer");
    private static int _vortexMotorBufferTag = Shader.PropertyToID("VortexMotorBuffer");
    private static int _movingMotorBufferTag = Shader.PropertyToID("MovingMotorBuffer");
    private static int _directionalMotorBufferCountTag = Shader.PropertyToID("DirectionalMotorBufferCount");
    private static int _omniMotorBufferCountTag = Shader.PropertyToID("OmniMotorBufferCount");
    private static int _vortexMotorBufferCountTag = Shader.PropertyToID("VortexMotorBufferCount");
    private static int _movingMotorBufferCountTag = Shader.PropertyToID("MovingMotorBufferCount");
    private static int _windBufferInputTag = Shader.PropertyToID("WindBufferInput");
    private static int _windBufferInputXTag = Shader.PropertyToID("WindBufferInputX");
    private static int _windBufferInputYTag = Shader.PropertyToID("WindBufferInputY");
    private static int _windBufferInputZTag = Shader.PropertyToID("WindBufferInputZ");
    private static int _windBufferOutputTag = Shader.PropertyToID("WindBufferOutput");
    private static int _windBufferOutputXTag = Shader.PropertyToID("WindBufferOutputX");
    private static int _windBufferOutputYTag = Shader.PropertyToID("WindBufferOutputY");
    private static int _windBufferOutputZTag = Shader.PropertyToID("WindBufferOutputZ");
    private static int _windBufferTargetTag = Shader.PropertyToID("WindBufferTarget");
    
    private static int _windBufferChannelR1Tag = Shader.PropertyToID("WindBufferChannelR1");
    private static int _windBufferChannelR2Tag = Shader.PropertyToID("WindBufferChannelR2");
    private static int _windBufferChannelG1Tag = Shader.PropertyToID("WindBufferChannelG1");
    private static int _windBufferChannelG2Tag = Shader.PropertyToID("WindBufferChannelG2");
    private static int _windBufferChannelB1Tag = Shader.PropertyToID("WindBufferChannelB1");
    private static int _windBufferChannelB2Tag = Shader.PropertyToID("WindBufferChannelB2");
    
    private static int _windVelocityDataTag = Shader.PropertyToID("WindVelocityData");
    private static int _windDataForCPUBufferTag = Shader.PropertyToID("WindDataForCPUBuffer");

    private Vector3 _volumeSize;
    private Vector3 _volumeSizeMinusOne;
    private Vector3 _halfVolume;
    private Vector3 _offsetPos;
    private Vector3 _lastOffsetPos;
    private Vector3 _windNoiseOffset = Vector3.zero;
    private Vector3 _windNoiseRCPTexSize;

    private int _shiftPosKernel;
    private int _diffusionKernel;
    private int _motorSpeedKernel;
    private int _advectionKernel;
    private int _bufferExchangeKernel;
    private int _clearBufferKernel;
    private int _reverseAdvectionKernel;
    private int _mergeChannelKernel;

    private RenderTextureDescriptor _windChannelDesc = new RenderTextureDescriptor();
    private RenderTexture _windBufferRTR1;
    private RenderTexture _windBufferRTR2;
    private RenderTexture _windBufferRTG1;
    private RenderTexture _windBufferRTG2;
    private RenderTexture _windBufferRTB1;
    private RenderTexture _windBufferRTB2;

    private RenderTextureDescriptor _windVelocityDataDesc = new RenderTextureDescriptor();
    private RenderTexture _windVelocityRT;

    private ComputeBuffer _directionalMotorComputeBuffer;
    private ComputeBuffer _omniMotorComputeBuffer;
    private ComputeBuffer _vortexMotorComputeBuffer;
    private ComputeBuffer _movingMotorComputeBuffer;
    private ComputeBuffer _windDataForCPUComputeBuffer;

    private List<WindMotor> _motorsList = new List<WindMotor>();
    private List<MotorDirectional> _directionalMotorsList = new List<MotorDirectional>();
    private List<MotorOmni> _omniMotorsList = new List<MotorOmni>();
    private List<MotorVortex> _vortexMotorsList = new List<MotorVortex>();
    private List<MotorMoving> _movingMotorsList = new List<MotorMoving>();

    private Vector3[] _windDataForCPU;

}
