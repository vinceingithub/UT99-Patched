Texture2D<float3> tRandom;
Texture2D<float>  tLinDepth;
Texture2D<float4> tNormal;

#define M_PI 3.14159265f

SamplerState samNearest
{
    Filter   = MIN_MAG_MIP_POINT;
    AddressU = Clamp;
    AddressV = Clamp;
};

//----------------------------------------------------------------------------------
DepthStencilState DisableDepth
{
    DepthEnable    = FALSE;
    DepthWriteMask = ZERO;
};

BlendState DisableBlend
{
    BlendEnable[0] = false;
};

//----------------------------------------------------------------------------------
cbuffer cb0
{
	float  g_AspectRatio;
	float  g_InvAspectRatio;
	float2 g_FocalLen;
	float2 g_InvFocalLen;
	float2 g_InvResolution;
	float2 g_Resolution;
	float2 g_ZLinParams;
    float  g_NumSteps;
    float  g_NumDir;
    float  g_R;
    float  g_inv_R;
    float  g_sqr_R;
    float  g_AngleBias;
    float  g_TanAngleBias;
    float  g_Attenuation;
    float  g_Contrast;
}

//----------------------------------------------------------------------------------
struct VSOut
{
    float4 pos   : SV_Position;
    float2 tex   : TEXCOORD0;
    float2 texUV : TEXCOORD1;
};

VSOut FullScreenQuadVS( uniform bool useAutoRadius, uint id : SV_VertexID )
{
    VSOut output;
    float2 tex = float2( (id << 1) & 2, id & 2 );
    output.tex = tex * float2( 2.0f, -2.0f ) + float2( -1.0f, 1.0f);
    output.pos = float4( output.tex, 0.0f, 1.0f );
    output.tex /= g_FocalLen;
    
    output.texUV = float2( (id << 1) & 2, id & 2 );
   
    return output;
}

//----------------------------------------------------------------------------------
float tangent(float3 P, float3 S)
{
    return (P.z - S.z) / length(S.xy - P.xy);
}

//----------------------------------------------------------------------------------
float3 uv_to_eye(float2 uv, float eye_z)
{
    uv = (uv * float2(2.0, -2.0) - float2(1.0, -1.0));
    return float3(uv * g_InvFocalLen * eye_z, eye_z);
}

//----------------------------------------------------------------------------------
float3 fetch_eye_pos(float2 uv)
{
	float z = tLinDepth.SampleLevel(samNearest, uv, 0);
    return uv_to_eye(uv, z);
}

//----------------------------------------------------------------------------------
float3 tangent_eye_pos(float2 uv, float4 tangentPlane)
{
    float3 V = fetch_eye_pos(uv);
    float NdotV = dot(tangentPlane.xyz, V);
    if (NdotV < 0.0) V *= (tangentPlane.w / NdotV);
    return V;
}

float length2(float3 v) { return dot(v, v); } 

//----------------------------------------------------------------------------------
float3 min_diff(float3 P, float3 Pr, float3 Pl)
{
    float3 V1 = Pr - P;
    float3 V2 = P - Pl;
    return (length2(V1) < length2(V2)) ? V1 : V2;
}

//----------------------------------------------------------------------------------
float falloff(float r)
{
    return 1.0f - g_Attenuation*r*r;
}

//----------------------------------------------------------------------------------
float2 snap_uv_offset(float2 uv)
{
    return round(uv * g_Resolution) * g_InvResolution;
}

//----------------------------------------------------------------------------------
float invlength(float2 v)
{
    return rsqrt(dot(v,v));
}

//----------------------------------------------------------------------------------
float tangent(float3 T)
{
    return -T.z * invlength(T.xy);
}

//----------------------------------------------------------------------------------
float biased_tangent(float3 T)
{
    float phi = atan(tangent(T)) + g_AngleBias;
    return tan(min(phi, M_PI*0.5));
}

