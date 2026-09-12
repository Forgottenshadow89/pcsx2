// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#include "GSMTLShaderCommon.h"

using namespace metal;

constant bool BILN      [[function_constant(GSMTLConstantIndex_BILN)]];
constant bool DEPTH_OUT [[function_constant(GSMTLConstantIndex_DEPTH_OUT)]];
constant bool COLOR_OUT = !DEPTH_OUT;

struct ConvertVSIn
{
	vector_float2 position  [[attribute(0)]];
	vector_float2 texcoord0 [[attribute(1)]];
};

struct ImGuiVSIn
{
	vector_float2 position  [[attribute(0)]];
	vector_float2 texcoord0 [[attribute(1)]];
	vector_half4  color     [[attribute(2)]];
};

struct ImGuiShaderData
{
	float4 p [[position]];
	float2 t;
	half4  c;
};

template <typename Format>
struct DirectReadTextureIn
{
	texture2d<Format> tex [[texture(GSMTLTextureIndexNonHW)]];
	vec<Format, 4> read(float4 pos)
	{
		return tex.read(uint2(pos.xy));
	}
};

vertex ConvertShaderData fs_triangle(uint vid [[vertex_id]])
{
	ConvertShaderData out;
	out.p = float4(vid & 1 ? 3 : -1, vid & 2 ? 3 : -1, 0, 1);
	out.t = float2(vid & 1 ? 2 : 0, vid & 2 ? -1 : 1);
	return out;
}

vertex ConvertShaderData vs_convert(ConvertVSIn in [[stage_in]])
{
	ConvertShaderData out;
	out.p = float4(in.position, 0, 1);
	out.t = in.texcoord0;
	return out;
}

vertex ImGuiShaderData vs_imgui(ImGuiVSIn in [[stage_in]], constant float4& cb [[buffer(GSMTLBufferIndexUniforms)]])
{
	ImGuiShaderData out;
	out.p = float4(in.position * cb.xy + cb.zw, 0, 1);
	out.t = in.texcoord0;
	out.c = in.color;
	return out;
}

fragment float4 ps_copy(ConvertShaderData data [[stage_in]], ConvertPSRes res)
{
	return res.sample(data.t);
}

fragment ushort ps_convert_rgb5a1_16bits(ConvertShaderData data [[stage_in]], ConvertPSRes res)
{
	float4 c = res.sample(data.t);
	uint4 cu = uint4(c * 255.f + 0.5f);
	return (cu.x >> 3) | ((cu.y << 2) & 0x03e0) | ((cu.z << 7) & 0x7c00) | ((cu.w << 8) & 0x8000);
}

fragment float4 ps_copy_fs(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	return tex.read(p);
}

fragment float4 ps_clear(float4 p [[position]], constant float4& color [[buffer(GSMTLBufferIndexUniforms)]])
{
	return color;
}

fragment void ps_datm1(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	if (tex.read(p).a < (127.5f / 255.f))
		discard_fragment();
}

fragment void ps_datm0_rta_correction(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	if (tex.read(p).a > (254.5f / 255.f))
		discard_fragment();
}

fragment void ps_datm1_rta_correction(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	if (tex.read(p).a < (254.5f / 255.f))
		discard_fragment();
}

fragment void ps_datm0(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	if (tex.read(p).a > (127.5f / 255.f))
		discard_fragment();
}

fragment float4 ps_primid_init_datm1(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	return tex.read(p).a < (127.5f / 255.f) ? GSShader::PRIMID_MIN : GSShader::PRIMID_MAX;
}

fragment float4 ps_primid_init_datm0(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	return tex.read(p).a > (127.5f / 255.f) ? GSShader::PRIMID_MIN : GSShader::PRIMID_MAX;
}

fragment float4 ps_primid_rta_init_datm1(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	return tex.read(p).a < (254.5f / 255.f) ? GSShader::PRIMID_MIN : GSShader::PRIMID_MAX;
}

fragment float4 ps_primid_rta_init_datm0(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	return tex.read(p).a > (254.5f / 255.f) ? GSShader::PRIMID_MIN : GSShader::PRIMID_MAX;
}

fragment float4 ps_rta_correction(ConvertShaderData data [[stage_in]], ConvertPSRes res)
{
	float4 in = res.sample(data.t);
	return float4(in.rgb, in.a / (128.25f / 255.0f));
}

fragment float4 ps_rta_decorrection(ConvertShaderData data [[stage_in]], ConvertPSRes res)
{
	float4 in = res.sample(data.t);
	return float4(in.rgb, in.a * (128.25f / 255.0f));
}

fragment float4 ps_colclip_init(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	float4 in = tex.read(p);
	return float4(round(in.rgb * 255.f) / 65535.f, in.a);
}

