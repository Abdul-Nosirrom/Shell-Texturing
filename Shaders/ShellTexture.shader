Shader "FreeSkies/ShellTexture"
{
    Properties
    {
        [KeywordEnum(Procedural, Full, Strand)] _TextureType("Texture Type", Float) = 0
        
        [Header(Global Texture Based Shape)]
        [MainTexture] _MainTex ("Shape Texture", 2D) = "white" {}

        [Header(Individual Strand Shape Texture)]
        _GridDimensions("Grid Dimensions", Vector) = (64, 64, 0, 0)
        _StrandPow("Strand Attenuation", Range(0, 1)) = 0.5
        
        [Header(Wind)][Space(10)]
        _WindTexture ("Wind Texture", 2D) = "black" {}
        _ScrollVelocity("Wind Scroll Velocity", Vector) = (64, 64, 0, 0)
        _MaxDisplacement("Wind Strength", Range(0,1)) = 0.2

        [Header(Shape And Color)][Space(10)]
        [MainColor] [HDR] _Color ("Color", Color) = (1,1,1,1)
        _MinHeight("Min Height", Range(0, 1)) = 0.5
        _AOFactor ("AO Factor", Range(0, 1)) = 0.5

        [Header(Additional Viz)] [Space(10)]
        [HDR] _FresnelGlow ("Highlight Color", Color) = (0,0,0,0)
        _FresnelFactor ("Highlight Factor", Range(0, 10)) = 0.5

    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "Queue"="Geometry"
            "RenderPipeline"="UniversalPipeline"
        }
        LOD 100
        Cull Off
        
        HLSLINCLUDE

        #pragma shader_feature_local _TEXTURETYPE_PROCEDURAL _TEXTURETYPE_FULL _TEXTURETYPE_STRAND
        
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        
        struct vertexdata
        {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
            float4 color : COLOR;
            float3 normalOS : NORMAL;
            float3 tangentOS : TANGENT;
        };

        struct interpolators
        {
            float2 uv : TEXCOORD0;
            float fogCoord : TEXCOORD1;
            float4 color : TEXCOORD2;
            float4 vertex : SV_POSITION;
            float3 normalWS : TEXCOORD3;
            float3 positionWS : TEXCOORD4;
        };

        TEXTURE2D(_WindTexture);
        SAMPLER(sampler_WindTexture);

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);

        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
        
            float4 _GridDimensions;
            float _StrandPow;

            float4 _Color;
            float _MinHeight;
            float _AOFactor;

            float4 _FresnelGlow;
            float _FresnelFactor;
        
            float4 _WindTexture_ST;
            float4 _ScrollVelocity;
            float _MaxDisplacement;
        CBUFFER_END

        float rand(float2 seed)
        {
            return frac(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453);
        }

        float GrassShapeGenerator(interpolators i)
        {
            #if defined(_TEXTURETYPE_FULL)
            return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).r;
            #else 
            // Generate a grid of points
            float2 gridUV = i.uv * floor(_GridDimensions.xy);
            float2 bladeIndex = floor(gridUV);

            float height = lerp(_MinHeight, 1, rand(bladeIndex));
            

            #if defined(_TEXTURETYPE_PROCEDURAL)
            gridUV = frac(gridUV);
            float strandVal = pow(1 - distance(gridUV, float2(0.5, 0.5)), 2); // basic radial shape with slight attenuation for a more curved quadratic shape
            #else
            float strandVal =  pow(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, gridUV).r, _StrandPow);
            #endif // Strand texture
            
            return height * strandVal;
            #endif
        }

        interpolators vert(vertexdata v)
        {
            interpolators o;

            // Apply wind
            float2 scrollingUV = TRANSFORM_TEX(v.uv + _Time.y * _ScrollVelocity.xy, _WindTexture);
            float2 windSample = v.color * _MaxDisplacement * (SAMPLE_TEXTURE2D_GRAD(_WindTexture, sampler_WindTexture, scrollingUV, 0, 0) - 0.5) * 2;

            // Want to apply this displacement in TS not OS for the cases of spheres and other non-plane shapes (simple)
            float3 displacementTS = float3(windSample.x, 0, windSample.y); // along tangent & bitangent
            float displacementMag = length(displacementTS);

            float3x3 tangentToWorld = CreateTangentToWorld(normalize(v.normalOS), normalize(v.tangentOS), 1);
            float3 displacementOS = SafeNormalize(TransformTangentToObject(SafeNormalize(displacementTS), tangentToWorld)) * displacementMag;
            
            o.vertex = TransformObjectToHClip(v.vertex + displacementOS);
            o.uv = TRANSFORM_TEX(v.uv, _MainTex);
            o.color = v.color;
            o.normalWS = TransformObjectToWorldNormal(v.normalOS);

            // Calculate fog factor
            o.fogCoord = ComputeFogFactor(o.vertex.z);

            // Set WS position (for lighting)
            o.positionWS = TransformObjectToWorld(v.vertex).xyz;
            
            return o;
        }

        void shell_evaluator(interpolators i)
        {
            // sample the texture
            float4 col = GrassShapeGenerator(i);

            if (col.r < i.color.r)
                discard;
        }
        
        ENDHLSL

        Pass
        {
            Name "ShellTexture"
            Tags
            {
                "LightMode"="UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog
            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOW_SCREEN
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            float3 half_lambert(Light L, float3 N, inout float3 fresnel)
            {
                float NoL = dot(N, L.direction) * 0.5f + 0.5f;
                fresnel *= NoL * L.shadowAttenuation * L.distanceAttenuation;
                return NoL * L.shadowAttenuation * L.color * L.distanceAttenuation;
            }
            
            float4 frag(interpolators i) : SV_Target
            {
                // sample the texture
                shell_evaluator(i);

                float4 col = _Color * lerp(_AOFactor, 1.0f, i.color.r);

                // Half Lambertian Lighting (NoL * 0.5 + 0.5)
                {
                    float3 N = normalize(i.normalWS);   

                    // Fresnel Highlight
                    float3 V = normalize(GetCameraPositionWS() - i.positionWS);
                    float3 fresnel = pow(saturate(1 - dot(N, V)), _FresnelFactor) * _FresnelGlow.rgb;
                    
                    // Main Light
                    Light L = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                    float3 lightVal = half_lambert(L, N, fresnel);

                    // Additional Lights
                    for (int l = 0; l < GetAdditionalLightsCount(); l++)
                    {
                        L = GetAdditionalLight(l, i.positionWS, TransformWorldToShadowCoord(i.positionWS));
                        lightVal += half_lambert(L, N, fresnel);
                    }

                    // Ambient
                    lightVal += SampleSH(N);

                    // Apply fresnel
                    lightVal += fresnel;
                    
                    // Apply lighting
                    col.rgb *= lightVal;
                }
                
                // Apply fog
                col.rgb = MixFog(col.rgb, i.fogCoord);
                
                return col;
            }
            
            ENDHLSL
        }

        Pass
        {
            Name "Shell Depth"
            Tags
            {
                "LightMode" = "DepthOnly"
            }
            
            ColorMask 0
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment depthFrag

            float4 depthFrag(interpolators i) : SV_Target
            {
                shell_evaluator(i);
                return 0;
            }
            
            ENDHLSL
        }
    }
}