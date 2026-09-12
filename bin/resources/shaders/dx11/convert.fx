// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#if defined(VERTEX_SHADER)

struct VS_INPUT
{
	float4 p : POSITION;
	float2 t : TEXCOORD0;
	float4 c : COLOR;
};

struct VS_OUTPUT
{
	float4 p : SV_Position;
	float2 t : TEXCOORD0;
	float4 c : COLOR;
};

VS_OUTPUT vs_main(VS_INPUT input)
{
	VS_OUTPUT output;

	output.p = input.p;
	output.t = input.t;
	output.c = input.c;

	return output;
}

#endif // VERTEX_SHADER

#if defined(PIXEL_SHADER)

cbuffer cb0 : register(b0)
{
	float4 BGColor;
	int EMODA;
	int EMODC;
	int DOFFSET;
};

static const float3x3 rgb2yuv =
{
	{0.587, 0.114, 0.299},
	{-0.311, 0.500, -0.169},
	{-0.419, -0.081, 0.500}
};

Texture2D Texture;
SamplerState TextureSampler;

#if HAS_FLOAT32_INPUT

float sample_c(float2 uv)
{
	return Texture.Sample(TextureSampler, uv).r;
}

#else

float4 sample_c(float2 uv)
{
	return Texture.Sample(TextureSampler, uv);
}

#endif

struct PS_INPUT
{
	float4 p : SV_Position;
	float2 t : TEXCOORD0;
	float4 c : COLOR;
};

#if HAS_INTEGER_OUTPUT
	#define OUTPUT_TYPE uint
	#define OUTPUT_SV SV_Target
#elif HAS_DEPTH_OUTPUT
	#define OUTPUT_TYPE float
	#define OUTPUT_SV SV_Depth
#elif HAS_FLOAT32_OUTPUT
	#define OUTPUT_TYPE float
	#define OUTPUT_SV SV_Target
#else
	#define OUTPUT_TYPE float4
	#define OUTPUT_SV SV_Target
#endif

struct PS_OUTPUT
{
	OUTPUT_TYPE o : OUTPUT_SV;
};

uint rgba8_to_uint(float4 c)
{
	uint4 i = uint4(c * 255.5f) & 0xFFu;
	return i.r | (i.g << 8) | (i.b << 16) | (i.a << 24);
}

uint rgb5a1_to_uint(float4 c)
{
	uint4 i = uint4(c * 255.5f) & uint4(0xF8u, 0xF8u, 0xF8u, 0x80u);
	return (i.r >> 3) | (i.g << 2) | (i.b << 7) | (i.a << 8);
}

uint depth_to_uint(float d)
{
	return uint(d * exp2(32.0f));
}

float4 uint_to_rgba8(uint i)
{
	return float4((i & 0xFFu), ((i >> 8) & 0xFFu), ((i >> 16) & 0xFFu), ((i >> 24) & 0xFFu)) / 255.0f;
}

float4 uint_to_rgb5a1(uint i)
{
	return float4(uint4(i << 3, i >> 2, i >> 7, i >> 8) & uint4(0xF8u, 0xF8u, 0xF8u, 0x80u)) / 255.0f;
}

float uint_to_depth32(uint i)
{
	return float(i) * exp2(-32.0f);
}

float uint_to_depth24(uint i)
{
	return float(i & 0xFFFFFFu) * exp2(-32.0f);
}

float uint_to_depth16(uint i)
{
	return float(i & 0xFFFFu) * exp2(-32.0f);
}

float rgba8_to_depth32(float4 val)
{
	return uint_to_depth32(rgba8_to_uint(val));
}

float rgba8_to_depth24(float4 val)
{
	return uint_to_depth24(rgba8_to_uint(val));
}

float rgba8_to_depth16(float4 val)
{
	return uint_to_depth16(rgba8_to_uint(val));
}

float rgb5a1_to_depth16(float4 val)
{
	return uint_to_depth16(rgb5a1_to_uint(val));
}