fragment float4 ps_colclip_resolve(float4 p [[position]], DirectReadTextureIn<float> tex)
{
	float4 in = tex.read(p);
	return float4(float3(uint3(in.rgb * 65535.5f) & 255) / 255.f, in.a);
}

fragment float4 ps_filter_transparency(ConvertShaderData data [[stage_in]], ConvertPSRes res)
{
	float4 c = res.sample(data.t);
	return float4(c.rgb, 1.0);
}

fragment uint ps_convert_depth32_32bits(ConvertShaderData data [[stage_in]], ConvertPSDepthRes res)
{
	return uint(0x1p32 * res.sample(data.t));
}

fragment float4 ps_convert_depth32_rgba8(ConvertShaderData data [[stage_in]], ConvertPSDepthRes res)
{
	return convert_depth32_rgba8(res.sample(data.t)) / 255.f;
}

fragment float4 ps_convert_depth16_rgb5a1(ConvertShaderData data [[stage_in]], ConvertPSDepthRes res)
{
	return convert_depth16_rgba8(res.sample(data.t)) / 255.f;
}

fragment float4 ps_downsample_copy(ConvertShaderData data [[stage_in]],
	texture2d<float> texture [[texture(GSMTLTextureIndexNonHW)]],
	constant GSMTLDownsamplePSUniform& uniform [[buffer(GSMTLBufferIndexUniforms)]])
{
	uint2 coord = max(uint2(data.p.xy) * uniform.downsample_factor, uniform.clamp_min);

	float4 result = float4(0.0, 0.0, 0.0, 0.0);
	for (uint yoff = 0; yoff < uniform.downsample_factor; yoff++)
	{
		for (uint xoff = 0; xoff < uniform.downsample_factor; xoff++)
			result += texture.read(coord + uint2(xoff * uniform.step_multiplier, yoff * uniform.step_multiplier), 0);
	}
	result /= uniform.weight;
	return result;
}

static float rgba8_to_depth32(half4 unorm)
{
	return float(as_type<uint>(uchar4(unorm * 255.5h))) * 0x1p-32f;
}

static float rgba8_to_depth24(half4 unorm)
{
	return rgba8_to_depth32(half4(unorm.rgb, 0));
}

static float rgba8_to_depth16(half4 unorm)
{
	return float(as_type<ushort>(uchar2(unorm.rg * 255.5h))) * 0x1p-32f;
}

static float rgb5a1_to_depth16(half4 unorm)
{
	uint4 cu = uint4(unorm * 255.5h);
	uint out = (cu.x >> 3) | ((cu.y << 2) & 0x03e0) | ((cu.z << 7) & 0x7c00) | ((cu.w << 8) & 0x8000);
	return float(out) * 0x1p-32f;
}

struct DepthOrColorOut
{
	float color [[color(0), function_constant(COLOR_OUT)]];
	float depth [[depth(any), function_constant(DEPTH_OUT)]];
	DepthOrColorOut(float value): color(value), depth(value) {}
};

struct ConvertPSDepthOrColorRes
{
	texture2d<float> texture [[texture(GSMTLTextureIndexNonHW)]];
	sampler s [[sampler(0)]];
	float sample(float2 coord)
	{
		return texture.sample(s, coord).x;
	}
};

struct ConvertToDepthRes
{
	texture2d<half> texture [[texture(GSMTLTextureIndexNonHW)]];
	half4 sample(float2 coord)
	{
		// RGBA bilinear on a depth texture is a bad idea, and should never be used
		// Might as well let the compiler optimize a bit by telling it exactly what sampler we'll be using here
		constexpr sampler s(coord::normalized, filter::nearest, address::clamp_to_edge);
		return texture.sample(s, coord);
	}

	/// Manual bilinear sampling where we do the bilinear *after* rgba → depth conversion
	template <float (&convert)(half4)>
	float sample_biln(float2 coord)
	{
		uint2 dimensions = uint2(texture.get_width(), texture.get_height());
		float2 top_left_f = coord * float2(dimensions) - 0.5f;
		int2 top_left = int2(floor(top_left_f));
		uint4 coords = uint4(clamp(int4(top_left, top_left + 1), 0, int2(dimensions - 1).xyxy));
		float2 mix_vals = fract(top_left_f);

		float depthTL = convert(texture.read(coords.xy));
		float depthTR = convert(texture.read(coords.zy));
		float depthBL = convert(texture.read(coords.xw));
		float depthBR = convert(texture.read(coords.zw));
		return floor(mix(mix(depthTL, depthTR, mix_vals.x), mix(depthBL, depthBR, mix_vals.x), mix_vals.y) * 0x1p32) * 0x1p-32;
	}

