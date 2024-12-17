using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Windows;

namespace ShaderWorkingGround.Editor
{
    public class CreateSDFTexture : EditorWindow
    {
        public struct Edge
        {
            public int edge;
            public int inTarget;
            public int X;
            public int Y;
            public float distance;
        }
        
        public Texture2D SourceTex;
        public ComputeShader _mSDFGeneratorCS;
    
        private RenderTexture _mRT0;
        private Texture2D DestTexture;
        
        private static CreateSDFTexture _window;
        private SerializedProperty _mTexProperty;
        private SerializedObject _mSerializedObj;
    
        private string _mSavePath = "";
        private int _mSourceWidth = 32;
        private int _mSourceHeight = 32;
        private float _mMaxDistance = 0.0f;
    
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
            if (GUILayout.Button("Create SDF Texture And Save"))
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
                
                _mSDFGeneratorCS = (ComputeShader)AssetDatabase.LoadAssetAtPath("Assets/VFXTest/MaskTrail/Shaders/SDFGenerateCS.compute", typeof(ComputeShader));
                _mSourceWidth = SourceTex.width;
                _mSourceHeight = SourceTex.height;
                GetEdgeOnGPU(SourceTex);
                DestTexture = new Texture2D(_mSourceWidth, _mSourceHeight);
                RenderTexture.active = _mRT0;
                DestTexture.ReadPixels(new Rect(0, 0, _mRT0.width, _mRT0.height), 0, 0);
                SaveTextureAsPNG(DestTexture, _mSavePath);
                _mRT0.Release();
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
            int intSize = sizeof(int) * 4 + sizeof(float);
            int maxIndex = _mSourceHeight * _mSourceWidth;
            Edge[] edges = new Edge[maxIndex];
            
            ComputeBuffer edgeBuffer = new ComputeBuffer(maxIndex, intSize);
            edgeBuffer.SetData(edges);
            
            _mSDFGeneratorCS.SetTexture(edgeKernel, "Source", source);
            _mSDFGeneratorCS.SetBuffer(edgeKernel, "Result", edgeBuffer);
            _mSDFGeneratorCS.SetInt("_Width", _mSourceWidth);
            _mSDFGeneratorCS.Dispatch(edgeKernel, _mSourceWidth / 32, _mSourceHeight / 32, 1);
            edgeBuffer.GetData(edges);
            
            GetSDF(ref edges);
    
            _mRT0 = new RenderTexture(_mSourceWidth, _mSourceHeight, 0);
            _mRT0.enableRandomWrite = true;
            _mRT0.Create();
            edgeBuffer.SetData(edges);
            int setTexKernel = _mSDFGeneratorCS.FindKernel("SetRT");
            _mSDFGeneratorCS.SetBuffer(setTexKernel, "IsEdge", edgeBuffer);
            _mSDFGeneratorCS.SetTexture(setTexKernel, "DestRT", _mRT0);
            _mSDFGeneratorCS.Dispatch(setTexKernel, _mSourceWidth / 32, _mSourceHeight / 32, 1);
            _mSDFGeneratorCS.SetFloat("_MaxDistance", _mMaxDistance);
            edgeBuffer.Release();
        }
    
        private void SaveTextureAsPNG(Texture2D png, string path)
        {
            png.Apply();
            File.WriteAllBytes(path, png.EncodeToPNG());
            AssetDatabase.Refresh();
        }
    
        float GetDistance(int dx, int dy)
        {
            float dist = Mathf.Sqrt(dx * dx + dy * dy);
            return Mathf.Exp(dist);
        }
    