float4 depth32_to_rgba8(float d)
{
	return uint_to_rgba8(depth_to_uint(d));
}

float4 depth16_to_rgb5a1(float d)
{
	return uint_to_rgb5a1(depth_to_uint(d));
}

float depth32_to_depth24(float d)
{
	return uint_to_depth24(depth_to_uint(d));
}

float4 primid_to_rgba8(float p)
{
	return uint_to_rgba8(asuint(p));
}

#if defined(__ps_copy__)
OUTPUT_TYPE ps_copy(PS_INPUT input) : OUTPUT_SV
{
	return sample_c(input.t);
}
#endif

#if defined(__ps_depth_copy__)
OUTPUT_TYPE ps_depth_copy(PS_INPUT input) : OUTPUT_SV
{
	return sample_c(input.t);
}
#endif

#if defined(__ps_downsample_copy__)
PS_OUTPUT ps_downsample_copy(PS_INPUT input)
{
	int DownsampleFactor = DOFFSET;
	int2 ClampMin = int2(EMODA, EMODC);
	float Weight = BGColor.x;
	float step_multiplier = BGColor.y;

	int2 coord = max(int2(input.p.xy) * DownsampleFactor, ClampMin);

	PS_OUTPUT output;
	output.o = (float4)0;
	for (int yoff = 0; yoff < DownsampleFactor; yoff++)
	{
		for (int xoff = 0; xoff < DownsampleFactor; xoff++)
			output.o += Texture.Load(int3(coord + int2(xoff * step_multiplier, yoff * step_multiplier), 0));
	}
	output.o /= Weight;
	return output;
}
#endif

#if defined(__ps_filter_transparency__)
PS_OUTPUT ps_filter_transparency(PS_INPUT input)
{
	PS_OUTPUT output;
	float4 c = sample_c(input.t);
	output.o = float4(c.rgb, 1.0);
	return output;
}
#endif

#if defined(__ps_convert_rgb5a1_16bits__)
OUTPUT_TYPE ps_convert_rgb5a1_16bits(PS_INPUT input) : OUTPUT_SV
{
	// Need to be careful with precision here, it can break games like Spider-Man 3 and Dogs Life
	return rgb5a1_to_uint(sample_c(input.t));
}
#endif

#if defined(__ps_datm1__)
void ps_datm1(PS_INPUT input)
{
	clip(sample_c(input.t).a - 127.5f / 255); // >= 0x80 pass
}
#endif

#if defined(__ps_datm0__)
void ps_datm0(PS_INPUT input)
{
	clip(127.5f / 255 - sample_c(input.t).a); // < 0x80 pass (== 0x80 should not pass)
}
#endif

#if defined(__ps_datm1_rta_correction__)
void ps_datm1_rta_correction(PS_INPUT input)
{
	clip(sample_c(input.t).a - 254.5f / 255); // >= 0x80 pass
}
#endif

#if defined(__ps_datm0_rta_correction__)
void ps_datm0_rta_correction(PS_INPUT input)
{
	clip(254.5f / 255 - sample_c(input.t).a); // < 0x80 pass (== 0x80 should not pass)
}
#endif

#if defined(__ps_rta_correction__)
PS_OUTPUT ps_rta_correction(PS_INPUT input)
{
	PS_OUTPUT output;
	float4 value = sample_c(input.t);
	output.o = float4(value.rgb, value.a / (128.25f / 255.0f));
	return output;
}
#endif

#if defined(__ps_rta_decorrection__)
PS_OUTPUT ps_rta_decorrection(PS_INPUT input)
{
	PS_OUTPUT output;
	float4 value = sample_c(input.t);
	output.o = float4(value.rgb, value.a * (128.25f / 255.0f));
	return output;
}
#endif

