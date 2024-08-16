using System.Collections;
using System.Collections.Generic;
using UnityEngine;

// [ExecuteInEditMode]
public class AutoRotation : MonoBehaviour
{
    [Tooltip("Angular velocity in degrees per seconds")]
    public float m_DegPerSec = 60.0f;

    [Tooltip("Rotation axis")]
    public Vector3 m_RotAxis = Vector3.up;
    
    // Start is called before the first frame update
    void Start()
    {
        m_RotAxis.Normalize();
    }

    // Update is called once per frame
    void Update()
    {
        transform.Rotate(m_RotAxis, m_DegPerSec * Time.deltaTime);
    }
}