	template <float (&convert)(half4)>
	float sample_maybe_biln(float2 coord)
	{
		if (BILN)
			return sample_biln<convert>(coord);
		else
			return convert(sample(coord));
	}
};

static float4 primid_to_rgba8(float p)
{
	return float4(as_type<uchar4>(p)) / 255.f;
}

fragment float4 ps_convert_primid_rgba8(ConvertShaderData data [[stage_in]], ConvertPSDepthOrColorRes res)
{
	return primid_to_rgba8(res.sample(data.t));
}

fragment DepthOrColorOut ps_depth_copy(ConvertShaderData data [[stage_in]], ConvertPSDepthOrColorRes res)
{
	return res.sample(data.t);
}

static float depth32_to_depth24(float d)
{
	return float(uint(d * exp2(32.0f)) & 0xffffff) * exp2(-32.0f); 
}

fragment DepthOrColorOut ps_convert_depth32_depth24(ConvertShaderData data [[stage_in]], ConvertPSDepthOrColorRes res)
{
	// Truncates depth value to 24bits
	return depth32_to_depth24(res.sample(data.t));
}

fragment DepthOrColorOut ps_convert_rgba8_depth32(ConvertShaderData data [[stage_in]], ConvertToDepthRes res)
{
	return res.sample_maybe_biln<rgba8_to_depth32>(data.t);
}

fragment DepthOrColorOut ps_convert_rgba8_depth24(ConvertShaderData data [[stage_in]], ConvertToDepthRes res)
{
	return res.sample_maybe_biln<rgba8_to_depth24>(data.t);
}

fragment DepthOrColorOut ps_convert_rgba8_depth16(ConvertShaderData data [[stage_in]], ConvertToDepthRes res)
{
	return res.sample_maybe_biln<rgba8_to_depth16>(data.t);
}

fragment DepthOrColorOut ps_convert_rgb5a1_depth16(ConvertShaderData data [[stage_in]], ConvertToDepthRes res)
{
	return res.sample_maybe_biln<rgb5a1_to_depth16>(data.t);
}

fragment float4 ps_convert_rgb5a1_8i(ConvertShaderData data [[stage_in]], DirectReadTextureIn<float> res,
	constant GSMTLIndexedConvertPSUniform& uniform [[buffer(GSMTLBufferIndexUniforms)]])
{
	// Convert a RGB5A1 texture into a 8 bits packed texture
	// Input column: 16x2 RGB5A1 pixels
	// 0: 16 RGBA
	// 1: 16 RGBA
	// Output column: 16x4 Index pixels
	// 0: 16 R5G2
	// 1: 16 R5G2
	// 2: 16 G2B5A1
	// 3: 16 G2B5A1
	uint2 pos = uint2(data.p.xy);

	// Collapse separate R G B A areas into their base pixel
	uint2 column = (pos & ~uint2(0u, 3u)) / uint2(1,2);
	uint2 subcolumn = (pos & uint2(0u, 1u));
	column.x -= (column.x / 128) * 64;
	column.y += (column.y / 32) * 32;

	// Deal with swizzling differences
	if ((uniform.psm & 0x8) != 0) // PSMCT16S
	{
		if ((pos.x & 32) != 0)
		{
			column.y += 32; // 4 columns high times 4 to get bottom 4 blocks
			column.x &= ~32;
		}
		
		if ((pos.x & 64) != 0)
		{
			column.x -= 32;
		}
		
		if (((pos.x & 16) != 0) != ((pos.y & 16) != 0))
		{
			column.x ^= 16; 
			column.y ^= 8;
		}
		
		if ((uniform.psm & 0x30) != 0) // PSMZ16S - Untested but hopefully ok if anything uses it.
		{
			column.x ^= 32;
			column.y ^= 16;
		}
	}
	else // PSMCT16
	{
		if ((pos.y & 32) != 0)
		{
			column.y -= 16;
			column.x += 32;
		}
		
		if ((pos.x & 96) != 0)
		{
			uint multi = (pos.x & 96) / 32;
			column.y += 16 * multi; // 4 columns high times 4 to get bottom 4 blocks
			column.x -= (pos.x & 96);
		}
		
		if (((pos.x & 16) != 0) != ((pos.y & 16) != 0))
		{
			column.x ^= 16; 
			column.y ^= 8;
		}
		
		if ((uniform.psm & 0x30) != 0) // PSMZ16 - Untested but hopefully ok if anything uses it.
		{
			column.x ^= 32;
			column.y ^= 32;
		}
	}
	
	uint2 coord = column | subcolumn;

	// Compensate for potentially differing page pitch.
	uint2 block_xy = coord / uint2(64, 64);
	uint block_num = (block_xy.y * (uniform.dbw / 128)) + block_xy.x;
	uint2 block_offset = uint2((block_num % (uniform.sbw / 64)) * 64, (block_num / (uniform.sbw / 64)) * 64);
	coord = (coord % uint2(64, 64)) + block_offset;

	// Apply offset to cols 1 and 2
	uint is_col23 = pos.y & 4;
	uint is_col13 = pos.y & 2;
	uint is_col12 = is_col23 ^ (is_col13 << 1);
	coord.x ^= is_col12; // If cols 1 or 2, flip bit 3 of x

	if (any(floor(uniform.scale) != uniform.scale))
		coord = uint2(float2(coord) * uniform.scale);
	else
		coord = mul24(coord, uint2(uniform.scale));

	float4 pixel = res.tex.read(coord);
	
	uint4 denorm_c = (uint4)(pixel * 255.5f);
	if ((pos.y & 2u) == 0u)
	{
		uint red = (denorm_c.r >> 3) & 0x1Fu;
		uint green = (denorm_c.g >> 3) & 0x1Fu;
		float sel0 = (float)(((green << 5) | red) & 0xFF) / 255.0f;
		
		return float4(sel0);
	}
	else
	{
		uint green = (denorm_c.g >> 3) & 0x1Fu;
		uint blue = (denorm_c.b >> 3) & 0x1Fu;
		uint alpha = denorm_c.a & 0x80u;
		float sel0 = (float)((alpha | (blue << 2) | (green >> 3)) & 0xFF) / 255.0f;

		return float4(sel0);
	}
}