#if defined(__ps_colclip_init__)
PS_OUTPUT ps_colclip_init(PS_INPUT input)
{
	PS_OUTPUT output;
	float4 value = sample_c(input.t);
	output.o = float4(round(value.rgb * 255) / 65535, value.a);
	return output;
}
#endif

#if defined(__ps_colclip_resolve__)
PS_OUTPUT ps_colclip_resolve(PS_INPUT input)
{
	PS_OUTPUT output;
	float4 value = sample_c(input.t);
	output.o = float4(float3(uint3(value.rgb * 65535.5) & 255) / 255, value.a);
	return output;
}
#endif

#if defined(__ps_convert_depth32_32bits__)
OUTPUT_TYPE ps_convert_depth32_32bits(PS_INPUT input) : OUTPUT_SV
{
	// Convert a depth texture into a 32 bits UINT texture
	return depth_to_uint(sample_c(input.t));
}
#endif

#if defined(__ps_convert_depth32_rgba8__)
OUTPUT_TYPE ps_convert_depth32_rgba8(PS_INPUT input) : OUTPUT_SV
{
	// Convert a depth texture into a RGBA color texture
	return depth32_to_rgba8(sample_c(input.t));
}
#endif

#if defined(__ps_convert_depth16_rgb5a1__)
OUTPUT_TYPE ps_convert_depth16_rgb5a1(PS_INPUT input) : OUTPUT_SV
{
	// Convert depth (only 16 lsb) into a RGB5A1 color texture
	return depth16_to_rgb5a1(sample_c(input.t));
}
#endif

#if defined(__ps_convert_depth32_depth24__)
OUTPUT_TYPE ps_convert_depth32_depth24(PS_INPUT input) : OUTPUT_SV
{
	// Truncates depth value to 24bits
	return depth32_to_depth24(sample_c(input.t));
}
#endif

#if defined(__ps_convert_primid_rgba8__)
OUTPUT_TYPE ps_convert_primid_rgba8(PS_INPUT input) : OUTPUT_SV
{
	return primid_to_rgba8(sample_c(input.t));
}
#endif

#define SAMPLE_RGBA_DEPTH_BILN(CONVERT_FN) \
	uint width, height; \
	Texture.GetDimensions(width, height); \
	float2 top_left_f = input.t * float2(width, height) - 0.5f; \
	int2 top_left = int2(floor(top_left_f)); \
	int4 coords = clamp(int4(top_left, top_left + 1), int4(0, 0, 0, 0), int2(width - 1, height - 1).xyxy); \
	float2 mix_vals = frac(top_left_f); \
	float depthTL = CONVERT_FN(Texture.Load(int3(coords.xy, 0))); \
	float depthTR = CONVERT_FN(Texture.Load(int3(coords.zy, 0))); \
	float depthBL = CONVERT_FN(Texture.Load(int3(coords.xw, 0))); \
	float depthBR = CONVERT_FN(Texture.Load(int3(coords.zw, 0))); \
	return floor(lerp(lerp(depthTL, depthTR, mix_vals.x), lerp(depthBL, depthBR, mix_vals.x), mix_vals.y) * exp2(32.0f)) * exp2(-32.0f); 

#if defined(__ps_convert_rgba8_depth32__)
OUTPUT_TYPE ps_convert_rgba8_depth32(PS_INPUT input) : OUTPUT_SV
{
	// Convert an RGBA texture into a float depth texture
#if HAS_BILN
	SAMPLE_RGBA_DEPTH_BILN(rgba8_to_depth32);
#else
	return rgba8_to_depth32(sample_c(input.t));
#endif
}
#endif

#if defined(__ps_convert_rgba8_depth24__)
OUTPUT_TYPE ps_convert_rgba8_depth24(PS_INPUT input) : OUTPUT_SV
{
	// Same as above but without the alpha channel (24 bits Z)
	// Convert an RGBA texture into a float depth texture
#if HAS_BILN
	SAMPLE_RGBA_DEPTH_BILN(rgba8_to_depth24);
#else
	return rgba8_to_depth24(sample_c(input.t));
#endif
}
#endif

