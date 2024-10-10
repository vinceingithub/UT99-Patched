
#ifndef NUM_MSAA_SAMPLES
#define NUM_MSAA_SAMPLES 1
#endif

#ifndef DOWNSAMPLED
#define DOWNSAMPLED 0
#endif

#if NUM_MSAA_SAMPLES == 1
Texture2D<float4> tNormal;
Texture2D<float>  tDepth;
#else
Texture2DMS<float4, NUM_MSAA_SAMPLES> tNormal;
Texture2DMS<float, NUM_MSAA_SAMPLES>  tDepth;
#endif

float g_ZNear;
float g_ZFar;

SamplerState samNearest
{
    Filter   = MIN_MAG_MIP_POINT;
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

struct PS_OUTPUT
{
    float4 Normal : SV_Target0;
    float  Depth  : SV_Target1;
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

//----------------------------------------------------------------------------------
float LinearizeDepth(float input)
{
	float z;
	z = 1.0f - input;
	return 2 * g_ZNear / (g_ZNear + g_ZFar - z * (g_ZFar - g_ZNear));
}

//-------------------------------------------------------------------------
PS_OUTPUT Resolve_PS( PostProc_VSOut IN)
{
    PS_OUTPUT output;
#if NUM_MSAA_SAMPLES == 1
    output.Normal = tNormal.SampleLevel( samNearest, IN.tex, 0 );
    output.Depth  = LinearizeDepth(tDepth.SampleLevel ( samNearest, IN.tex, 0 ).x);
#else

#if DOWNSAMPLED == 1
    output.Normal = tNormal.Load( int2(IN.pos.xy)*2, 0 );
    output.Depth  = LinearizeDepth(tDepth.Load ( int2(IN.pos.xy)*2, 0 ).x);
#else
    output.Normal = tNormal.Load( int2(IN.pos.xy), 0 );
    output.Depth  = LinearizeDepth(tDepth.Load ( int2(IN.pos.xy), 0 ).x);
#endif

#endif
    return output;
}

//-------------------------------------------------------------------------
technique11 ResolveTechnique
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_5_0, FullScreenQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, Resolve_PS() ) );
        SetBlendState( DisableBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetDepthStencilState( DisableDepth, 0 );
    }
}
