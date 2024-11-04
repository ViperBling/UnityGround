using System;
using UnityEngine;
using UnityEditor;
using System.IO;
using System.Collections;

// Flow Map Painter
[CustomEditor(typeof(FurPainter))]
[CanEditMultipleObjects]
public class FurPainterEditor : Editor
{
    bool m_bIsPainting = false;

    private float m_BrushSize = 15.0f;
    private float m_BrushStrength = 0.5f;

    private Texture[] m_BrushTextures;
    private Texture[] m_LayerTextures;

    private int m_SelectedBrush = 0;
    private int m_SelectedTexture = 0;

    private Texture2D m_FurFlowMap;

    private int m_BrushSizeInPercent;
    
    // Fur Flow
    public Vector2 m_FurDirection = Vector2.one;
    private Vector2 m_PreviousUV = Vector2.zero;
    
    // Can not call OnSceneGUI directly
    void OnEnable()
    {
        SceneView.duringSceneGui += this.OnSceneGUI;
    }

    private void OnDestroy()
    {
        SceneView.duringSceneGui -= this.OnSceneGUI;
    }

    void OnSceneGUI(SceneView obj)
    {
        if (m_bIsPainting)
        {
            FurPainter painter = Selection.activeTransform.gameObject.GetComponent<FurPainter>();
            m_FurFlowMap = painter.m_FurFlowMap;
            // Painting(m_FurFlowMap, painter.m_DrawType);
            Painting(m_FurFlowMap, FurPainter.DrawType.FurDirection);
        }
    }

    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();