#if defined(__ps_convert_rgba8_depth16__)
OUTPUT_TYPE ps_convert_rgba8_depth16(PS_INPUT input) : OUTPUT_SV
{
	// Same as above but without the A/B channels (16 bits Z)
	// Convert an RGBA texture into a float depth texture
#if HAS_BILN
	SAMPLE_RGBA_DEPTH_BILN(rgba8_to_depth16);
#else
	return rgba8_to_depth16(sample_c(input.t));
#endif
}
#endif

#if defined(__ps_convert_rgb5a1_depth16__)
OUTPUT_TYPE ps_convert_rgb5a1_depth16(PS_INPUT input) : OUTPUT_SV
{
	// Convert an RGB5A1 (saved as RGBA8) color to a 16 bit Z
#if HAS_BILN
	SAMPLE_RGBA_DEPTH_BILN(rgb5a1_to_depth16);
#else
	return rgb5a1_to_depth16(sample_c(input.t));
#endif
}
#endif

#if defined(__ps_convert_rgb5a1_8i__)
PS_OUTPUT ps_convert_rgb5a1_8i(PS_INPUT input)
{
	PS_OUTPUT output;

	// Convert a RGB5A1 texture into a 8 bits packed texture
	// Input column: 16x2 RGB5A1 pixels
	// 0: 16 RGBA
	// 1: 16 RGBA
	// Output column: 16x4 Index pixels
	// 0: 16 R5G2
	// 1: 16 R5G2
	// 2: 16 G2B5A1
	// 3: 16 G2B5A1
	uint2 pos = uint2(input.p.xy);

	// Collapse separate R G B A areas into their base pixel
	uint2 column = (pos & ~uint2(0u, 3u)) / uint2(1u, 2u);
	uint2 subcolumn = (pos & uint2(0u, 1u));
	column.x -= (column.x / 128u) * 64u;
	column.y += (column.y / 32u) * 32u;
	
	uint PSM = uint(DOFFSET);
	
	// Deal with swizzling differences
	if ((PSM & 0x8u) != 0u) // PSMCT16S
	{
		if ((pos.x & 32u) != 0u)
		{
			column.y += 32u; // 4 columns high times 4 to get bottom 4 blocks
			column.x &= ~32u;
		}
		
		if ((pos.x & 64u) != 0u)
		{
			column.x -= 32u;
		}
		
		if (((pos.x & 16u) != 0u) != ((pos.y & 16u) != 0u))
		{
			column.x ^= 16u; 
			column.y ^= 8u;
		}
		
		if ((PSM & 0x30u) != 0u) // PSMZ16S - Untested but hopefully ok if anything uses it.
		{
			column.x ^= 32u;
			column.y ^= 16u;
		}
	}
	else // PSMCT16
	{
		if ((pos.y & 32u) != 0u)
		{
			column.y -= 16u;
			column.x += 32u;
		}
		
		if ((pos.x & 96u) != 0u)
		{
			uint multi = (pos.x & 96u) / 32u;
			column.y += 16u * multi; // 4 columns high times 4 to get bottom 4 blocks
			column.x -= (pos.x & 96u);
		}
		
		if (((pos.x & 16u) != 0u) != ((pos.y & 16) != 0))
		{
			column.x ^= 16u; 
			column.y ^= 8u;
		}
		
		if ((PSM & 0x30u) != 0u) // PSMZ16 - Untested but hopefully ok if anything uses it.
		{
			column.x ^= 32u;
			column.y ^= 32u;
		}
	}
	
	uint2 coord = column | subcolumn;

	// Compensate for potentially differing page pitch.
	uint SBW = uint(EMODA);
	uint DBW = uint(EMODC);
	uint2 block_xy = coord / uint2(64u, 64u);
	uint block_num = (block_xy.y * (DBW / 128u)) + block_xy.x;
	uint2 block_offset = uint2((block_num % (SBW / 64u)) * 64u, (block_num / (SBW / 64u)) * 64u);
	coord = (coord % uint2(64u, 64u)) + block_offset;

	// Apply offset to cols 1 and 2
	uint is_col23 = pos.y & 4u;
	uint is_col13 = pos.y & 2u;
	uint is_col12 = is_col23 ^ (is_col13 << 1);
	coord.x ^= is_col12; // If cols 1 or 2, flip bit 3 of x

	float ScaleFactor = BGColor.x;
	if (floor(ScaleFactor) != ScaleFactor)
		coord = uint2(float2(coord) * ScaleFactor);
	else
		coord *= uint(ScaleFactor);

	float4 pixel = Texture.Load(int3(int2(coord), 0));
	uint4 denorm_c = (uint4)(pixel * 255.5f);
	if ((pos.y & 2u) == 0u)
	{
		uint red = (denorm_c.r >> 3) & 0x1Fu;
		uint green = (denorm_c.g >> 3) & 0x1Fu;
		
		output.o = (float4)(((float)(((green << 5) | red) & 0xFFu)) / 255.0f);
	}
	else
	{
		uint green = (denorm_c.g >> 3) & 0x1Fu;
		uint blue = (denorm_c.b >> 3) & 0x1Fu;
		uint alpha = denorm_c.a & 0x80u;

		output.o = (float4)(((float)((alpha | (blue << 2) | (green >> 3)) & 0xFFu)) / 255.0f);
	}
	return output;
}
#endif

