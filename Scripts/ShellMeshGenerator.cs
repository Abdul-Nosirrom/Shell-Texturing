using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace Abdulal.ShellTexturing
{
    [RequireComponent(typeof(MeshFilter)), RequireComponent(typeof(MeshRenderer))]
    public class ShellMeshGenerator : MonoBehaviour
    {
        /// <summary>
        /// Number of shells to generate from the input mesh
        /// </summary>
        [Range(2, 256)] [SerializeField] private int m_numShells = 2;
        
        /// <summary>
        /// Total height of all the shells, each shell will be spaced by
        /// m_height/m_numShells
        /// </summary>
        [Range(0, 10)] [SerializeField] private float m_height = 0.1f;

        /// <summary>
        /// The source mesh to generate the shell mesh from.
        /// </summary>
        [SerializeField] 
        private Mesh m_sourceMesh;

        /// <summary>
        /// The generated shell mesh that'll be set to the mesh filter
        /// </summary>
        private Mesh m_shellMesh;

        /// <summary>
        /// Compute shader that generates the shell mesh
        /// </summary>
        [SerializeField] private ComputeShader m_computeShader;

        // Shader cached property IDs
        private readonly int k_triangleBuffer = Shader.PropertyToID("_Triangles");
        private readonly int k_positionBuffer = Shader.PropertyToID("_Positions");
        private readonly int k_normalBuffer = Shader.PropertyToID("_Normals");
        private readonly int k_uvBuffer = Shader.PropertyToID("_UVs");
        private readonly int k_colorBuffer = Shader.PropertyToID("_Colors");

        private readonly int k_numShells = Shader.PropertyToID("_NumShells");
        private readonly int k_vertexCount = Shader.PropertyToID("_VertexCount");
        private readonly int k_height = Shader.PropertyToID("_Height");
        private readonly int k_triangleCount = Shader.PropertyToID("_TriangleCount");

        private void OnValidate()
        {
            GenerateShellMesh();
        }

        private void GenerateShellMesh()
        {
            if (m_sourceMesh == null || m_computeShader == null)
            {
                Debug.LogError("Null Data");
                return;
            }
            
            // Dispatch the compute shader for NumTriangles time
            
#region SETUP BUFFERS
            
            ComputeBuffer vertexBuffer = new ComputeBuffer(m_sourceMesh.vertexCount * m_numShells, sizeof(float) * 3);
            vertexBuffer.SetData(m_sourceMesh.vertices, 0, 0, m_sourceMesh.vertexCount);
            
            ComputeBuffer triangleBuffer = new ComputeBuffer(m_sourceMesh.triangles.Length * m_numShells, sizeof(int));
            triangleBuffer.SetData(m_sourceMesh.triangles, 0, 0, m_sourceMesh.triangles.Length);
            
            ComputeBuffer uvBuffer = new ComputeBuffer(m_sourceMesh.uv.Length * m_numShells, sizeof(float) * 2);
            uvBuffer.SetData(m_sourceMesh.uv, 0, 0, m_sourceMesh.uv.Length);
            
            ComputeBuffer normalBuffer = new ComputeBuffer(m_sourceMesh.normals.Length * m_numShells, sizeof(float) * 3);
            normalBuffer.SetData(m_sourceMesh.normals, 0, 0, m_sourceMesh.normals.Length);
            
            ComputeBuffer colorBuffer = new ComputeBuffer(m_sourceMesh.vertexCount * m_numShells, sizeof(float) * 4);
            //colorBuffer.SetData(m_sourceMesh.colors);
            
#endregion
            
#region INITIALIZE DATA FOR COMPUTE SHADER & DISPATCH

            int numTriangles = m_sourceMesh.triangles.Length / 3;

            m_computeShader.GetKernelThreadGroupSizes(0, out uint threadSizeX, out _, out _);
            int threadGroupSize = Mathf.CeilToInt((float)numTriangles / threadSizeX);
            
            m_computeShader.SetBuffer(0, k_triangleBuffer, triangleBuffer);
            m_computeShader.SetBuffer(0, k_positionBuffer, vertexBuffer);
            m_computeShader.SetBuffer(0, k_normalBuffer, normalBuffer);
            m_computeShader.SetBuffer(0, k_uvBuffer, uvBuffer);
            m_computeShader.SetBuffer(0, k_colorBuffer, colorBuffer);
            
            m_computeShader.SetInt(k_numShells, m_numShells);
            m_computeShader.SetInt(k_vertexCount, m_sourceMesh.vertexCount);
            m_computeShader.SetFloat(k_height, m_height);
            m_computeShader.SetInt(k_triangleCount, numTriangles);
            
            m_computeShader.Dispatch(0, threadGroupSize, 1, 1);
            
#endregion             
            
#region GET DATA FROM COMPUTE SHADER TO MESH

            m_shellMesh = new Mesh();
            
            // Add a check for mesh size limits
            if (m_sourceMesh.vertexCount * m_numShells > UInt16.MaxValue && !m_sourceMesh.indexFormat.Equals(IndexFormat.UInt32))
            {
                Debug.LogWarning("[ShellTexturing] Shell mesh will exceed 16-bit index limit. Setting 32-bit indices.");
                m_shellMesh.indexFormat = IndexFormat.UInt32;
            }
            
            Vector3[] vertices = new Vector3[m_sourceMesh.vertexCount * m_numShells];
            int[] tris = new int[m_sourceMesh.triangles.Length * m_numShells];
            Vector2[] uvs = new Vector2[m_sourceMesh.uv.Length * m_numShells];
            Vector3[] normals = new Vector3[m_sourceMesh.normals.Length * m_numShells];
            Color[] colors = new Color[m_sourceMesh.vertexCount * m_numShells];
            
            vertexBuffer.GetData(vertices);
            triangleBuffer.GetData(tris);
            uvBuffer.GetData(uvs);
            normalBuffer.GetData(normals);
            colorBuffer.GetData(colors);
            
            m_shellMesh.SetVertices(vertices);
            m_shellMesh.SetTriangles(tris, 0);
            m_shellMesh.SetUVs(0, uvs);
            m_shellMesh.SetNormals(normals);
            m_shellMesh.SetColors(colors);
            
            GetComponent<MeshFilter>().sharedMesh = m_shellMesh;
            
#endregion

#region RELEASE DATA

            triangleBuffer.Release();
            vertexBuffer.Release();
            normalBuffer.Release();
            uvBuffer.Release();
            colorBuffer.Release();
            
#endregion
        }
    }
}