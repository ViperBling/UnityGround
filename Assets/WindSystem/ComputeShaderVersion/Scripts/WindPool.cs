using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Object = UnityEngine.Object;

public class WindPool : MonoBehaviour
{
    void Awake()
    {
        _instance = this;
    }

    void Start()
    {
        windContainer = GameObject.Find("WindContainer").transform;
        _windMotorPool.Clear();
        _windMotorCurrentNum = 0;
    }

    public GameObject PopWindMotor()
    {
        GameObject output;
        if (_windMotorCurrentNum > 0)
        {
            _windMotorCurrentNum = _windMotorCurrentNum - 1;
            output = _windMotorPool[_windMotorCurrentNum];
            _windMotorPool.RemoveAt(_windMotorCurrentNum);
        }
        else
        {
            output = GameObject.Instantiate(windMotorPrefab, windContainer);
        }
        output.SetActive(true);
        return output;
    }

    public void PushWindMotor(GameObject windObj)
    {
        windObj.SetActive(false);
        if (_windMotorCurrentNum < _maxNum)
        {
            _windMotorPool.Add(windObj);
            _windMotorCurrentNum++;
        }
        else
        {
            Object.DestroyImmediate(windObj);
        }
    }

    private static WindPool _instance;
    public static WindPool Instance
    {
        get { return _instance; }
    }

    public Transform windContainer;
    public GameObject windMotorPrefab;

    private List<GameObject> _windMotorPool = new List<GameObject>();
    private int _maxNum = 10;
    private int _windMotorCurrentNum = 0;
}