fragment float4 ps_convert_rgba_8i(ConvertShaderData data [[stage_in]], DirectReadTextureIn<float> res,
	constant GSMTLIndexedConvertPSUniform& uniform [[buffer(GSMTLBufferIndexUniforms)]])
{
	// Convert a RGBA texture into a 8 bits packed texture
	// Input column: 8x2 RGBA pixels
	// 0: 8 RGBA
	// 1: 8 RGBA
	// Output column: 16x4 Index pixels
	// 0: 8 R | 8 B
	// 1: 8 R | 8 B
	// 2: 8 G | 8 A
	// 3: 8 G | 8 A
	uint2 pos = uint2(data.p.xy);

	// Collapse separate R G B A areas into their base pixel
	uint2 block = (pos & ~uint2(15, 3)) >> 1;
	uint2 subblock = pos & uint2(7, 1);
	uint2 coord = block | subblock;

	// Compensate for potentially differing page pitch.
	uint2 block_xy = coord / uint2(64, 32);
	uint block_num = (block_xy.y * (uniform.dbw / 128)) + block_xy.x;
	uint2 block_offset = uint2((block_num % (uniform.sbw / 64)) * 64, (block_num / (uniform.sbw / 64)) * 32);
	coord = (coord % uint2(64, 32)) + block_offset;

	// Apply offset to cols 1 and 2
	uint is_col23 = pos.y & 4;
	uint is_col13 = pos.y & 2;
	uint is_col12 = is_col23 ^ (is_col13 << 1);
	coord.x ^= is_col12; // If cols 1 or 2, flip bit 3 of x

	if (any(floor(uniform.scale) != uniform.scale))
		coord = uint2(float2(coord) * uniform.scale);
	else
		coord = mul24(coord, uint2(uniform.scale));

	float4 pixel = res.tex.read(coord);
	float2 sel0 = (pos.y & 2) == 0 ? pixel.rb : pixel.ga;
	float  sel1 = (pos.x & 8) == 0 ? sel0.x : sel0.y;
	return float4(sel1);
}

fragment float4 ps_convert_clut_4(ConvertShaderData data [[stage_in]],
	texture2d<float> texture [[texture(GSMTLTextureIndexNonHW)]],
	constant GSMTLCLUTConvertPSUniform& uniform [[buffer(GSMTLBufferIndexUniforms)]])
{
	// CLUT4 is easy, just two rows of 8x8.
	uint index = uint(data.p.x) + uniform.doffset;
	uint2 pos = uint2(index % 8, index / 8);

	uint2 final = uint2(float2(uniform.offset + pos) * uniform.scale);
	return texture.read(final);
}

fragment float4 ps_convert_clut_8(ConvertShaderData data [[stage_in]],
	texture2d<float> texture [[texture(GSMTLTextureIndexNonHW)]],
	constant GSMTLCLUTConvertPSUniform& uniform [[buffer(GSMTLBufferIndexUniforms)]])
{
	uint index = min(uint(data.p.x) + uniform.doffset, 255u);

	// CLUT is arranged into 8 groups of 16x2, with the top-right and bottom-left quadrants swapped.
	// This can probably be done better..
	uint subgroup = (index / 8) % 4;
	uint2 pos;
	pos.x = (index % 8) + ((subgroup >= 2) ? 8 :0u);
	pos.y = ((index / 32u) * 2u) + (subgroup % 2u);

	uint2 final = uint2(float2(uniform.offset + pos) * uniform.scale);
	return texture.read(final);
}

