using System;
using System.Collections;
using UnityEditor;
using System.Collections.Generic;
using System.Net.Http.Headers;
using System.Numerics;
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
        
    }

    void UpdateTargetPosition()
    {
        
    }

    void DoShiftPos(int form)
    {
        
    }

    void DoDiffusion(int form)
    {
        
    }

    void DoRenderWindVelocityData(int form)
    {
        
    }

    void DoAdvection(int form)
    {
        
    }
    
    

    public void AddWindMotor(WindMotor motor)
    {
        
    }

    public void RemoveWindMotor(WindMotor motor)
    {
        
    }

    void ClearRenderTexture(ref RenderTexture rt)
    {
        
    }

    public Vector3 GetWindForceByPosAndDeltaTime(Vector3 pos)
    {
        return Vector3.zero;
    }

    Vector3 ConvertFloatPointToInt(Vector3 v)
    {
        return Vector3.zero;
    }

    public void OnDestroy()
    {
        
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
        
        
    }
    
    private void CreateRenderTexture(ref RenderTexture rt, ref RenderTextureDescriptor rtDesc, string name)
    {
        
    }

    private void DoMergeChannel(int form)
    {
        
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
