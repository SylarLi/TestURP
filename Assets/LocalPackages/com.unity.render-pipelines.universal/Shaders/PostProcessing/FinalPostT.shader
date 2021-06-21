Shader "Hidden/Universal Render Pipeline/FinalPostT"
{
    HLSLINCLUDE

        #pragma multi_compile_local _ _FXAA
        #pragma multi_compile_local _ _FILM_GRAIN
        #pragma multi_compile_local _ _DITHERING
		#pragma multi_compile_local _ _LINEAR_TO_SRGB_CONVERSION
        
        #include "Assets/LocalPackages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Assets/LocalPackages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
        #include "Assets/LocalPackages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Assets/LocalPackages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

        TEXTURE2D_X(_BlitTex);
        TEXTURE2D(_Grain_Texture);
        TEXTURE2D(_BlueNoise_Texture);

        float4 _BlitTex_TexelSize;
        float2 _Grain_Params;
        float4 _Grain_TilingParams;
        float4 _Dithering_Params;

        #define GrainIntensity          _Grain_Params.x
        #define GrainResponse           _Grain_Params.y
        #define GrainScale              _Grain_TilingParams.xy
        #define GrainOffset             _Grain_TilingParams.zw

        #define DitheringScale          _Dithering_Params.xy
        #define DitheringOffset         _Dithering_Params.zw

        #define FXAA_SPAN_MAX           (8.0)
        #define FXAA_REDUCE_MUL         (1.0 / 8.0)
        #define FXAA_REDUCE_MIN         (1.0 / 128.0)

        half4 Fetch(float2 coords, float2 offset)
        {
            float2 uv = coords + offset;
            return SAMPLE_TEXTURE2D_X(_BlitTex, sampler_LinearClamp, uv);
        }

        half4 Load(int2 icoords, int idx, int idy)
        {
            #if SHADER_API_GLES
            float2 uv = (icoords + int2(idx, idy)) * _BlitTex_TexelSize.xy;
            return SAMPLE_TEXTURE2D_X(_BlitTex, sampler_LinearClamp, uv);
            #else
            return LOAD_TEXTURE2D_X(_BlitTex, clamp(icoords + int2(idx, idy), 0, _BlitTex_TexelSize.zw - 1.0));
            #endif
        }

        half4 Frag(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

            float2 uv = UnityStereoTransformScreenSpaceTex(input.uv);
            float2 positionNDC = uv;
            int2   positionSS  = uv * _BlitTex_TexelSize.zw;

            half4 color = Load(positionSS, 0, 0);

            #if _FXAA
            {
                // Edge detection
            	half4 rgbaNW = Load(positionSS, -1, -1);
                half4 rgbaNE = Load(positionSS,  1, -1);
                half4 rgbaSW = Load(positionSS, -1,  1);
                half4 rgbaSE = Load(positionSS,  1,  1);
            	rgbaNW = saturate(rgbaNW);
                rgbaNE = saturate(rgbaNE);
                rgbaSW = saturate(rgbaSW);
                rgbaSE = saturate(rgbaSE);
                color = saturate(color);

                half3 rgbNW = rgbaNW.xyz;
                half3 rgbNE = rgbaNE.xyz;
                half3 rgbSW = rgbaSW.xyz;
                half3 rgbSE = rgbaSE.xyz;

                half lumaNW = Luminance(rgbNW);
                half lumaNE = Luminance(rgbNE);
                half lumaSW = Luminance(rgbSW);
                half lumaSE = Luminance(rgbSE);
                half lumaM = Luminance(color.xyz);

                float2 dir;
                dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
                dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

                half lumaSum = lumaNW + lumaNE + lumaSW + lumaSE;
                float dirReduce = max(lumaSum * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
                float rcpDirMin = rcp(min(abs(dir.x), abs(dir.y)) + dirReduce);

                dir = min((FXAA_SPAN_MAX).xx, max((-FXAA_SPAN_MAX).xx, dir * rcpDirMin)) * _BlitTex_TexelSize.xy;

                // Blur
                half4 rgba03 = Fetch(positionNDC, dir * (0.0 / 3.0 - 0.5));
                half4 rgba13 = Fetch(positionNDC, dir * (1.0 / 3.0 - 0.5));
                half4 rgba23 = Fetch(positionNDC, dir * (2.0 / 3.0 - 0.5));
                half4 rgba33 = Fetch(positionNDC, dir * (3.0 / 3.0 - 0.5));
                rgba03 = saturate(rgba03);
                rgba13 = saturate(rgba13);
                rgba23 = saturate(rgba23);
                rgba33 = saturate(rgba33);

                half3 rgb03 = rgba03.xyz;
                half3 rgb13 = rgba13.xyz;
                half3 rgb23 = rgba23.xyz;
                half3 rgb33 = rgba33.xyz;

                half3 rgbA = 0.5 * (rgb13 + rgb23);
                half3 rgbB = rgbA * 0.5 + 0.25 * (rgb03 + rgb33);

                half lumaB = Luminance(rgbB);

                half lumaMin = Min3(lumaM, lumaNW, Min3(lumaNE, lumaSW, lumaSE));
                half lumaMax = Max3(lumaM, lumaNW, Max3(lumaNE, lumaSW, lumaSE));

                color.rgb = ((lumaB < lumaMin) || (lumaB > lumaMax)) ? rgbA : rgbB;

                // ------------------ alpha channel ---------------- //

                lumaNW = rgbaNW.w;
                lumaNE = rgbaNE.w;
                lumaSW = rgbaSW.w;
                lumaSE = rgbaSE.w;
                lumaM = color.w;

                dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
                dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

                lumaSum = lumaNW + lumaNE + lumaSW + lumaSE;
                dirReduce = max(lumaSum * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
                rcpDirMin = rcp(min(abs(dir.x), abs(dir.y)) + dirReduce);

                dir = min((FXAA_SPAN_MAX).xx, max((-FXAA_SPAN_MAX).xx, dir * rcpDirMin)) * _BlitTex_TexelSize.xy;

                // Blur
                half a03 = rgba03.w;
                half a13 = rgba13.w;
                half a23 = rgba23.w;
                half a33 = rgba33.w;

                half aA = 0.5 * (a13 + a23);
                half aB = aA * 0.5 + 0.25 * (a03 + a33);

                lumaB = aB;

                lumaMin = Min3(lumaM, lumaNW, Min3(lumaNE, lumaSW, lumaSE));
                lumaMax = Max3(lumaM, lumaNW, Max3(lumaNE, lumaSW, lumaSE));

                color.a = ((lumaB < lumaMin) || (lumaB > lumaMax)) ? aA : aB;
            }
            #endif

            #if _FILM_GRAIN
            {
                color.rgb = ApplyGrain(color.rgb, positionNDC, TEXTURE2D_ARGS(_Grain_Texture, sampler_LinearRepeat) , GrainIntensity, GrainResponse, GrainScale, GrainOffset);
            }
            #endif
			
			#if _LINEAR_TO_SRGB_CONVERSION
            {
                color.rgb = LinearToSRGB(color.rgb);
            }
            #endif

            #if _DITHERING
            {
                color.rgb = ApplyDithering(color.rgb, positionNDC, TEXTURE2D_ARGS(_BlueNoise_Texture, sampler_PointRepeat), DitheringScale, DitheringOffset);
            }
            #endif

            return color;
        }

    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "FinalPost"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment Frag
            ENDHLSL
        }
    }
}
