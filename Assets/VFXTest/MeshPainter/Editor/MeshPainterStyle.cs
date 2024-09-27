using System;
using System.Collections;
using Codice.CM.Common.Tree;
using UnityEngine;
using UnityEditor;
using UnityEngine.Windows;

[CustomEditor(typeof(MeshPainter))]
[CanEditMultipleObjects]
public class MeshPainterStyle : Editor
{
    string m_ControlTextureName = "";
    bool m_bIsPaint;
    private float m_BrushSize = 16f;
    private float m_BrushStrength = 0.5f;

    private Texture[] m_BrushTexs;
    private Texture[] m_TexLayers;
    private int m_SelectedBrush = 0;
    private int m_SelectedTexture = 0;

    private int m_BrushSizeInPercent;
    private Texture2D m_MaskTexture;

    void OnPreSceneGUI()
    {
        if (m_bIsPaint)
        {
            Painter();
        }
    }

    public override void OnInspectorGUI()
    {
        if (Check())
        {
            GUIStyle boolBtnOn = new GUIStyle(GUI.skin.GetStyle("Button"));
            GUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            m_bIsPaint = GUILayout.Toggle(m_bIsPaint, EditorGUIUtility.IconContent("EditCollider"), boolBtnOn,
                GUILayout.Width(35), GUILayout.Height(25));
            GUILayout.FlexibleSpace();
            GUILayout.EndHorizontal();
            m_BrushSize = (int)EditorGUILayout.Slider("Brush Size", m_BrushSize, 1, 36);//笔刷大小
            m_BrushStrength = EditorGUILayout.Slider("Brush Stronger", m_BrushStrength, 0, 1f);//笔刷强度
            
            InitBrush();
            LayerTexture();
            
            GUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.BeginHorizontal("Box", GUILayout.Width(340));
            m_SelectedTexture = GUILayout.SelectionGrid(m_SelectedTexture, m_TexLayers, 4, "GridList", GUILayout.Width(340), GUILayout.Height(86));
            GUILayout.EndHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.EndHorizontal();
            
            GUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.BeginHorizontal("Box", GUILayout.Width(318));
            m_SelectedBrush = GUILayout.SelectionGrid(m_SelectedBrush, m_BrushTexs, 9, "GridList", GUILayout.Width(340), GUILayout.Height(70));
            GUILayout.EndHorizontal();
            GUILayout.FlexibleSpace();
            GUILayout.EndHorizontal();
        }
        
        // if (m_bIsPaint)
        // {
        //     Painter();
        // }
    }

    void LayerTexture()
    {
        Transform select = Selection.activeTransform;
        m_TexLayers = new Texture[4];
        m_TexLayers[0] = AssetPreview.GetAssetPreview(select.gameObject.GetComponent<MeshRenderer>().sharedMaterial.GetTexture("_Splat0")) as Texture;
        m_TexLayers[1] = AssetPreview.GetAssetPreview(select.gameObject.GetComponent<MeshRenderer>().sharedMaterial.GetTexture("_Splat1")) as Texture;
        m_TexLayers[2] = AssetPreview.GetAssetPreview(select.gameObject.GetComponent<MeshRenderer>().sharedMaterial.GetTexture("_Splat2")) as Texture;
        m_TexLayers[3] = AssetPreview.GetAssetPreview(select.gameObject.GetComponent<MeshRenderer>().sharedMaterial.GetTexture("_Splat3")) as Texture;
    }

    void InitBrush()
    {
        string meshPaintEditorFolder = "Assets/VFXTest/MeshPainter/Editor/";
        ArrayList brushList = new ArrayList();
        Texture brushes;
        int numBrushes = 0;
        do
        {
            brushes = (Texture)AssetDatabase.LoadAssetAtPath(
                meshPaintEditorFolder + "BrushesIcon/Brush" + numBrushes + ".png", typeof(Texture));
            if (brushes)
            {
                brushList.Add(brushes);
            }

            numBrushes++;
        } while (brushes);
        m_BrushTexs = brushList.ToArray(typeof(Texture)) as Texture[];
    }

    bool Check()
    {
        bool isChecked = false;
        Transform select = Selection.activeTransform;
        Texture controlTex = select.gameObject.GetComponent<MeshRenderer>().sharedMaterial.GetTexture("_Control");

        if (select.gameObject.GetComponent<MeshRenderer>().sharedMaterial.shader == Shader.Find("Terrian/S_TextureBlend_Normal"))
        {
            if (controlTex == null)
            {
                EditorGUILayout.HelpBox("未找到Control贴图，绘制不可用", MessageType.Error);
                if (GUILayout.Button("创建Control贴图"))
                {
                    CreateControlTexture();
                }
            }
            else
            {
                isChecked = true;
            }
        }
        else
        {
            EditorGUILayout.HelpBox("模型Shader不匹配", MessageType.Error);
        }

        return isChecked;
    }

    void CreateControlTexture()
    {
        string controlTexFolder = "Assets/VFXTest/MeshPainter/Editor/ControlTexture/";
        Texture2D newMaskTex = new Texture2D(512, 512, TextureFormat.ARGB32, true);
        Color[] colorBase = new Color[512 * 512];
        for (int i = 0; i < colorBase.Length; i++)
        {
            colorBase[i] = new Color(1, 0, 0, 0);
        }
        newMaskTex.SetPixels(colorBase);

        bool exportNameSuccess = true;
        for (int num = 1; exportNameSuccess; num++)
        {
            string next = Selection.activeTransform.name + "_" + num;
            if (!File.Exists(controlTexFolder + Selection.activeTransform.name + ".png"))
            {
                m_ControlTextureName = Selection.activeTransform.name;
                exportNameSuccess = false;
            }
            else if (!File.Exists(controlTexFolder + next + ".png"))
            {
                m_ControlTextureName = next;
                exportNameSuccess = false;
            }
        }
        
        string path = controlTexFolder + m_ControlTextureName + ".png";
        byte[] texBytes = newMaskTex.EncodeToPNG();
        File.WriteAllBytes(path, texBytes);
        
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        TextureImporter texImporter = AssetImporter.GetAtPath(path) as TextureImporter;
        // texImporter.textureFormat =
        texImporter.isReadable = true;
        texImporter.anisoLevel = 9;
        texImporter.mipmapEnabled = false;
        texImporter.wrapMode = TextureWrapMode.Clamp;
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
        
        SetControlTexture(path);
    }