fragment float4 ps_yuv(ConvertShaderData data [[stage_in]], ConvertPSRes res,
	constant GSMTLConvertPSUniform& uniform [[buffer(GSMTLBufferIndexUniforms)]])
{
	float4 i = res.sample(data.t);
	float4 o = float4(0);

	// Value from GS manual
	const float3x3 rgb2yuv =
	{
		{0.587, -0.311, -0.419},
		{0.114,  0.500, -0.081},
		{0.299, -0.169,  0.500}
	};

	float3 yuv = rgb2yuv * i.gbr;

	float Y  = 0xDB / 255.f * yuv.x + 0x10 / 255.f;
	float Cr = 0xE0 / 255.f * yuv.y + 0x80 / 255.f;
	float Cb = 0xE0 / 255.f * yuv.z + 0x80 / 255.f;

	switch (uniform.emoda)
	{
		case 0: o.a = i.a; break;
		case 1: o.a = Y;   break;
		case 2: o.a = Y/2; break;
		case 3: o.a = 0;   break;
	}

	switch (uniform.emodc)
	{
		case 0: o.rgb = i.rgb;             break;
		case 1: o.rgb = float3(Y);         break;
		case 2: o.rgb = float3(Y, Cb, Cr); break;
		case 3: o.rgb = float3(i.a);       break;
	}

	return o;
}

fragment half4 ps_imgui(ImGuiShaderData data [[stage_in]], texture2d<half> texture [[texture(GSMTLTextureIndexNonHW)]])
{
	constexpr sampler s(coord::normalized, filter::linear, address::clamp_to_edge);
	return data.c * texture.sample(s, data.t);
}

fragment float4 ps_shadeboost(float4 p [[position]], DirectReadTextureIn<float> tex, constant float4& cb [[buffer(GSMTLBufferIndexUniforms)]])
{
	const float brt = cb.x;
	const float con = cb.y;
	const float sat = cb.z;
	const float gam = cb.w;
	// Increase or decrease these values to adjust r, g and b color channels separately
	const float AvgLumR = 0.5;
	const float AvgLumG = 0.5;
	const float AvgLumB = 0.5;

	const float3 LumCoeff = float3(0.2125, 0.7154, 0.0721);

	float3 AvgLumin = float3(AvgLumR, AvgLumG, AvgLumB);
	float3 brtColor = tex.read(p).rgb * brt;
	float dot_intensity = dot(brtColor, LumCoeff);
	float3 intensity = float3(dot_intensity, dot_intensity, dot_intensity);
	float3 satColor = mix(intensity, brtColor, sat);
	float3 conColor = mix(AvgLumin, satColor, con);

	float3 csb = pow(conColor, float3(1.0 / gam));

	return float4(csb, 1);
}

/*
   xBR upscaler for CPU -> render target uploads (FMVs, pre-rendered backgrounds, software-drawn 2D).
   Used by GSTextureCache::Target::Update when the "Dirty Upload Filter" option is set to xBR.
   xBR only reshapes block corners along detected edges, so the centre of every scaled block keeps the
   exact source colour and nearest readbacks of uploaded data stay bit-exact.

   Hyllian's xBR-vertex code and texel mapping

   Copyright (C) 2011/2016 Hyllian - sergiogdb@gmail.com

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.
*/
constant int XBR_BLEND_NONE = 0;
constant int XBR_BLEND_NORMAL = 1;
constant int XBR_BLEND_DOMINANT = 2;
constant float XBR_LUMINANCE_WEIGHT = 1.0;
constant float XBR_EQUAL_COLOR_TOLERANCE = 0.1176470588235294;
constant float XBR_STEEP_DIRECTION_THRESHOLD = 2.2;
constant float XBR_DOMINANT_DIRECTION_THRESHOLD = 3.6;
constant float4 XBR_W = float4(0.2627, 0.6780, 0.0593, 0.5);

static float xbr_dist(float4 pixA, float4 pixB)
{
	float scaleB = 0.5 / (1.0 - XBR_W.b);
	float scaleR = 0.5 / (1.0 - XBR_W.r);
	float4 diff = pixA - pixB;
	float Y = dot(diff, XBR_W);
	float Cb = scaleB * (diff.b - Y);
	float Cr = scaleR * (diff.r - Y);
	return sqrt(((XBR_LUMINANCE_WEIGHT * Y) * (XBR_LUMINANCE_WEIGHT * Y)) + (Cb * Cb) + (Cr * Cr));
}

static bool xbr_eq(float4 pixA, float4 pixB)
{
	return (xbr_dist(pixA, pixB) < XBR_EQUAL_COLOR_TOLERANCE);
}

