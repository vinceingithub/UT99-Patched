/**
Shader for Rune fog surfaces
*/

#include "common.fxh"
#include "unrealpool.fxh"

cbuffer PerScene
{
	matrix projection;
};
#if(SAMPLES>1)
Texture2DMS<float4,SAMPLES>  texNormal;
#else
Texture2D<float4> texNormal;
#endif

struct VS_INPUT
{	
	float3 pos : POSITION;
	float4 color: COLOR0;
	uint flags: BLENDINDICES;
};


struct PS_INPUT
{	
	float4 pos : SV_POSITION;
	float4 color: COLOR0;
	uint flags: BLENDINDICES;
};

struct PS_SIMPLE
{	
	float4 pos : SV_POSITION;
};

//--------------------------------------------------------------------------------------
// Vertex Shader
//--------------------------------------------------------------------------------------
PS_INPUT VS( VS_INPUT input )
{
	PS_INPUT output = (PS_INPUT)0;

	float4 projected=mul(float4(input.pos,1),projection);
	output.pos = projected;		
	output.color = unrealColor(input.color,input.flags);
	output.flags = input.flags;
	output.pos.y =  -output.pos.y;
	return output;
}

//Vertex shader that generates a full screen quad with texcoords g_Rom vertIDs
//To use draw 3 vertices with primitive type triangle strip
PS_SIMPLE VS_FullScreenQuad( uint id : SV_VertexID )
{
    PS_SIMPLE output;

    float2 tex = float2( (id << 1) & 2, id & 2 );
    output.pos = float4(tex * float2( 2.0f, -2.0f ) + float2( -1.0f, 1.0f) , 0.0f, 1.0f );
    
    return output;
}



//--------------------------------------------------------------------------------------
// Pixel Shaders
//--------------------------------------------------------------------------------------
PS_OUTPUT2 PS( PS_INPUT input)
{
	PS_OUTPUT2 output;
	
	output.color= input.color;
#if(HBAO_ENABLED==1)
	#if(SAMPLES>1)
	output.normal = texNormal.Load( int2(input.pos.xy), 0);
	#else
	output.normal = texNormal.Load( int3(input.pos.xy, 0));
	#endif
	output.normal.a = 0.5f-input.color.a*0.5f;
#endif

	return output;
}

PS_OUTPUT PS_Normal( PS_SIMPLE input)
{
	PS_OUTPUT output;
	
	#if(SAMPLES>1)
	output.color= texNormal.Load( int2(input.pos.xy), 0);
	#else
	output.color= texNormal.Load( int3(input.pos.xy, 0));
	#endif


	return output;
}


//--------------------------------------------------------------------------------------
technique11 Render
{
	pass P0
	{
		SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( NULL );
		SetHullShader(0);
		SetDomainShader(0);
		SetPixelShader( CompileShader( ps_5_0, PS() ) );
		
		SetRasterizerState(rstate_Default);
	}
	pass P1
	{
		SetVertexShader( CompileShader( vs_5_0, VS_FullScreenQuad() ) );
		SetGeometryShader( NULL );
		SetHullShader(0);
		SetDomainShader(0);
		SetPixelShader( CompileShader( ps_5_0, PS_Normal() ) );
		
		SetRasterizerState(rstate_Default);
	}
}