    void SetControlTexture(string path)
    {
        Texture controlTex = (Texture2D)AssetDatabase.LoadAssetAtPath(path, typeof(Texture2D));
        Selection.activeTransform.gameObject.GetComponent<MeshRenderer>().sharedMaterial.SetTexture("_Control", controlTex);
    }

    void Painter()
    {
        Transform currentSelected = Selection.activeTransform;
        MeshFilter meshFilter = currentSelected.GetComponent<MeshFilter>();
        float orthoGraphicsSize = m_BrushSize * currentSelected.localScale.x * meshFilter.sharedMesh.bounds.size.x / 200;
        m_MaskTexture = (Texture2D)currentSelected.gameObject.GetComponent<MeshRenderer>().sharedMaterial
            .GetTexture("_Control");

        m_BrushSizeInPercent = (int)Mathf.Round(m_BrushSize * m_MaskTexture.width / 100);
        bool toggleF = false;
        Event curInput = Event.current;
        HandleUtility.AddDefaultControl(0);
        RaycastHit rayCasHit = new RaycastHit();
        Ray ray = HandleUtility.GUIPointToWorldRay(curInput.mousePosition);

        if (Physics.Raycast(ray, out rayCasHit))
        {
            Handles.color = new Color(1.0f, 1.0f, 0.0f, 1.0f);
            Handles.DrawWireDisc(rayCasHit.point, rayCasHit.normal, orthoGraphicsSize);

            if ((curInput.type == EventType.MouseDrag && curInput.alt == false && curInput.control == false && curInput.shift == false && curInput.button == 0) ||
                (curInput.type == EventType.MouseDown && curInput.shift == false && curInput.alt == false && curInput.control == false && curInput.button == 1 && !toggleF))
            {
                Color targetColor = new Color(1.0f, 0.0f, 0.0f, 0.0f);
                switch (m_SelectedTexture)
                {
                    case 0:
                        targetColor = new Color(1.0f, 0.0f, 0.0f, 0.0f);
                        break;
                    case 1:
                        targetColor = new Color(0f, 1f, 0f, 0f);
                        break;
                    case 2:
                        targetColor = new Color(0f, 0f, 1f, 0f);
                        break;
                    case 3:
                        targetColor = new Color(0f, 0f, 0f, 1f);
                        break;
                }

                Vector2 pixelUV = rayCasHit.textureCoord;

                int puX = Mathf.FloorToInt(pixelUV.x * m_MaskTexture.width);
                int puY = Mathf.FloorToInt(pixelUV.y * m_MaskTexture.height);
                int x = Mathf.Clamp(puX - m_BrushSizeInPercent / 2, 0, m_MaskTexture.width - 1);
                int y = Mathf.Clamp(puY - m_BrushSizeInPercent / 2, 0, m_MaskTexture.height - 1);
                int width = Mathf.Clamp(puX + m_BrushSizeInPercent / 2, 0, m_MaskTexture.width) - x;
                int height = Mathf.Clamp(puY + m_BrushSizeInPercent / 2, 0, m_MaskTexture.height) - y;

                Color[] terrianBay = m_MaskTexture.GetPixels(x, y, width, height, 0);
                
                Texture2D tBrush = m_BrushTexs[m_SelectedBrush] as Texture2D;
                float[] brushAlpha = new float[m_BrushSizeInPercent * m_BrushSizeInPercent];

                for (int i = 0; i < m_BrushSizeInPercent; i++)
                {
                    for (int j = 0; j < m_BrushSizeInPercent; j++)
                    {
                        brushAlpha[j * m_BrushSizeInPercent + i] = tBrush.GetPixelBilinear((float)i / m_BrushSizeInPercent, (float)j / m_BrushSizeInPercent).a;
                    }
                }

                for (int i = 0; i < height; i++)
                {
                    for (int j = 0; j < width; j++)
                    {
                        int index = i * width + j;
                        float stronger =
                            brushAlpha[
                                Mathf.Clamp(y + i - (puY - m_BrushSizeInPercent / 2), 0, m_BrushSizeInPercent - 1) * m_BrushSizeInPercent + 
                                Mathf.Clamp(x + j - (puX - m_BrushSizeInPercent / 2), 0, m_BrushSizeInPercent - 1)] * m_BrushStrength;
                        terrianBay[index] = Color.Lerp(terrianBay[index], targetColor, stronger);
                    }
                }
                Undo.RegisterCompleteObjectUndo(m_MaskTexture, "MeshPaint");
                
                m_MaskTexture.SetPixels(x, y, width, height, terrianBay, 0);
                m_MaskTexture.Apply();
                toggleF = true;
            }
            else if (curInput.type == EventType.MouseUp && curInput.alt == false && curInput.button == 0 && toggleF)
            {
                SaveTexture();
                toggleF = false;
            }
        }
    }

    public void SaveTexture()
    {
        var path = AssetDatabase.GetAssetPath(m_MaskTexture);
        var bytes = m_MaskTexture.EncodeToPNG();
        File.WriteAllBytes(path, bytes);
        AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
    }
}