//----------------------------------------------------------------------------------
float AccumulatedHorizonOcclusion(float2 deltaUV, float2 uv0, float3 P, float numSteps, float randstep,float3 dPdu,float3 dPdv )
{
    float2 uv = uv0 + snap_uv_offset( randstep * deltaUV );
    deltaUV = snap_uv_offset( deltaUV );
	float3 T = deltaUV.x * dPdu + deltaUV.y * dPdv;
    float tanH = biased_tangent(T);
    float sinH = tanH / sqrt(1.0f + tanH*tanH);
	
    float ao = 0;
    for(float j = 1; j <= numSteps; ++j) 
	{
        uv += deltaUV;
        float3 S = fetch_eye_pos(uv);
        
        float d2  = length2(S - P);
        if (d2 < g_sqr_R) 
		{
            float tanS = tangent(P, S);
            [branch]
            if(tanS > tanH) 
			{
                float sinS = tanS / sqrt(1.0f + tanS*tanS);
                float r = sqrt(d2) * g_inv_R;
                ao += falloff(r) * (sinS - sinH);

                tanH = tanS;
                sinH = sinS;
            }
        } 
    }

    return ao;
}

//----------------------------------------------------------------------------------
float2 rotate_direction(float2 Dir, float2 CosSin)
{
    return float2(Dir.x*CosSin.x - Dir.y*CosSin.y, 
                  Dir.x*CosSin.y + Dir.y*CosSin.x);
}

//----------------------------------------------------------------------------------
float4 HBAO_PS(VSOut IN ) : SV_TARGET
{
    float3 P = fetch_eye_pos(IN.texUV);
    float2 step_size = 0.5 * g_R  * g_FocalLen / P.z;
	float aoStrength=1.0f;

    // Early out if the projected radius is smaller than 1 pixel.
    float numSteps = min ( g_NumSteps, min(step_size.x * g_Resolution.x, step_size.y * g_Resolution.y));
    if( numSteps < 1.0 ) return 1.0;
    step_size = step_size / ( numSteps + 1 );

    float3 Pr, Pl, Pt, Pb;
    float4 tangentPlane;

	float4 sampledNorm = tNormal.SampleLevel(samNearest, IN.texUV, 0);
    float3 N = normalize(sampledNorm).xyz;
	aoStrength = normalize(sampledNorm).w;
	if (aoStrength < 0.001f)
		return 1.0f;
	tangentPlane = float4(N, dot(P, N));
	Pr = tangent_eye_pos(IN.texUV + float2(g_InvResolution.x, 0), tangentPlane);
	Pl = tangent_eye_pos(IN.texUV + float2(-g_InvResolution.x, 0), tangentPlane);
	Pt = tangent_eye_pos(IN.texUV + float2(0, g_InvResolution.y), tangentPlane);
	Pb = tangent_eye_pos(IN.texUV + float2(0, -g_InvResolution.y), tangentPlane);
    
    float3 dPdu = min_diff(P, Pr, Pl);
    float3 dPdv = min_diff(P, Pt, Pb) * (g_Resolution.y * g_InvResolution.x);

    float3 rand = tRandom.Load(int3((int)IN.pos.x&63, (int)IN.pos.y&63, 0)).xyz;

    float ao = 0;
    float d;
    float alpha = 2.0f * M_PI / g_NumDir;

	for (d = 0; d < g_NumDir; d++)
	{
		float angle = alpha * d;
		float2 dir = float2(cos(angle), sin(angle));
		float2 deltaUV = rotate_direction(dir, rand.xy) * step_size.xy;
		ao += AccumulatedHorizonOcclusion(deltaUV, IN.texUV, P, numSteps, rand.z, dPdu, dPdv);
	}
    return 1.0 - (ao*aoStrength) / g_NumDir * g_Contrast;
}


//----------------------------------------------------------------------------------
technique11 HBAO_TECHNIQUE
{
    pass p0
    {
        SetVertexShader( CompileShader( vs_5_0, FullScreenQuadVS(false) ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, HBAO_PS() ) );
        SetBlendState( DisableBlend, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetDepthStencilState( DisableDepth, 0 );
    }
}