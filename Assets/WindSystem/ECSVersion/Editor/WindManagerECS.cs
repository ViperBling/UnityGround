using System;
using System.Collections;
using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using Unity.Entities;
using Unity.Jobs;
using Unity.Mathematics;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Serialization;

public class WindManagerECS : MonoBehaviour
{

    private static WindManagerECS mInstance;

    public static WindManagerECS Instance
    {
        get { return mInstance; }
    }
}