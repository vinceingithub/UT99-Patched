Texture2D<float4> tColor;
Texture2D<float>  tSource;
Texture2D<float>  tDepth;
Texture2D<float>  tDepthBuffer;

cbuffer cb1
{
	float2 g_Resolution;
	float2 g_InvResolution;
	float g_BlurRadius;
	float g_BlurFalloff;
	float g_Sharpness;
	float g_EdgeThreshold;
	float2 g_ZLinParams;
	float3 flash;
}

SamplerState samNearest
{
    Filter   = MIN_MAG_MIP_POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};

SamplerState samLinear
{
    Filter   = MIN_MAG_MIP_LINEAR;
    AddressU = Clamp;
    AddressV = Clamp;
};

//--------------------------------------------------------------------------------------
DepthStencilState DisableDepth
{
    DepthEnable    = FALSE;
    DepthWriteMask = ZERO;
};

BlendState DisableBlend
{
    BlendEnable[0] = false;
};

BlendState EnableBlend
{
    BlendEnable[0] = true;
};

//--------------------------------------------------------------------------------------
struct PostProc_VSOut
{
    float4 pos : SV_Position;
    float2 tex : TEXCOORD0;
};

PostProc_VSOut FullScreenQuadVS( uint id : SV_VertexID )
{
    PostProc_VSOut output = (PostProc_VSOut)0.0f;

    output.tex = float2( (id << 1) & 2, id & 2 );
    output.pos = float4( output.tex * float2( 2.0f, -2.0f ) + float2( -1.0f, 1.0f) , 0.0f, 1.0f );
    
    return output;
}

//-------------------------------------------------------------------------
float fetch_eye_z(float2 uv)
{
    float z = tDepth.Sample(samNearest, uv);
    return z;
}

//-------------------------------------------------------------------------
float BlurFunction(float2 uv, float r, float center_c, float center_d, inout float w_total)
{
    float c = tSource.Sample( samNearest, uv );
    float d = fetch_eye_z(uv);

    float ddiff = d - center_d;
    float w = exp(-r*r*g_BlurFalloff - ddiff*ddiff*g_Sharpness);
    w_total += w;

    return w*c;
}

//-------------------------------------------------------------------------
float4 BlurX( PostProc_VSOut IN ): SV_TARGET
{
    float b = 0;
    float w_total = 0;
    float center_c = tSource.Sample( samNearest, IN.tex );
    float center_d = fetch_eye_z(IN.tex);
    
    for (float r = -g_BlurRadius; r <= g_BlurRadius; ++r)
    {
        float2 uv = IN.tex.xy + float2(r*g_InvResolution.x , 0);
        b += BlurFunction(uv, r, center_c, center_d, w_total);	
    }

    return b/w_total;
}

//-------------------------------------------------------------------------
float4 BlurY(PostProc_VSOut IN): SV_TARGET
{
    float b = 0;
    float w_total = 0;
    float center_c = tSource.Sample( samNearest, IN.tex, 0 );
    float center_d = fetch_eye_z(IN.tex);
    
    for (float r = -g_BlurRadius; r <= g_BlurRadius; ++r)
    {
        float2 uv = IN.tex.xy + float2(0, r*g_InvResolution.y); 
        b += BlurFunction(uv, r, center_c, center_d, w_total);
    }
	#if(HDR_ENABLED==0)
	return  b / w_total * tColor.Sample(samNearest, IN.tex, 0) + float4(flash.rgb, 0);
	#else
	return  b / w_total * tColor.Sample(samNearest, IN.tex, 0);
	#endif
    return b/w_total;	
}


technique11 HBAO_BLUR
{
    pass pX
    {
        SetVertexShader( CompileShader( vs_5_0, FullScreenQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, BlurX() ) );
        SetBlendState( DisableBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
    }

    pass pY
    {
        SetVertexShader( CompileShader( vs_5_0, FullScreenQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, BlurY() ) );
        SetBlendState( DisableBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
    }
}
