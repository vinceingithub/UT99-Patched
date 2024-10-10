#include "common.fxh"
#include "postprocessing.fxh"


/** read MSAA pixel */
#if(SAMPLES>1)
float4 directCopy(float2 coords, Texture2DMS<float4,SAMPLES> tex)
{
		float4 color=(float4)0;
		[unroll] for(int i=0;i<SAMPLES;i++)
		{
			color += tex.Load(coords,i);		
		}
		color/=SAMPLES;
		return color;
}
Texture2DMS<float4,SAMPLES> inputTextureMSAA;
#else
float4 directCopy(int3 coords, Texture2D<float4> tex)
{
		float4 color=(float4)0;
		color = tex.Load(coords);		
		return color;
}
Texture2D<float4> inputTextureMSAA;
#endif

PS_OUTPUT_SIMPLE PS_first(PS_INPUT_SIMPLE input)
{
	PS_OUTPUT_SIMPLE output = (PS_OUTPUT_SIMPLE)0;
	#if(SAMPLES>1)			
	float2 coords = input.pos.xy;	
	#else
	int3 coords = int3(input.pos.xy,0);		
	#endif
	output.color=directCopy(coords,inputTextureMSAA);
	#if((HBAO_ENABLED==0) && (HDR_ENABLED==0))
	output.color.rgb += flash.rgb;
	#endif
	return output;
}


technique11 Render
{
	pass P0
	{
		SetVertexShader( CompileShader( vs_5_0, VS_identity() ) );	
		SetGeometryShader( 0 );
		SetHullShader(0);
		SetDomainShader(0);
		SetPixelShader( CompileShader( ps_5_0, PS_first() ) );
		
	}
}