/**
Shader for 3D models
*/

#include "common.fxh"
#include "unrealpool.fxh"
#include "states.fx"

cbuffer cbTess
{
	matrix projection;
	float tesselationFactor;
	float tesselationAmount;
};
Texture2D texDiffuse;

struct VS_INPUT
{	
	float3 pos : POSITION0;
	float3 normal : NORMAL0;
	float4 color: COLOR0;
	float4 fog: COLOR1;
	float2 tex: TEXCOORD0;
	uint flags: BLENDINDICES; 
};

struct HS_INPUT
{
	float3 pos : POSITION0;
	float3 normal : NORMAL0;
	float4 color : COLOR0;
	float4 fog: COLOR1;
	float2 tex: TEXCOORD0;
	uint flags: BLENDINDICES;
};

struct HS_OUTPUT
{
	float3 pos : POSITION0;
	float3 normal : NORMAL0;
	float4 color : COLOR0;
	float4 fog: COLOR1;
	float2 tex: TEXCOORD0;
	uint flags: BLENDINDICES;
};

struct PS_INPUT
{	
	float4 pos : SV_POSITION;
	centroid float4 color: COLOR0;
	centroid float4 fog: COLOR1;
	float2 tex: TEXCOORD0;
	uint flags: BLENDINDICES;
	float3 origPos : POSITION0;
};

struct ConstantOutputType
{
	float edges[3] : SV_TessFactor;
	float inside : SV_InsideTessFactor;
};

cbuffer Fog //Rune object fog
{
	float fogDist;
	float4 fogColor;
}

// orthogonal projection of q onto the plane defined by position and normal
float3 PI(HS_OUTPUT q, HS_OUTPUT I)
{
	float3 q_minus_p = q.pos - I.pos;
	return q.pos - dot(q_minus_p, I.normal) * I.normal;
}

//--------------------------------------------------------------------------------------
// Patch Constant Function
//--------------------------------------------------------------------------------------
ConstantOutputType PatchConstantFunction(InputPatch<HS_INPUT, 3> inputPatch, uint patchId : SV_PrimitiveID)
{
	ConstantOutputType output;

	output.edges[0] = tesselationAmount;
	output.edges[1] = tesselationAmount;
	output.edges[2] = tesselationAmount;
	output.inside = tesselationAmount;

	return output;
}
//--------------------------------------------------------------------------------------
// Vertex Shader
//--------------------------------------------------------------------------------------
HS_INPUT VS( VS_INPUT input )
{
	HS_INPUT output;

	output.pos = input.pos;
	//d3d vs unreal coords
	output.pos.y = -output.pos.y;
	output.color = unrealColor(input.color,input.flags);
	output.fog = unrealVertexFog(input.fog, input.flags);
	output.tex = input.tex;
	output.flags = input.flags;
	float3 norm = input.normal;
	norm.y = -norm.y;
	output.normal = normalize(norm);
	
	return output;
}
//--------------------------------------------------------------------------------------
// Hull shader
//--------------------------------------------------------------------------------------
[domain("tri")]
[partitioning("integer")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(3)]
[maxtessfactor(8.0f)]
[patchconstantfunc("PatchConstantFunction")]
HS_OUTPUT HS(InputPatch<HS_INPUT, 3> patch, uint pointId : SV_OutputControlPointID, uint patchId : SV_PrimitiveID)
{
	HS_OUTPUT output;

	output.pos = patch[pointId].pos;
	output.color = patch[pointId].color;
	output.fog = patch[pointId].fog;
	output.tex = patch[pointId].tex;
	output.flags = patch[pointId].flags;
	output.normal = patch[pointId].normal;

	return output;
}
//--------------------------------------------------------------------------------------
// Domain shader
//--------------------------------------------------------------------------------------
[domain("tri")]
PS_INPUT DS(ConstantOutputType input, float3 uvwCoord : SV_DomainLocation, const OutputPatch<HS_OUTPUT, 3> patch)
{
	PS_INPUT output;
	float fU = uvwCoord.x;//fW->fU, fU->fV,fV->fW
	float fV = uvwCoord.y;
	float fW = uvwCoord.z;
	// Precompute squares 
	float fUU = fU * fU;
	float fVV = fV * fV;
	float fWW = fW * fW;
	// Determine the position of the new vertex.
	float3 vertexPosition;
	if(tesselationFactor<0.001f)//rune shadows fix
		vertexPosition =patch[0].pos * fU + patch[1].pos * fV + patch[2].pos * fW;
	else
	{
		vertexPosition = patch[0].pos * fUU + patch[1].pos * fVV + patch[2].pos * fWW + fU * fV * (PI(patch[0], patch[1]) + PI(patch[1], patch[0])) + fV * fW * (PI(patch[1], patch[2]) + PI(patch[2], patch[1])) + fW * fU * (PI(patch[2], patch[0]) + PI(patch[0], patch[2]));
		vertexPosition = vertexPosition * tesselationFactor + (patch[0].pos * fU + patch[1].pos * fV + patch[2].pos * fW)*(1.0f - tesselationFactor);
	}
	output.pos =  mul(float4(vertexPosition, 1), projection);
	output.color = fU * patch[0].color + fV * patch[1].color + fW * patch[2].color;
	output.fog = patch[0].fog;
	output.tex = fU * patch[0].tex + fV * patch[1].tex + fW * patch[2].tex;
	output.flags = patch[0].flags;
	output.origPos = vertexPosition;

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
	if (input.flags&(PF_Unlit|PF_Translucent))
		output.normal.w = 0;
	else if (fogDist > 0)
		output.normal.w = 1.0 - saturate(input.pos.w / fogDist);
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

	//Compensate for darker HDR environments, but don't make objects lighter (get glowing white coats, etc)
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
		SetHullShader(CompileShader(hs_5_0, HS()));
		SetDomainShader(CompileShader(ds_5_0, DS()));
		SetGeometryShader( 0 );
		SetPixelShader( CompileShader( ps_5_0, PS() ) );
		
		SetRasterizerState(rstate_Default);
	}
}