        if (CheckResource())
        {
            GUIStyle boolBtnOn = new GUIStyle(GUI.skin.GetStyle("Button"));
            GUILayout.BeginHorizontal();
            GUILayout.FlexibleSpace();
            m_bIsPainting = GUILayout.Toggle(m_bIsPainting, EditorGUIUtility.IconContent("EditCollider"), boolBtnOn, GUILayout.Width(35), GUILayout.Height(25));
            GUILayout.FlexibleSpace();
            GUILayout.EndHorizontal();

            m_BrushSize = (int)EditorGUILayout.Slider("Brush Size", m_BrushSize, 1, 36);
            m_BrushStrength = EditorGUILayout.Slider("Brush Strength", m_BrushStrength, 0, 1);

            GetLayerTexture();
            InitBrush();
            
            GUILayout.BeginHorizontal();
            
            GUILayout.FlexibleSpace();
            GUILayout.BeginHorizontal("Box", GUILayout.Width(128));
            m_SelectedBrush = GUILayout.SelectionGrid(m_SelectedBrush, m_BrushTextures, 4, "GridList", GUILayout.Width(256), GUILayout.Height(64));
            GUILayout.EndHorizontal();
            GUILayout.FlexibleSpace();
            
            GUILayout.FlexibleSpace();
            GUILayout.BeginHorizontal("Box", GUILayout.Width(128));
            m_SelectedTexture = GUILayout.SelectionGrid(m_SelectedTexture, m_LayerTextures, 1, "GridList", GUILayout.Width(128), GUILayout.Height(130));
            GUILayout.EndHorizontal();
            GUILayout.FlexibleSpace();
            
            GUILayout.EndHorizontal();
            
            // GUILayout.BeginVertical();
            // GUILayout.FlexibleSpace();
            // GUILayout.BeginHorizontal("Box", GUILayout.Width(128));
            // m_SelectedTexture = GUILayout.SelectionGrid(m_SelectedTexture, m_LayerTextures, 1, "GridList", GUILayout.Width(128), GUILayout.Height(130));
            // GUILayout.EndHorizontal();
            // GUILayout.FlexibleSpace();
            // GUILayout.EndVertical();

            if (GUILayout.Button("Reset Texture"))
            {
                ResetTexture(m_FurFlowMap);
            }
            
            if (GUILayout.Button("Save FlowMap"))
            {
                SaveTexture(m_FurFlowMap);
            }
        }
    }

    void GetLayerTexture()
    {
        Transform select = Selection.activeTransform;

        m_LayerTextures = new Texture[1];
        m_LayerTextures[0] = select.gameObject.GetComponent<FurPainter>().m_FurFlowMap;
    }

    void InitBrush()
    {
        // Temporary
        string brushFolder = "Assets/MeshPainter/Editor/";
        ArrayList brushList = new ArrayList();
        Texture brushToLoad;
        int brushNum = 0;
        do
        {
            brushToLoad = AssetDatabase.LoadAssetAtPath<Texture>(brushFolder + "BrushesIcon/Brush" + brushNum + ".png");
            if (brushToLoad)
            {
                brushList.Add(brushToLoad);
            }

            brushNum++;
            if (brushNum > 3) break;
        } while (brushToLoad);

        m_BrushTextures = brushList.ToArray(typeof(Texture)) as Texture[];
    }

    bool CheckResource()
    {
        if (Selection.activeTransform == null)
        {
            EditorGUILayout.HelpBox("No selection!", MessageType.Warning);
            return false;
        }

        FurPainter painter = Selection.activeTransform.gameObject.GetComponent<FurPainter>();
        if (painter == null)
        {
            EditorGUILayout.HelpBox("No FurPainter component found!", MessageType.Warning);
            return false;
        }
        
        if (painter.m_FurFlowMap == null)
        {
            EditorGUILayout.HelpBox("FurFlowMap not setting!", MessageType.Warning);
            return false;
        }

        return true;
    }

    void Painting(Texture2D curTexture, FurPainter.DrawType drawType)
    {
        Transform curSelected = Selection.activeTransform;
        float orthographicSize;
        if (Selection.activeTransform.gameObject.GetComponent<FurPainter>().m_MeshType == FurPainter.MeshType.Mesh)
        {
            MeshFilter meshFilter = curSelected.GetComponent<MeshFilter>();
            orthographicSize = (m_BrushSize * curSelected.localScale.x) * (meshFilter.sharedMesh.bounds.size.x / 200);
        }
        else
        {
            SkinnedMeshRenderer skinnedMeshRenderer = curSelected.GetComponent<SkinnedMeshRenderer>();
            orthographicSize = (m_BrushSize * curSelected.localScale.x) * (skinnedMeshRenderer.localBounds.size.x / 200);
        }
        
        m_BrushSizeInPercent = (int)Mathf.Round(m_BrushSize * curTexture.width / 100);
        bool toggleFalse = false;
        Event inputEvent = Event.current;
        HandleUtility.AddDefaultControl(0);
        RaycastHit raycastHit = new RaycastHit();
        Ray ray = HandleUtility.GUIPointToWorldRay(inputEvent.mousePosition);

        if (Physics.Raycast(ray, out raycastHit, Mathf.Infinity, Selection.activeTransform.gameObject.GetComponent<FurPainter>().m_LayerMask))
        {
            Handles.color = new Color(1.0f, 1.0f, 0.0f, 1.0f);
            Handles.DrawWireDisc(raycastHit.point, raycastHit.normal, orthographicSize);
            
            if ((inputEvent.type == EventType.MouseDrag && inputEvent.alt == false && inputEvent.control == false && inputEvent.shift == false && inputEvent.button == 0) ||
                (inputEvent.type == EventType.MouseDown && inputEvent.alt == false && inputEvent.control == false && inputEvent.shift == false && inputEvent.button == 0 && toggleFalse == false))
            {
                Color targetColor = new Color(0.5f, 0.5f, 0.0f, 1.0f);
                // For now, only FurDirection
                // if (drawType == FurPainter.DrawType.FurLength)
                // {
                //     targetColor.a = Selection.activeTransform.gameObject.GetComponent<FurPainter>().m_BrushColor.r;
                // }
                // else
                {
                    Vector2 currentUV = raycastHit.textureCoord;
                    currentUV.x *= curTexture.width;
                    currentUV.y *= curTexture.height;

                    if (m_PreviousUV != Vector2.zero)
                    {
                        Vector2 direction = currentUV - m_PreviousUV;
                        m_FurDirection = direction.normalized;

                        targetColor.r = -m_FurDirection.x * 0.5f + 0.5f;
                        targetColor.g = -m_FurDirection.y * 0.5f + 0.5f;
                    }

                    m_PreviousUV = currentUV;
                }

                Vector2 pixelUV = raycastHit.textureCoord;
                int pixelUVX = Mathf.FloorToInt(pixelUV.x * curTexture.width);
                int pixelUVY = Mathf.FloorToInt(pixelUV.y * curTexture.height);
                int paintPointX = Mathf.Clamp(pixelUVX - m_BrushSizeInPercent / 2, 0, curTexture.width - 1);
                int paintPointY = Mathf.Clamp(pixelUVY - m_BrushSizeInPercent / 2, 0, curTexture.height - 1);
                int paintAreaW = Mathf.Clamp(pixelUVX + m_BrushSizeInPercent / 2, 0, curTexture.width) - paintPointX;
                int paintAreaH = Mathf.Clamp(pixelUVY + m_BrushSizeInPercent / 2, 0, curTexture.height) - paintPointY;

                Color[] texColor = curTexture.GetPixels(paintPointX, paintPointY, paintAreaW, paintAreaH, 0);

                Texture2D brush = m_BrushTextures[m_SelectedBrush] as Texture2D;
                float[] brushAlpha = new float[m_BrushSizeInPercent * m_BrushSizeInPercent];
                
                // Calculate brush alpha
                for (int i = 0; i < m_BrushSizeInPercent; i++)
                {
                    for (int j = 0; j < m_BrushSizeInPercent; j++)
                    {
                        brushAlpha[j * m_BrushSizeInPercent + i] = brush.GetPixelBilinear((float)i / m_BrushSizeInPercent, (float)j / m_BrushSizeInPercent).a;
                    }
                }
                
                // Apply brush
                for (int i = 0; i < paintAreaH; i++)
                {
                    for (int j = 0; j < paintAreaW; j++)
                    {
                        int index = i * paintAreaW + j;
                        int brushPixelIdx =
                            Mathf.Clamp((paintPointY + i) - (pixelUVY - m_BrushSizeInPercent / 2), 0, m_BrushSizeInPercent - 1) * m_BrushSizeInPercent +
                            Mathf.Clamp((paintPointX + j) - (pixelUVX - m_BrushSizeInPercent / 2), 0, m_BrushSizeInPercent - 1);
                        float strength = brushAlpha[brushPixelIdx] * m_BrushStrength;
                        texColor[index] = Color.Lerp(texColor[index], targetColor, strength);
                    }
                }
                Undo.RegisterCompleteObjectUndo(curTexture, "FurPainter");
                
                curTexture.SetPixels(paintPointX, paintPointY, paintAreaW, paintAreaH, texColor, 0);
                curTexture.Apply();
                toggleFalse = true;
                inputEvent.Use();
            }

            if (Input.GetMouseButtonUp(0))
            {
                m_PreviousUV = Vector2.zero;
            }
        }
    }

    void ResetTexture(Texture2D tex)
    {
        // Reset FlowMap
        Color[] colors = tex.GetPixels();
        for (int i = 0; i < colors.Length; i++)
        {
            colors[i] = new Color(0.5f, 0.5f, 0.0f, 1.0f);
        }
        tex.SetPixels(colors);
        tex.Apply();
    }

    void SaveTexture(Texture2D tex)
    {
        if (tex == null)
        {
            Debug.LogError("Texture is null!");
            return;
        }

        string path = AssetDatabase.GetAssetPath(tex);
        byte[] bytes = tex.EncodeToPNG();
        File.WriteAllBytes(path, bytes);
        
        Debug.Log("Texture saved at : " + path);

        EditorApplication.delayCall += () =>
        {
            AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceUpdate);
            Debug.Log("Asset database update.");
        };
    }
}
