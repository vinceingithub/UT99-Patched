/**
Shader for 3D models
*/

#include "common.fxh"
#include "unrealpool.fxh"

cbuffer PerScene
{
	matrix projection;
};
Texture2D texDiffuse;

struct VS_INPUT
{	
	float3 pos : POSITION;
	float3 normal : NORMAL0;
	float4 color: COLOR0;
	float4 fog: COLOR1;
	float2 tex: TEXCOORD0;
	uint flags: BLENDINDICES; //flags are set per poly instead of as global state so no commits are necessary when changing them
};


struct PS_INPUT
{	
	float4 pos : SV_POSITION;
	float3 origPos : POSITION;
	centroid float4 color: COLOR0;
	centroid float4 fog: COLOR1;
	float2 tex: TEXCOORD0;
	uint flags: BLENDINDICES;
};

cbuffer Fog //Rune object fog
{
	float fogDist;
	float4 fogColor;
}


//--------------------------------------------------------------------------------------
// Vertex Shader
//--------------------------------------------------------------------------------------
PS_INPUT VS( VS_INPUT input )
{
	PS_INPUT output = (PS_INPUT)0;

	/*
	Position
	*/
	float4 projected=mul(float4(input.pos,1),projection);
	output.pos = projected;

	output.origPos = input.pos;
	
	
	output.color = unrealColor(input.color,input.flags);
	
	
	output.fog = unrealVertexFog(input.fog, input.flags);
	
	/*
	Misc
	*/
	output.tex = input.tex;
	output.flags = input.flags;
	
	//d3d vs unreal coords
	output.pos.y =  -output.pos.y;
	return output;
}


//--------------------------------------------------------------------------------------
// Pixel Shader
//--------------------------------------------------------------------------------------
PS_OUTPUT2 PS( PS_INPUT input)
{
	PS_OUTPUT2 output;
	//Initialize all textures to have no influence
	 
	float4 fog = input.fog;
	output.color= input.color;

	#if(HBAO_ENABLED==1)
		output.normal.xyz = normalize(cross(ddx(input.pos.xyz), ddy(input.pos.xyz)));
		if(input.flags&(PF_Unlit|PF_Translucent))
			output.normal.w = 0;
		else if (fogDist > 0)
			output.normal.w=1.0- saturate(input.pos.w / fogDist);
		else
			output.normal.w = 1.0f;
	#endif
		
	float4 diffuse = texDiffuse.SampleBias(sam,input.tex,LODBIAS);
	float4 diffusePoint = texDiffuse.SampleBias(samPoint,input.tex,LODBIAS);
	if (input.flags&PF_Modulated)//proj shadow fix
		output.color = diffusePoint;
	else
		output.color *= diffuseTexture(diffuse, diffusePoint, input.flags);
	output.color+=fog;
	
	//Rune object fogging
	if(fogDist>0)
		output.color = lerp(output.color,fogColor,saturate(input.pos.w/fogDist));

	#if(HDR_ENABLED==1)
	if(input.flags&PF_Unlit)
		output.color.rgb=increaseDynamicRange(output.color.rgb,input.flags);
	#endif
	return output;
}


//--------------------------------------------------------------------------------------
technique11 Render
{
	pass Standard
	{
		SetVertexShader( CompileShader( vs_5_0, VS() ) );
		SetGeometryShader( NULL );
		SetPixelShader( CompileShader( ps_5_0, PS() ) );
		
		SetRasterizerState(rstate_Default);
	}
}