#if defined(__ps_convert_rgba_8i__)
PS_OUTPUT ps_convert_rgba_8i(PS_INPUT input)
{
	PS_OUTPUT output;

	// Convert a RGBA texture into a 8 bits packed texture
	// Input column: 8x2 RGBA pixels
	// 0: 8 RGBA
	// 1: 8 RGBA
	// Output column: 16x4 Index pixels
	// 0: 8 R | 8 B
	// 1: 8 R | 8 B
	// 2: 8 G | 8 A
	// 3: 8 G | 8 A
	uint2 pos = uint2(input.p.xy);

	// Collapse separate R G B A areas into their base pixel
	uint2 block = (pos & ~uint2(15u, 3u)) >> 1;
	uint2 subblock = pos & uint2(7u, 1u);
	uint2 coord = block | subblock;

	// Compensate for potentially differing page pitch.
	uint SBW = uint(EMODA);
	uint DBW = uint(EMODC);
	uint2 block_xy = coord / uint2(64, 32);
	uint block_num = (block_xy.y * (DBW / 128)) + block_xy.x;
	uint2 block_offset = uint2((block_num % (SBW / 64)) * 64, (block_num / (SBW / 64)) * 32);
	coord = (coord % uint2(64, 32)) + block_offset;

	// Apply offset to cols 1 and 2
	uint is_col23 = pos.y & 4u;
	uint is_col13 = pos.y & 2u;
	uint is_col12 = is_col23 ^ (is_col13 << 1);
	coord.x ^= is_col12; // If cols 1 or 2, flip bit 3 of x

	float ScaleFactor = BGColor.x;
	if (floor(ScaleFactor) != ScaleFactor)
		coord = uint2(float2(coord) * ScaleFactor);
	else
		coord *= uint(ScaleFactor);

	float4 pixel = Texture.Load(int3(int2(coord), 0));
	float2 sel0 = (pos.y & 2u) == 0u ? pixel.rb : pixel.ga;
	float  sel1 = (pos.x & 8u) == 0u ? sel0.x : sel0.y;
	output.o = (float4)(sel1); // Divide by something here?
	return output;
}
#endif

