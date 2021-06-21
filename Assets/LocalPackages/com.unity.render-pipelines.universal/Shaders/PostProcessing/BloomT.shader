Shader "Hidden/Universal Render Pipeline/BloomT"
{
    Properties
    {
        _MainTex("Source", 2D) = "white" {}
    }

    HLSLINCLUDE

        #include "Assets/LocalPackages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Assets/LocalPackages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"
        #include "Assets/LocalPackages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Assets/LocalPackages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

        TEXTURE2D_X(_MainTex);
        TEXTURE2D_X(_MainTexLowMip);

        float4 _MainTex_TexelSize;
        float4 _MainTexLowMip_TexelSize;

        float4 _Params; // x: scatter, y: clamp, z: threshold (linear), w: threshold knee

        #define Scatter             _Params.x
        #define ClampMax            _Params.y
        #define Threshold           _Params.z
        #define ThresholdKnee       _Params.w

        half4 EncodeHDR(half4 color)
        {
        #if UNITY_COLORSPACE_GAMMA
            return half4(sqrt(color.xyz), color.w); // linear to γ
        #else
            return color;
        #endif
        }

        half4 DecodeHDR(half4 color)
        {
        #if UNITY_COLORSPACE_GAMMA
            color.xyz *= color.xyz; // γ to linear
        #endif

        return color;
        }

        half4 FragPrefilter(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = UnityStereoTransformScreenSpaceTex(input.uv);
            half4 color = SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv);

            // User controlled clamp to limit crazy high broken spec
            color.rgb = min(ClampMax, color.rgb);

            // Thresholding
            half brightness = Max3(color.r, color.g, color.b) * color.a;
            half softness = clamp(brightness - Threshold + ThresholdKnee, 0.0, 2.0 * ThresholdKnee);
            softness = (softness * softness) / (4.0 * ThresholdKnee + 1e-4);
            half multiplier = max(brightness - Threshold, softness) / max(brightness, 1e-4);
            color.rgb *= multiplier;

            return EncodeHDR(color);
        }

        half4 FragBlurH(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float texelSize = _MainTex_TexelSize.x * 2.0;
            float2 uv = UnityStereoTransformScreenSpaceTex(input.uv);

            // 9-tap gaussian blur on the downsampled source
            half4 c0 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv - float2(texelSize * 4.0, 0.0)));
            half4 c1 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv - float2(texelSize * 3.0, 0.0)));
            half4 c2 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv - float2(texelSize * 2.0, 0.0)));
            half4 c3 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv - float2(texelSize * 1.0, 0.0)));
            half4 c4 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv                               ));
            half4 c5 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv + float2(texelSize * 1.0, 0.0)));
            half4 c6 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv + float2(texelSize * 2.0, 0.0)));
            half4 c7 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv + float2(texelSize * 3.0, 0.0)));
            half4 c8 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv + float2(texelSize * 4.0, 0.0)));

            half4 color = c0 * 0.01621622 + c1 * 0.05405405 + c2 * 0.12162162 + c3 * 0.19459459
                        + c4 * 0.22702703
                        + c5 * 0.19459459 + c6 * 0.12162162 + c7 * 0.05405405 + c8 * 0.01621622;

            // 如果像素点alpha大于0，则不修改alpha值，否则使用计算结果
            color.a = lerp(c4.a, color.a, 1 - sign(c4.a));

            return EncodeHDR(color);
        }

        half4 FragBlurV(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float texelSize = _MainTex_TexelSize.y;
            float2 uv = UnityStereoTransformScreenSpaceTex(input.uv);

            // Optimized bilinear 5-tap gaussian on the same-sized source (9-tap equivalent)
            half4 c0 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv - float2(0.0, texelSize * 3.23076923)));
            half4 c1 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv - float2(0.0, texelSize * 1.38461538)));
            half4 c2 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv                                      ));
            half4 c3 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv + float2(0.0, texelSize * 1.38461538)));
            half4 c4 = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv + float2(0.0, texelSize * 3.23076923)));

            half4 color = c0 * 0.07027027 + c1 * 0.31621622
                        + c2 * 0.22702703
                        + c3 * 0.31621622 + c4 * 0.07027027;

            // 如果像素点alpha大于0，则不修改alpha值，否则使用计算结果
            color.a = lerp(c2.a, color.a, 1 - sign(c2.a));

            return EncodeHDR(color);
        }

        half4 Upsample(float2 uv)
        {
            half4 highMip = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, uv));

        #if _BLOOM_HQ && !defined(SHADER_API_GLES)
            half4 lowMip = DecodeHDR(SampleTexture2DBicubic(TEXTURE2D_X_ARGS(_MainTexLowMip, sampler_LinearClamp), uv, _MainTexLowMip_TexelSize.zwxy, (1.0).xx, unity_StereoEyeIndex));
        #else
            half4 lowMip = DecodeHDR(SAMPLE_TEXTURE2D_X(_MainTexLowMip, sampler_LinearClamp, uv));
        #endif

            return lerp(highMip, lowMip, Scatter);
        }

        half4 FragUpsample(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            half4 color = Upsample(UnityStereoTransformScreenSpaceTex(input.uv));
            return EncodeHDR(color);
        }

    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "Bloom Prefilter"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragPrefilter
            ENDHLSL
        }

        Pass
        {
            Name "Bloom Blur Horizontal"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragBlurH
            ENDHLSL
        }

        Pass
        {
            Name "Bloom Blur Vertical"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragBlurV
            ENDHLSL
        }

        Pass
        {
            Name "Bloom Upsample"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragUpsample
                #pragma multi_compile_local _ _BLOOM_HQ
            ENDHLSL
        }
    }
}