static float xbr_left_ratio(float2 center, float2 origin, float2 direction, float scale)
{
	float2 P0 = center - origin;
	float2 proj = direction * (dot(P0, direction) / dot(direction, direction));
	float2 distv = P0 - proj;
	float2 orth = float2(-direction.y, direction.x);
	float side = sign(dot(P0, orth));
	float v = side * length(distv * scale);
	return smoothstep(-sqrt(2.0) / 2.0, sqrt(2.0) / 2.0, v);
}

static float4 xbr_fetch(texture2d<float> tex, int2 coord, int2 size)
{
	return tex.read(uint2(clamp(coord, int2(0, 0), size - int2(1, 1))));
}

#define XBR_P(xoffs, yoffs) xbr_fetch(tex_res.texture, coord + int2((xoffs), (yoffs)), size)
#define XBR_EQ(a, b) all((a) == (b))
#define XBR_NEQ(a, b) any((a) != (b))

fragment float4 ps_xbr_upscale(ConvertShaderData data [[stage_in]], ConvertPSRes tex_res)
{
	int2 size = int2(tex_res.texture.get_width(), tex_res.texture.get_height());

	// Source texel this output pixel maps to, and the number of source texels covered by one output pixel
	// (1 / upscale factor). The texture coordinate is linear across the quad, so the derivative is constant.
	float2 texel = data.t * float2(size);
	float2 texels_per_pixel = fwidth(data.t) * float2(size);
	float scale = max(1.0 / max(max(texels_per_pixel.x, texels_per_pixel.y), 0.000001), 1.0);

	float2 pos = fract(texel) - float2(0.5, 0.5);
	int2 coord = int2(floor(texel));

	// Input Pixel Mapping:  -|x|x|x|-
	//                       x|A|B|C|x
	//                       x|D|E|F|x
	//                       x|G|H|I|x
	//                       -|x|x|x|-
	float4 A = XBR_P(-1, -1);
	float4 B = XBR_P( 0, -1);
	float4 C = XBR_P( 1, -1);
	float4 D = XBR_P(-1,  0);
	float4 E = XBR_P( 0,  0);
	float4 F = XBR_P( 1,  0);
	float4 G = XBR_P(-1,  1);
	float4 H = XBR_P( 0,  1);
	float4 I = XBR_P( 1,  1);

	// blendResult Mapping: x|y|
	//                      w|z|
	int4 blendResult = int4(XBR_BLEND_NONE, XBR_BLEND_NONE, XBR_BLEND_NONE, XBR_BLEND_NONE);

	// Preprocess corners
	// Pixel Tap Mapping: -|-|-|-|-
	//                    -|-|B|C|-
	//                    -|D|E|F|x
	//                    -|G|H|I|x
	//                    -|-|x|x|-
	if (!((XBR_EQ(E, F) && XBR_EQ(H, I)) || (XBR_EQ(E, H) && XBR_EQ(F, I))))
	{
		float dist_H_F = xbr_dist(G, E) + xbr_dist(E, C) + xbr_dist(XBR_P(0, 2), I) + xbr_dist(I, XBR_P(2, 0)) + (4.0 * xbr_dist(H, F));
		float dist_E_I = xbr_dist(D, H) + xbr_dist(H, XBR_P(1, 2)) + xbr_dist(B, F) + xbr_dist(F, XBR_P(2, 1)) + (4.0 * xbr_dist(E, I));
		bool dominantGradient = (XBR_DOMINANT_DIRECTION_THRESHOLD * dist_H_F) < dist_E_I;
		blendResult.z = ((dist_H_F < dist_E_I) && XBR_NEQ(E, F) && XBR_NEQ(E, H)) ? ((dominantGradient) ? XBR_BLEND_DOMINANT : XBR_BLEND_NORMAL) : XBR_BLEND_NONE;
	}

	// Pixel Tap Mapping: -|-|-|-|-
	//                    -|A|B|-|-
	//                    x|D|E|F|-
	//                    x|G|H|I|-
	//                    -|x|x|-|-
	if (!((XBR_EQ(D, E) && XBR_EQ(G, H)) || (XBR_EQ(D, G) && XBR_EQ(E, H))))
	{
		float dist_G_E = xbr_dist(XBR_P(-2, 1), D) + xbr_dist(D, B) + xbr_dist(XBR_P(-1, 2), H) + xbr_dist(H, F) + (4.0 * xbr_dist(G, E));
		float dist_D_H = xbr_dist(XBR_P(-2, 0), G) + xbr_dist(G, XBR_P(0, 2)) + xbr_dist(A, E) + xbr_dist(E, I) + (4.0 * xbr_dist(D, H));
		bool dominantGradient = (XBR_DOMINANT_DIRECTION_THRESHOLD * dist_D_H) < dist_G_E;
		blendResult.w = ((dist_G_E > dist_D_H) && XBR_NEQ(E, D) && XBR_NEQ(E, H)) ? ((dominantGradient) ? XBR_BLEND_DOMINANT : XBR_BLEND_NORMAL) : XBR_BLEND_NONE;
	}

	// Pixel Tap Mapping: -|-|x|x|-
	//                    -|A|B|C|x
	//                    -|D|E|F|x
	//                    -|-|H|I|-
	//                    -|-|-|-|-
	if (!((XBR_EQ(B, C) && XBR_EQ(E, F)) || (XBR_EQ(B, E) && XBR_EQ(C, F))))
	{
		float dist_E_C = xbr_dist(D, B) + xbr_dist(B, XBR_P(1, -2)) + xbr_dist(H, F) + xbr_dist(F, XBR_P(2, -1)) + (4.0 * xbr_dist(E, C));
		float dist_B_F = xbr_dist(A, E) + xbr_dist(E, I) + xbr_dist(XBR_P(0, -2), C) + xbr_dist(C, XBR_P(2, 0)) + (4.0 * xbr_dist(B, F));
		bool dominantGradient = (XBR_DOMINANT_DIRECTION_THRESHOLD * dist_B_F) < dist_E_C;
		blendResult.y = ((dist_E_C > dist_B_F) && XBR_NEQ(E, B) && XBR_NEQ(E, F)) ? ((dominantGradient) ? XBR_BLEND_DOMINANT : XBR_BLEND_NORMAL) : XBR_BLEND_NONE;
	}

	// Pixel Tap Mapping: -|x|x|-|-
	//                    x|A|B|C|-
	//                    x|D|E|F|-
	//                    -|G|H|-|-
	//                    -|-|-|-|-
	if (!((XBR_EQ(A, B) && XBR_EQ(D, E)) || (XBR_EQ(A, D) && XBR_EQ(B, E))))
	{
		float dist_D_B = xbr_dist(XBR_P(-2, 0), A) + xbr_dist(A, XBR_P(0, -2)) + xbr_dist(G, E) + xbr_dist(E, C) + (4.0 * xbr_dist(D, B));
		float dist_A_E = xbr_dist(XBR_P(-2, -1), D) + xbr_dist(D, H) + xbr_dist(XBR_P(-1, -2), B) + xbr_dist(B, F) + (4.0 * xbr_dist(A, E));
		bool dominantGradient = (XBR_DOMINANT_DIRECTION_THRESHOLD * dist_D_B) < dist_A_E;
		blendResult.x = ((dist_D_B < dist_A_E) && XBR_NEQ(E, D) && XBR_NEQ(E, B)) ? ((dominantGradient) ? XBR_BLEND_DOMINANT : XBR_BLEND_NORMAL) : XBR_BLEND_NONE;
	}

	float4 res = E;

	// Pixel Tap Mapping: -|-|-|-|-
	//                    -|-|B|C|-
	//                    -|D|E|F|x
	//                    -|G|H|I|x
	//                    -|-|x|x|-
	if (blendResult.z != XBR_BLEND_NONE)
	{
		float dist_F_G = xbr_dist(F, G);
		float dist_H_C = xbr_dist(H, C);
		bool doLineBlend = (blendResult.z == XBR_BLEND_DOMINANT ||
			!((blendResult.y != XBR_BLEND_NONE && !xbr_eq(E, G)) || (blendResult.w != XBR_BLEND_NONE && !xbr_eq(E, C)) ||
			(xbr_eq(G, H) && xbr_eq(H, I) && xbr_eq(I, F) && xbr_eq(F, C) && !xbr_eq(E, I))));

		float2 origin = float2(0.0, 1.0 / sqrt(2.0));
		float2 direction = float2(1.0, -1.0);
		if (doLineBlend)
		{
			bool haveShallowLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_F_G <= dist_H_C) && XBR_NEQ(E, G) && XBR_NEQ(D, G);
			bool haveSteepLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_H_C <= dist_F_G) && XBR_NEQ(E, C) && XBR_NEQ(B, C);
			origin = haveShallowLine ? float2(0.0, 0.25) : float2(0.0, 0.5);
			direction.x += haveShallowLine ? 1.0 : 0.0;
			direction.y -= haveSteepLine ? 1.0 : 0.0;
		}

		float4 blendPix = mix(H, F, step(xbr_dist(E, F), xbr_dist(E, H)));
		res = mix(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
	}

	// Pixel Tap Mapping: -|-|-|-|-
	//                    -|A|B|-|-
	//                    x|D|E|F|-
	//                    x|G|H|I|-
	//                    -|x|x|-|-
	if (blendResult.w != XBR_BLEND_NONE)
	{
		float dist_H_A = xbr_dist(H, A);
		float dist_D_I = xbr_dist(D, I);
		bool doLineBlend = (blendResult.w == XBR_BLEND_DOMINANT ||
			!((blendResult.z != XBR_BLEND_NONE && !xbr_eq(E, A)) || (blendResult.x != XBR_BLEND_NONE && !xbr_eq(E, I)) ||
			(xbr_eq(A, D) && xbr_eq(D, G) && xbr_eq(G, H) && xbr_eq(H, I) && !xbr_eq(E, G))));

		float2 origin = float2(-1.0 / sqrt(2.0), 0.0);
		float2 direction = float2(1.0, 1.0);
		if (doLineBlend)
		{
			bool haveShallowLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_H_A <= dist_D_I) && XBR_NEQ(E, A) && XBR_NEQ(B, A);
			bool haveSteepLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_D_I <= dist_H_A) && XBR_NEQ(E, I) && XBR_NEQ(F, I);
			origin = haveShallowLine ? float2(-0.25, 0.0) : float2(-0.5, 0.0);
			direction.y += haveShallowLine ? 1.0 : 0.0;
			direction.x += haveSteepLine ? 1.0 : 0.0;
		}

		float4 blendPix = mix(H, D, step(xbr_dist(E, D), xbr_dist(E, H)));
		res = mix(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
	}

	// Pixel Tap Mapping: -|-|x|x|-
	//                    -|A|B|C|x
	//                    -|D|E|F|x
	//                    -|-|H|I|-
	//                    -|-|-|-|-
	if (blendResult.y != XBR_BLEND_NONE)
	{
		float dist_B_I = xbr_dist(B, I);
		float dist_F_A = xbr_dist(F, A);
		bool doLineBlend = (blendResult.y == XBR_BLEND_DOMINANT ||
			!((blendResult.x != XBR_BLEND_NONE && !xbr_eq(E, I)) || (blendResult.z != XBR_BLEND_NONE && !xbr_eq(E, A)) ||
			(xbr_eq(I, F) && xbr_eq(F, C) && xbr_eq(C, B) && xbr_eq(B, A) && !xbr_eq(E, C))));

		float2 origin = float2(1.0 / sqrt(2.0), 0.0);
		float2 direction = float2(-1.0, -1.0);
		if (doLineBlend)
		{
			bool haveShallowLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_B_I <= dist_F_A) && XBR_NEQ(E, I) && XBR_NEQ(H, I);
			bool haveSteepLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_F_A <= dist_B_I) && XBR_NEQ(E, A) && XBR_NEQ(D, A);
			origin = haveShallowLine ? float2(0.25, 0.0) : float2(0.5, 0.0);
			direction.y -= haveShallowLine ? 1.0 : 0.0;
			direction.x -= haveSteepLine ? 1.0 : 0.0;
		}

		float4 blendPix = mix(F, B, step(xbr_dist(E, B), xbr_dist(E, F)));
		res = mix(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
	}

	// Pixel Tap Mapping: -|x|x|-|-
	//                    x|A|B|C|-
	//                    x|D|E|F|-
	//                    -|G|H|-|-
	//                    -|-|-|-|-
	if (blendResult.x != XBR_BLEND_NONE)
	{
		float dist_D_C = xbr_dist(D, C);
		float dist_B_G = xbr_dist(B, G);
		bool doLineBlend = (blendResult.x == XBR_BLEND_DOMINANT ||
			!((blendResult.w != XBR_BLEND_NONE && !xbr_eq(E, C)) || (blendResult.y != XBR_BLEND_NONE && !xbr_eq(E, G)) ||
			(xbr_eq(C, B) && xbr_eq(B, A) && xbr_eq(A, D) && xbr_eq(D, G) && !xbr_eq(E, A))));

		float2 origin = float2(0.0, -1.0 / sqrt(2.0));
		float2 direction = float2(-1.0, 1.0);
		if (doLineBlend)
		{
			bool haveShallowLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_D_C <= dist_B_G) && XBR_NEQ(E, C) && XBR_NEQ(F, C);
			bool haveSteepLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_B_G <= dist_D_C) && XBR_NEQ(E, G) && XBR_NEQ(H, G);
			origin = haveShallowLine ? float2(0.0, -0.25) : float2(0.0, -0.5);
			direction.x -= haveShallowLine ? 1.0 : 0.0;
			direction.y += haveSteepLine ? 1.0 : 0.0;
		}

		float4 blendPix = mix(D, B, step(xbr_dist(E, B), xbr_dist(E, D)));
		res = mix(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
	}

	return res;
}

#undef XBR_P
#undef XBR_EQ
#undef XBR_NEQ