        private void GetSDF(ref Edge[] edges)
        {
            for (int h = 0; h < _mSourceHeight; h++)
            {
                for (int w = 0; w < _mSourceWidth; w++)
                {
                    int index = h * _mSourceWidth + w;
    
                    if (edges[index].inTarget == 1)
                    {
                        int bottomIndex = (h - 1) * _mSourceWidth + w;
                        int leftIndex = h * _mSourceWidth + w - 1;
                        int bottomLeftIndex = (h - 1) * _mSourceWidth + w - 1;
                        int bottomRightIndex = (h - 1) * _mSourceWidth + w + 1;
                        //向左检测像素
                        if (edges[leftIndex].distance + 1 < edges[index].distance && w - 1 >= 0)
                        {
                            edges[index].X = edges[leftIndex].X;
                            edges[index].Y = edges[leftIndex].Y;
                            edges[index].distance = GetDistance(edges[index].X - w, edges[index].Y - h);
                        }
    
                        //向左下检测像素
                        if (edges[bottomLeftIndex].distance + 1.414 < edges[index].distance && h - 1 >= 0 && w - 1 >= 0)
                        {
                            edges[index].X = edges[bottomLeftIndex].X;
                            edges[index].Y = edges[bottomLeftIndex].Y;
                            edges[index].distance = GetDistance(edges[index].X - w, edges[index].Y - h);
                        }
    
                        //向下检测像素
                        if (edges[bottomIndex].distance + 1 < edges[index].distance && h - 1 >= 0)
                        {
                            edges[index].X = edges[bottomIndex].X;
                            edges[index].Y = edges[bottomIndex].Y;
                            edges[index].distance = GetDistance(edges[index].X - w, edges[index].Y - h);
                        }
    
                        //向右下检测像素
                        if (edges[bottomRightIndex].distance + 1.414 < edges[index].distance && h - 1 >= 0 &&
                            w + 1 < _mSourceWidth)
                        {
                            edges[index].X = edges[bottomRightIndex].X;
                            edges[index].Y = edges[bottomRightIndex].Y;
                            edges[index].distance = GetDistance(edges[index].X - w, edges[index].Y - h);
                        }
    
                    }
                }
            }
    
            //反向遍历像素
            for (int h = _mSourceHeight - 1; h >= 0; h--)
            {
                for (int w = _mSourceWidth - 1; w >= 0; w--)
                {
                    int index = h * _mSourceWidth + w;
                    if (edges[index].inTarget == 1)
                    {
                        int topIndex = (h + 1) * _mSourceWidth + w;
                        int rightIndex = h * _mSourceWidth + w + 1;
                        int topLeftIndex = (h + 1) * _mSourceWidth + w - 1;
                        int topRightIndex = (h + 1) * _mSourceWidth + w + 1;
    
                        //向右检测像素
                        if (w + 1 < _mSourceWidth && edges[rightIndex].distance + 1 < edges[index].distance)
                        {
                            edges[index].X = edges[rightIndex].X;
                            edges[index].Y = edges[rightIndex].Y;
                            edges[index].distance = GetDistance(edges[index].X - w, edges[index].Y - h);
                        }
    
                        //向右上检测像素
                        if (h + 1 < _mSourceHeight && w + 1 < _mSourceWidth &&
                            edges[topRightIndex].distance + 1.414 < edges[index].distance)
                        {
                            edges[index].X = edges[topRightIndex].X;
                            edges[index].Y = edges[topRightIndex].Y;
                            edges[index].distance = GetDistance(edges[index].X - w, edges[index].Y - h);
                        }
    
                        //向上检测像素
                        if (h + 1 < _mSourceHeight && edges[topIndex].distance + 1 < edges[index].distance)
                        {
                            edges[index].X = edges[topIndex].X;
                            edges[index].Y = edges[topIndex].Y;
                            edges[index].distance = GetDistance(edges[index].X - w, edges[index].Y - h);
                        }
    
                        //向左上检测像素
                        if (h + 1 < _mSourceHeight && w - 1 >= 0 &&
                            edges[topLeftIndex].distance + 1.414 < edges[index].distance)
                        {
                            edges[index].X = edges[topLeftIndex].X;
                            edges[index].Y = edges[topLeftIndex].Y;
                            edges[index].distance = GetDistance(edges[index].X - w, edges[index].Y - h);
                        }
    
                        if (edges[index].distance < 999999 && _mMaxDistance < edges[index].distance)
                        {
                            _mMaxDistance = edges[index].distance;
                        }
                    }
                }
            }
        }
    }

}
