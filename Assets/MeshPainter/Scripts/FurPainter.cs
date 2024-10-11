using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
[RequireComponent(typeof(MeshCollider))]
public class FurPainter : MonoBehaviour
{
    public enum MeshType
    {
        SkinnedMesh,
        Mesh
    }

    public enum DrawType
    {
        FurLength,
        FurDirection
    }

    public MeshType m_MeshType;
    // public DrawType m_DrawType;
    public Texture2D m_FurFlowMap;
    public LayerMask m_LayerMask;
    // public Color m_BrushColor;
    
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }
}
