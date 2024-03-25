using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

public class CreateSDFTexture : EditorWindow
{
    public Texture2D SourceTex;
    
    // [SerializeField]
    public ComputeShader _mSDFGeneratorCS;

    public struct Edge
    {
        public int edge;
    }
    
    private static CreateSDFTexture _window;
    private SerializedProperty _mTexProperty;
    private SerializedObject _mSerializedObj;

    private string _mSavePath = "";
    private int _mSourceWidth = 32;
    private int _mSourceHeight = 32;

    [MenuItem("Tools/SDF Generator")]
    private static void CreateSDF()
    {
        _window = EditorWindow.GetWindow<CreateSDFTexture>("SDF Generator");
        _window.Show();
        _window.minSize = new Vector2(200, 300);
    }
    
    void OnEnable()
    {
        _mSerializedObj = new SerializedObject(this);
        _mTexProperty = _mSerializedObj.FindProperty("SourceTex");
    }

    void DrawTextureProperties()
    {
        EditorGUILayout.BeginVertical();
        EditorGUILayout.LabelField("Source Texture");
        EditorGUILayout.PropertyField(_mTexProperty, true);
        EditorGUILayout.EndVertical();
        _mSerializedObj.ApplyModifiedProperties();
    }

    void OnGUI()
    {
        DrawTextureProperties();
        ComputeSDF();
    }

    private void ComputeSDF()
    {
        if (SourceTex == null)
        {
            _window.ShowNotification(new GUIContent("Please select a texture"));
            return;
        }
        
        _mSavePath = EditorUtility.SaveFilePanel("Save Texture", Application.dataPath, "SDFTextureGPU", "png");
        if (_mSavePath == null)
        {
            return;
        }
        _mSDFGeneratorCS = (ComputeShader)AssetDatabase.LoadAssetAtPath("Assets/VFXTest/MaskTrail/Shaders/SDFGeneratorCS.compute", typeof(ComputeShader));
        _mSourceWidth = SourceTex.width;
        _mSourceHeight = SourceTex.height;
        
        if (GUILayout.Button("Create SDF Texture And Save"))
        {
            
        }
    }

    private void GetEdgeOnGPU(Texture2D source)
    {
        if (source.isReadable == false)
        {
            _window.ShowNotification(new GUIContent("Source texture is not readable"));
            return;
        }
        int edgeKernel = _mSDFGeneratorCS.FindKernel("GetEdge");
        int intSize = sizeof(int);
        int maxIndex = _mSourceHeight * _mSourceWidth;
        Edge[] edges = new Edge[maxIndex];
        
        ComputeBuffer edgeBuffer = new ComputeBuffer(maxIndex, intSize);
        edgeBuffer.SetData(edges);
        _mSDFGeneratorCS.SetTexture(edgeKernel, "Source", source);
        _mSDFGeneratorCS.SetBuffer(edgeKernel, "Result", edgeBuffer);
        _mSDFGeneratorCS.SetInt("_Width", _mSourceWidth);
        _mSDFGeneratorCS.Dispatch(edgeKernel, _mSourceWidth / 32, _mSourceHeight / 32, 1);
        edgeBuffer.GetData(edges);
    }
}