#if defined(__ps_convert_clut_4__)
PS_OUTPUT ps_convert_clut_4(PS_INPUT input)
{
	// Borrowing the YUV constant buffer.
	float scale = BGColor.x;
	uint2 offset = uint2(uint(EMODA), uint(EMODC)) + uint(DOFFSET);

	// CLUT4 is easy, just two rows of 8x8.
	uint index = uint(input.p.x);
	uint2 pos = uint2(index % 8u, index / 8u);

	int2 final = int2(floor(float2(offset + pos) * scale));
	PS_OUTPUT output;
	output.o = Texture.Load(int3(final, 0), 0);
	return output;
}
#endif

#if defined(__ps_convert_clut_8__)
PS_OUTPUT ps_convert_clut_8(PS_INPUT input)
{
	float scale = BGColor.x;
	uint2 offset = uint2(uint(EMODA), uint(EMODC));
	uint index = min(uint(input.p.x) + uint(DOFFSET), 255u);

	// CLUT is arranged into 8 groups of 16x2, with the top-right and bottom-left quadrants swapped.
	// This can probably be done better..
	uint subgroup = (index / 8u) % 4u;
	uint2 pos;
	pos.x = (index % 8u) + ((subgroup >= 2u) ? 8u : 0u);
	pos.y = ((index / 32u) * 2u) + (subgroup % 2u);

	int2 final = int2(floor(float2(offset + pos) * scale));
	PS_OUTPUT output;
	output.o = Texture.Load(int3(final, 0), 0);
	return output;
}
#endif

#if defined(__ps_yuv__)
PS_OUTPUT ps_yuv(PS_INPUT input)
{
	PS_OUTPUT output;

	float4 i = sample_c(input.t);
	float3 yuv = mul(rgb2yuv, i.gbr);

	float Y = float(0xDB) / 255.0f * yuv.x + float(0x10) / 255.0f;
	float Cr = float(0xE0) / 255.0f * yuv.y + float(0x80) / 255.0f;
	float Cb = float(0xE0) / 255.0f * yuv.z + float(0x80) / 255.0f;

	switch (EMODA)
	{
		case 0:
			output.o.a = i.a;
			break;
		case 1:
			output.o.a = Y;
			break;
		case 2:
			output.o.a = Y / 2.0f;
			break;
		case 3:
		default:
			output.o.a = 0.0f;
			break;
	}

	switch (EMODC)
	{
		case 0:
			output.o.rgb = i.rgb;
			break;
		case 1:
			output.o.rgb = float3(Y, Y, Y);
			break;
		case 2:
			output.o.rgb = float3(Y, Cb, Cr);
			break;
		case 3:
		default:
			output.o.rgb = float3(i.a, i.a, i.a);
			break;
	}

	return output;
}
#endif

#if defined(__ps_primid_image_init_0__)
float ps_primid_image_init_0(PS_INPUT input) : SV_Target
{
	float c;
	if ((127.5f / 255.0f) < sample_c(input.t).a) // < 0x80 pass (== 0x80 should not pass)
		c = float(PRIMID_MIN);
	else
		c = float(PRIMID_MAX);
	return c;
}
#endif

#if defined(__ps_primid_image_init_1__)
float ps_primid_image_init_1(PS_INPUT input) : SV_Target
{
	float c;
	if (sample_c(input.t).a < (127.5f / 255.0f)) // >= 0x80 pass
		c = float(PRIMID_MIN);
	else
		c = float(PRIMID_MAX);
	return c;
}
#endif

#if defined(__ps_primid_image_init_2__)
float ps_primid_image_init_2(PS_INPUT input) : SV_Target
{
	float c;
	if ((254.5f / 255.0f) < sample_c(input.t).a) // < 0x80 pass (== 0x80 should not pass)
		c = float(PRIMID_MIN);
	else
		c = float(PRIMID_MAX);
	return c;
}
#endif

#if defined(__ps_primid_image_init_3__)
float ps_primid_image_init_3(PS_INPUT input) : SV_Target
{
	float c;
	if (sample_c(input.t).a < (254.5f / 255.0f)) // >= 0x80 pass
		c = float(PRIMID_MIN);
	else
		c = float(PRIMID_MAX);
	return c;
}
#endif

#if defined(__ps_xbr_upscale__)
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
static const int XBR_BLEND_NONE = 0;
static const int XBR_BLEND_NORMAL = 1;
static const int XBR_BLEND_DOMINANT = 2;
static const float XBR_LUMINANCE_WEIGHT = 1.0;
static const float XBR_EQUAL_COLOR_TOLERANCE = 0.1176470588235294;
static const float XBR_STEEP_DIRECTION_THRESHOLD = 2.2;
static const float XBR_DOMINANT_DIRECTION_THRESHOLD = 3.6;
static const float4 XBR_W = float4(0.2627, 0.6780, 0.0593, 0.5);

float xbr_dist(float4 pixA, float4 pixB)
{
	float scaleB = 0.5 / (1.0 - XBR_W.b);
	float scaleR = 0.5 / (1.0 - XBR_W.r);
	float4 diff = pixA - pixB;
	float Y = dot(diff, XBR_W);
	float Cb = scaleB * (diff.b - Y);
	float Cr = scaleR * (diff.r - Y);
	return sqrt(((XBR_LUMINANCE_WEIGHT * Y) * (XBR_LUMINANCE_WEIGHT * Y)) + (Cb * Cb) + (Cr * Cr));
}

bool xbr_eq(float4 pixA, float4 pixB)
{
	return (xbr_dist(pixA, pixB) < XBR_EQUAL_COLOR_TOLERANCE);
}

float xbr_left_ratio(float2 center, float2 origin, float2 direction, float scale)
{
	float2 P0 = center - origin;
	float2 proj = direction * (dot(P0, direction) / dot(direction, direction));
	float2 distv = P0 - proj;
	float2 orth = float2(-direction.y, direction.x);
	float side = sign(dot(P0, orth));
	float v = side * length(distv * scale);
	return smoothstep(-sqrt(2.0) / 2.0, sqrt(2.0) / 2.0, v);
}

float4 xbr_fetch(int2 coord, int2 size)
{
	return Texture.Load(int3(clamp(coord, int2(0, 0), size - int2(1, 1)), 0));
}

#define XBR_P(xoffs, yoffs) xbr_fetch(coord + int2((xoffs), (yoffs)), size)
#define XBR_EQ(a, b) all((a) == (b))
#define XBR_NEQ(a, b) any((a) != (b))

PS_OUTPUT ps_xbr_upscale(PS_INPUT input)
{
	uint tex_w, tex_h;
	Texture.GetDimensions(tex_w, tex_h);
	int2 size = int2(int(tex_w), int(tex_h));

	// Source texel this output pixel maps to, and the number of source texels covered by one output pixel
	// (1 / upscale factor). The texture coordinate is linear across the quad, so the derivative is constant.
	float2 texel = input.t * float2(size);
	float2 texels_per_pixel = fwidth(input.t) * float2(size);
	float scale = max(1.0 / max(max(texels_per_pixel.x, texels_per_pixel.y), 0.000001), 1.0);

	float2 pos = frac(texel) - float2(0.5, 0.5);
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

		float4 blendPix = lerp(H, F, step(xbr_dist(E, F), xbr_dist(E, H)));
		res = lerp(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
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

		float4 blendPix = lerp(H, D, step(xbr_dist(E, D), xbr_dist(E, H)));
		res = lerp(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
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

		float4 blendPix = lerp(F, B, step(xbr_dist(E, B), xbr_dist(E, F)));
		res = lerp(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
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

		float4 blendPix = lerp(D, B, step(xbr_dist(E, B), xbr_dist(E, D)));
		res = lerp(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
	}

	PS_OUTPUT output;
	output.o = res;
	return output;
}

#undef XBR_P
#undef XBR_EQ
#undef XBR_NEQ
#endif

#endif // PIXEL_SHADER