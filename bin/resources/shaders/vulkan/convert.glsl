// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec2 a_tex;

layout(location = 0) out vec2 v_tex;

void main()
{
	gl_Position = vec4(a_pos.x, -a_pos.y, a_pos.z, a_pos.w);
	v_tex = a_tex;
}

#endif

#ifdef FRAGMENT_SHADER

layout(location = 0) in vec2 v_tex;

#if HAS_INTEGER_OUTPUT
	layout(location = 0) out uint o_col0;
	#define OUTPUT o_col0
#elif HAS_DEPTH_OUTPUT
	out float gl_FragDepth;
	#define OUTPUT gl_FragDepth
#elif HAS_FLOAT32_OUTPUT
	layout(location = 0) out float o_col0;
	#define OUTPUT o_col0
#elif HAS_STENCIL_OUTPUT
#else
	layout(location = 0) out vec4 o_col0;
	#define OUTPUT o_col0
#endif

layout(set = 0, binding = 0) uniform sampler2D samp0;

#if HAS_FLOAT32_INPUT

float sample_c(vec2 uv)
{
	return texture(samp0, uv).r;
}

#else

vec4 sample_c(vec2 uv)
{
	return texture(samp0, uv);
}

#endif

uint rgba8_to_uint(vec4 c)
{
	uvec4 i = uvec4(c * 255.5f) & 0xFFu;
	return i.r | (i.g << 8) | (i.b << 16) | (i.a << 24);
}

uint rgb5a1_to_uint(vec4 c)
{
	uvec4 i = uvec4(c * 255.5f) & uvec4(0xF8u, 0xF8u, 0xF8u, 0x80u);
	return (i.r >> 3) | (i.g << 2) | (i.b << 7) | (i.a << 8);
}

uint depth_to_uint(float d)
{
	return uint(d * exp2(32.0f));
}

vec4 uint_to_rgba8(uint i)
{
	return vec4((i & 0xFFu), ((i >> 8) & 0xFFu), ((i >> 16) & 0xFFu), ((i >> 24) & 0xFFu)) / 255.0f;
}

vec4 uint_to_rgb5a1(uint i)
{
	return vec4(uvec4(i << 3, i >> 2, i >> 7, i >> 8) & uvec4(0xF8u, 0xF8u, 0xF8u, 0x80u)) / 255.0f;
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

float rgba8_to_depth32(vec4 val)
{
	return uint_to_depth32(rgba8_to_uint(val));
}

float rgba8_to_depth24(vec4 val)
{
	return uint_to_depth24(rgba8_to_uint(val));
}

float rgba8_to_depth16(vec4 val)
{
	return uint_to_depth16(rgba8_to_uint(val));
}

float rgb5a1_to_depth16(vec4 val)
{
	return uint_to_depth16(rgb5a1_to_uint(val));
}

vec4 depth32_to_rgba8(float d)
{
	return uint_to_rgba8(depth_to_uint(d));
}

vec4 depth16_to_rgb5a1(float d)
{
	return uint_to_rgb5a1(depth_to_uint(d));
}

float depth32_to_depth24(float d)
{
	return uint_to_depth24(depth_to_uint(d));
}

vec4 primid_to_rgba8(float p)
{
	return uint_to_rgba8(floatBitsToUint(p));
}

#ifdef ps_copy
void ps_copy()
{
	OUTPUT = sample_c(v_tex);
}
#endif

#ifdef ps_depth_copy
void ps_depth_copy()
{
	OUTPUT = sample_c(v_tex);
}
#endif

#ifdef ps_downsample_copy
layout(push_constant) uniform cb10
{
	ivec2 ClampMin;
	int DownsampleFactor;
	int pad0;
	float Weight;
	float step_multiplier;
	vec2 pad1;
};
void ps_downsample_copy()
{
	ivec2 coord = max(ivec2(gl_FragCoord.xy) * DownsampleFactor, ClampMin);
	vec4 result = vec4(0);
	for (int yoff = 0; yoff < DownsampleFactor; yoff++)
	{
		for (int xoff = 0; xoff < DownsampleFactor; xoff++)
		{
			result += texelFetch(samp0, coord + ivec2(xoff * step_multiplier, yoff * step_multiplier), 0);
		}
	}
	OUTPUT = result / Weight;
}
#endif

#ifdef ps_filter_transparency
void ps_filter_transparency()
{
	vec4 c = sample_c(v_tex);
	OUTPUT = vec4(c.rgb, 1.0);
}
#endif

#ifdef ps_convert_rgb5a1_16bits
void ps_convert_rgb5a1_16bits()
{
	// Need to be careful with precision here, it can break games like Spider-Man 3 and Dogs Life
	OUTPUT = rgb5a1_to_uint(sample_c(v_tex));
}
#endif

#ifdef ps_datm1
void ps_datm1()
{
	if(sample_c(v_tex).a < (127.5f / 255.0f)) // >= 0x80 pass
		discard;
}
#endif

#ifdef ps_datm0
void ps_datm0()
{
	if((127.5f / 255.0f) < sample_c(v_tex).a) // < 0x80 pass (== 0x80 should not pass)
		discard;
}
#endif

#ifdef ps_datm1_rta_correction
void ps_datm1_rta_correction()
{
	if(sample_c(v_tex).a < (254.5f / 255.0f)) // >= 0x80 pass
		discard;
}
#endif

#ifdef ps_datm0_rta_correction
void ps_datm0_rta_correction()
{
	if((254.5f / 255.0f) < sample_c(v_tex).a) // < 0x80 pass (== 0x80 should not pass)
		discard;
}
#endif

#ifdef ps_rta_correction
void ps_rta_correction()
{
	vec4 value = sample_c(v_tex);
	OUTPUT = vec4(value.rgb, value.a / (128.25f / 255.0f));
}
#endif

#ifdef ps_rta_decorrection
void ps_rta_decorrection()
{
	vec4 value = sample_c(v_tex);
	OUTPUT = vec4(value.rgb, value.a * (128.25f / 255.0f));
}
#endif

#ifdef ps_colclip_init
void ps_colclip_init()
{
	vec4 value = sample_c(v_tex);
	OUTPUT = vec4(roundEven(value.rgb * 255.0f) / 65535.0f, value.a);
}
#endif

#ifdef ps_colclip_resolve
void ps_colclip_resolve()
{
	vec4 value = sample_c(v_tex);
	OUTPUT = vec4(vec3(uvec3(value.rgb * 65535.5f) & 255u) / 255.0f, value.a);
}
#endif

#ifdef ps_convert_depth32_32bits
void ps_convert_depth32_32bits()
{
	// Convert a vec32 depth texture into a 32 bits UINT texture
	OUTPUT = depth_to_uint(sample_c(v_tex));
}
#endif

#ifdef ps_convert_depth32_rgba8
void ps_convert_depth32_rgba8()
{
	// Convert a vec32 depth texture into a RGBA color texture
	OUTPUT = depth32_to_rgba8(sample_c(v_tex));
}
#endif

#ifdef ps_convert_depth16_rgb5a1
void ps_convert_depth16_rgb5a1()
{
	// Convert a vec32 (only 16 lsb) depth into a RGB5A1 color texture
	OUTPUT = depth16_to_rgb5a1(sample_c(v_tex));
}
#endif

#ifdef ps_convert_depth32_depth24
void ps_convert_depth32_depth24()
{
	// Truncates depth value to 24bits
	OUTPUT = depth32_to_depth24(sample_c(v_tex));
}
#endif

#ifdef ps_convert_primid_rgba8
void ps_convert_primid_rgba8()
{
	OUTPUT = primid_to_rgba8(sample_c(v_tex));
}
#endif

#define SAMPLE_RGBA_DEPTH_BILN(CONVERT_FN) \
	ivec2 dims = textureSize(samp0, 0); \
	vec2 top_left_f = v_tex * vec2(dims) - 0.5f; \
	ivec2 top_left = ivec2(floor(top_left_f)); \
	ivec4 coords = clamp(ivec4(top_left, top_left + 1), ivec4(0), dims.xyxy - 1); \
	vec2 mix_vals = fract(top_left_f); \
	float depthTL = CONVERT_FN(texelFetch(samp0, coords.xy, 0)); \
	float depthTR = CONVERT_FN(texelFetch(samp0, coords.zy, 0)); \
	float depthBL = CONVERT_FN(texelFetch(samp0, coords.xw, 0)); \
	float depthBR = CONVERT_FN(texelFetch(samp0, coords.zw, 0)); \
	OUTPUT = floor(mix(mix(depthTL, depthTR, mix_vals.x), mix(depthBL, depthBR, mix_vals.x), mix_vals.y) * exp2(32.0f)) * exp2(-32.0f);

#ifdef ps_convert_rgba8_depth32
void ps_convert_rgba8_depth32()
{
	// Convert an RGBA texture into a float depth texture
#if HAS_BILN
	SAMPLE_RGBA_DEPTH_BILN(rgba8_to_depth32);
#else
	OUTPUT = rgba8_to_depth32(sample_c(v_tex));
#endif
}
#endif

#ifdef ps_convert_rgba8_depth24
void ps_convert_rgba8_depth24()
{
	// Same as above but without the alpha channel (24 bits Z)
#if HAS_BILN
	SAMPLE_RGBA_DEPTH_BILN(rgba8_to_depth24);
#else
	OUTPUT = rgba8_to_depth24(sample_c(v_tex));
#endif
}
#endif

#ifdef ps_convert_rgba8_depth16
void ps_convert_rgba8_depth16()
{
	// Same as above but without the A/B channels (16 bits Z)
#if HAS_BILN
	SAMPLE_RGBA_DEPTH_BILN(rgba8_to_depth16);
#else
	OUTPUT = rgba8_to_depth16(sample_c(v_tex));
#endif
}
#endif

#ifdef ps_convert_rgb5a1_depth16
void ps_convert_rgb5a1_depth16()
{
	// Convert an RGB5A1 (saved as RGBA8) color to a 16 bit Z
#if HAS_BILN
	SAMPLE_RGBA_DEPTH_BILN(rgb5a1_to_depth16);
#else
	OUTPUT = rgb5a1_to_depth16(sample_c(v_tex));
#endif
}
#endif

#ifdef ps_convert_rgb5a1_8i
layout(push_constant) uniform cb10
{
	uint SBW;
	uint DBW;
	uint PSM;
	float cb_pad1;
	float ScaleFactor;
	vec3 cb_pad2;
};

void ps_convert_rgb5a1_8i()
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

	uvec2 pos = uvec2(gl_FragCoord.xy);

	// Collapse separate R G B A areas into their base pixel
	uvec2 column = (pos & ~uvec2(0u, 3u)) / uvec2(1u, 2u);
	uvec2 subcolumn = (pos & uvec2(0u, 1u));
	column.x -= (column.x / 128u) * 64u;
	column.y += (column.y / 32u) * 32u;

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

		if (((pos.x & 16u) != 0u) != ((pos.y & 16u) != 0u))
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
	uvec2 coord = column | subcolumn;

	// Compensate for potentially differing page pitch.
	uvec2 block_xy = coord / uvec2(64u, 64u);
	uint block_num = (block_xy.y * (DBW / 128u)) + block_xy.x;
	uvec2 block_offset = uvec2((block_num % (SBW / 64u)) * 64u, (block_num / (SBW / 64u)) * 64u);
	coord = (coord % uvec2(64u, 64u)) + block_offset;

	// Apply offset to cols 1 and 2
	uint is_col23 = pos.y & 4u;
	uint is_col13 = pos.y & 2u;
	uint is_col12 = is_col23 ^ (is_col13 << 1);
	coord.x ^= is_col12; // If cols 1 or 2, flip bit 3 of x

	if (floor(ScaleFactor) != ScaleFactor)
		coord = uvec2(vec2(coord) * ScaleFactor);
	else
		coord *= uvec2(ScaleFactor);

	vec4 pixel = texelFetch(samp0, ivec2(coord), 0);

	uvec4 denorm_c = uvec4(pixel * 255.5f);
	if ((pos.y & 2u) == 0u)
	{
		uint red = (denorm_c.r >> 3) & 0x1Fu;
		uint green = (denorm_c.g >> 3) & 0x1Fu;

		o_col0 = vec4(float(((green << 5) | red) & 0xFFu) / 255.0f);
	}
	else
	{
		uint green = (denorm_c.g >> 3) & 0x1Fu;
		uint blue = (denorm_c.b >> 3) & 0x1Fu;
		uint alpha = denorm_c.a & 0x80u;

		o_col0 = vec4(float((alpha | (blue << 2) | (green >> 3)) & 0xFFu) / 255.0f);
	}
}
#endif

#ifdef ps_convert_rgba_8i
layout(push_constant) uniform cb10
{
	uint SBW;
	uint DBW;
	uint PSM;
	float cb_pad1;
	float ScaleFactor;
	vec3 cb_pad2;
};

void ps_convert_rgba_8i()
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
	uvec2 pos = uvec2(gl_FragCoord.xy);

	// Collapse separate R G B A areas into their base pixel
	uvec2 block = (pos & ~uvec2(15u, 3u)) >> 1;
	uvec2 subblock = pos & uvec2(7u, 1u);
	uvec2 coord = block | subblock;

	// Compensate for potentially differing page pitch.
	uvec2 block_xy = coord / uvec2(64u, 32u);
	uint block_num = (block_xy.y * (DBW / 128u)) + block_xy.x;
	uvec2 block_offset = uvec2((block_num % (SBW / 64u)) * 64u, (block_num / (SBW / 64u)) * 32u);
	coord = (coord % uvec2(64u, 32u)) + block_offset;

	// Apply offset to cols 1 and 2
	uint is_col23 = pos.y & 4u;
	uint is_col13 = pos.y & 2u;
	uint is_col12 = is_col23 ^ (is_col13 << 1);
	coord.x ^= is_col12; // If cols 1 or 2, flip bit 3 of x

	if (floor(ScaleFactor) != ScaleFactor)
		coord = uvec2(vec2(coord) * ScaleFactor);
	else
		coord *= uvec2(ScaleFactor);

	vec4 pixel = texelFetch(samp0, ivec2(coord), 0);
	vec2  sel0 = (pos.y & 2u) == 0u ? pixel.rb : pixel.ga;
	float sel1 = (pos.x & 8u) == 0u ? sel0.x : sel0.y;
	o_col0 = vec4(sel1); // Divide by something here?
}
#endif

#ifdef ps_convert_clut_4
layout(push_constant) uniform cb10
{
	uvec2 offset;
	uint doffset;
	uint cb_pad1;
	float scale;
	vec3 cb_pad2;
};

void ps_convert_clut_4()
{
	// CLUT4 is easy, just two rows of 8x8.
	uint index = uint(gl_FragCoord.x) + doffset;
	uvec2 pos = uvec2(index % 8u, index / 8u);

	ivec2 final = ivec2(floor(vec2(offset + pos) * vec2(scale)));
	o_col0 = texelFetch(samp0, final, 0);
}
#endif

#ifdef ps_convert_clut_8
layout(push_constant) uniform cb10
{
	uvec2 offset;
	uint doffset;
	uint cb_pad1;
	float scale;
	vec3 cb_pad2;
};

void ps_convert_clut_8()
{
	uint index = min(uint(gl_FragCoord.x) + doffset, 255u);

	// CLUT is arranged into 8 groups of 16x2, with the top-right and bottom-left quadrants swapped.
	// This can probably be done better..
	uint subgroup = (index / 8u) % 4u;
	uvec2 pos;
	pos.x = (index % 8u) + ((subgroup >= 2u) ? 8u : 0u);
	pos.y = ((index / 32u) * 2u) + (subgroup % 2u);

	ivec2 final = ivec2(floor(vec2(offset + pos) * vec2(scale)));
	o_col0 = texelFetch(samp0, final, 0);
}
#endif

#ifdef ps_yuv
layout(push_constant) uniform cb10
{
	int EMODA;
	int EMODC;
};

void ps_yuv()
{
	vec4 i = sample_c(v_tex);
	vec4 o = vec4(0.0f);

	mat3 rgb2yuv;
	rgb2yuv[0] = vec3(0.587, -0.311, -0.419);
	rgb2yuv[1] = vec3(0.114, 0.500, -0.081);
	rgb2yuv[2] = vec3(0.299, -0.169, 0.500);

	vec3 yuv = rgb2yuv * i.gbr;

	float Y = float(0xDB)/255.0f * yuv.x + float(0x10)/255.0f;
	float Cr = float(0xE0)/255.0f * yuv.y + float(0x80)/255.0f;
	float Cb = float(0xE0)/255.0f * yuv.z + float(0x80)/255.0f;

	switch(EMODA)
	{
		case 0:
			o.a = i.a;
			break;
		case 1:
			o.a = Y;
			break;
		case 2:
			o.a = Y/2.0f;
			break;
		case 3:
			o.a = 0.0f;
			break;
	}

	switch(EMODC)
	{
		case 0:
			o.rgb = i.rgb;
			break;
		case 1:
			o.rgb = vec3(Y);
			break;
		case 2:
			o.rgb = vec3(Y, Cb, Cr);
			break;
		case 3:
			o.rgb = vec3(i.a);
			break;
	}

	o_col0 = o;
}
#endif

#if defined(ps_primid_image_init_0) || defined(ps_primid_image_init_1) || defined(ps_primid_image_init_2) || defined(ps_primid_image_init_3)

void main()
{
	o_col0 = vec4(PRIMID_MAX);

	#ifdef ps_primid_image_init_0
		if((127.5f / 255.0f) < sample_c(v_tex).a) // < 0x80 pass (== 0x80 should not pass)
			o_col0 = vec4(PRIMID_MIN);
	#endif
	#ifdef ps_primid_image_init_1
		if(sample_c(v_tex).a < (127.5f / 255.0f)) // >= 0x80 pass
			o_col0 = vec4(PRIMID_MIN);
	#endif
	#ifdef ps_primid_image_init_2
		if((254.5f / 255.0f) < sample_c(v_tex).a) // < 0x80 pass (== 0x80 should not pass)
			o_col0 = vec4(PRIMID_MIN);
	#endif
	#ifdef ps_primid_image_init_3
		if(sample_c(v_tex).a < (254.5f / 255.0f)) // >= 0x80 pass
			o_col0 = vec4(PRIMID_MIN);
	#endif
}
#endif

#ifdef ps_xbr_upscale
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
const int XBR_BLEND_NONE = 0;
const int XBR_BLEND_NORMAL = 1;
const int XBR_BLEND_DOMINANT = 2;
const float XBR_LUMINANCE_WEIGHT = 1.0;
const float XBR_EQUAL_COLOR_TOLERANCE = 0.1176470588235294;
const float XBR_STEEP_DIRECTION_THRESHOLD = 2.2;
const float XBR_DOMINANT_DIRECTION_THRESHOLD = 3.6;
const vec4 XBR_W = vec4(0.2627, 0.6780, 0.0593, 0.5);

float xbr_dist(vec4 pixA, vec4 pixB)
{
	float scaleB = 0.5 / (1.0 - XBR_W.b);
	float scaleR = 0.5 / (1.0 - XBR_W.r);
	vec4 diff = pixA - pixB;
	float Y = dot(diff, XBR_W);
	float Cb = scaleB * (diff.b - Y);
	float Cr = scaleR * (diff.r - Y);
	return sqrt(((XBR_LUMINANCE_WEIGHT * Y) * (XBR_LUMINANCE_WEIGHT * Y)) + (Cb * Cb) + (Cr * Cr));
}

bool xbr_eq(vec4 pixA, vec4 pixB)
{
	return (xbr_dist(pixA, pixB) < XBR_EQUAL_COLOR_TOLERANCE);
}

float xbr_left_ratio(vec2 center, vec2 origin, vec2 direction, float scale)
{
	vec2 P0 = center - origin;
	vec2 proj = direction * (dot(P0, direction) / dot(direction, direction));
	vec2 distv = P0 - proj;
	vec2 orth = vec2(-direction.y, direction.x);
	float side = sign(dot(P0, orth));
	float v = side * length(distv * scale);
	return smoothstep(-sqrt(2.0) / 2.0, sqrt(2.0) / 2.0, v);
}

vec4 xbr_fetch(ivec2 coord, ivec2 size)
{
	return texelFetch(samp0, clamp(coord, ivec2(0, 0), size - ivec2(1, 1)), 0);
}

#define XBR_P(xoffs, yoffs) xbr_fetch(coord + ivec2((xoffs), (yoffs)), size)
#define XBR_EQ(a, b) all(equal((a), (b)))
#define XBR_NEQ(a, b) any(notEqual((a), (b)))

void ps_xbr_upscale()
{
	ivec2 size = textureSize(samp0, 0);

	// Source texel this output pixel maps to, and the number of source texels covered by one output pixel
	// (1 / upscale factor). The texture coordinate is linear across the quad, so the derivative is constant.
	vec2 texel = v_tex * vec2(size);
	vec2 texels_per_pixel = fwidth(v_tex) * vec2(size);
	float scale = max(1.0 / max(max(texels_per_pixel.x, texels_per_pixel.y), 0.000001), 1.0);

	vec2 pos = fract(texel) - vec2(0.5, 0.5);
	ivec2 coord = ivec2(floor(texel));

	// Input Pixel Mapping:  -|x|x|x|-
	//                       x|A|B|C|x
	//                       x|D|E|F|x
	//                       x|G|H|I|x
	//                       -|x|x|x|-
	vec4 A = XBR_P(-1, -1);
	vec4 B = XBR_P( 0, -1);
	vec4 C = XBR_P( 1, -1);
	vec4 D = XBR_P(-1,  0);
	vec4 E = XBR_P( 0,  0);
	vec4 F = XBR_P( 1,  0);
	vec4 G = XBR_P(-1,  1);
	vec4 H = XBR_P( 0,  1);
	vec4 I = XBR_P( 1,  1);

	// blendResult Mapping: x|y|
	//                      w|z|
	ivec4 blendResult = ivec4(XBR_BLEND_NONE, XBR_BLEND_NONE, XBR_BLEND_NONE, XBR_BLEND_NONE);

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

	vec4 res = E;

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

		vec2 origin = vec2(0.0, 1.0 / sqrt(2.0));
		vec2 direction = vec2(1.0, -1.0);
		if (doLineBlend)
		{
			bool haveShallowLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_F_G <= dist_H_C) && XBR_NEQ(E, G) && XBR_NEQ(D, G);
			bool haveSteepLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_H_C <= dist_F_G) && XBR_NEQ(E, C) && XBR_NEQ(B, C);
			origin = haveShallowLine ? vec2(0.0, 0.25) : vec2(0.0, 0.5);
			direction.x += haveShallowLine ? 1.0 : 0.0;
			direction.y -= haveSteepLine ? 1.0 : 0.0;
		}

		vec4 blendPix = mix(H, F, step(xbr_dist(E, F), xbr_dist(E, H)));
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

		vec2 origin = vec2(-1.0 / sqrt(2.0), 0.0);
		vec2 direction = vec2(1.0, 1.0);
		if (doLineBlend)
		{
			bool haveShallowLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_H_A <= dist_D_I) && XBR_NEQ(E, A) && XBR_NEQ(B, A);
			bool haveSteepLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_D_I <= dist_H_A) && XBR_NEQ(E, I) && XBR_NEQ(F, I);
			origin = haveShallowLine ? vec2(-0.25, 0.0) : vec2(-0.5, 0.0);
			direction.y += haveShallowLine ? 1.0 : 0.0;
			direction.x += haveSteepLine ? 1.0 : 0.0;
		}

		vec4 blendPix = mix(H, D, step(xbr_dist(E, D), xbr_dist(E, H)));
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

		vec2 origin = vec2(1.0 / sqrt(2.0), 0.0);
		vec2 direction = vec2(-1.0, -1.0);
		if (doLineBlend)
		{
			bool haveShallowLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_B_I <= dist_F_A) && XBR_NEQ(E, I) && XBR_NEQ(H, I);
			bool haveSteepLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_F_A <= dist_B_I) && XBR_NEQ(E, A) && XBR_NEQ(D, A);
			origin = haveShallowLine ? vec2(0.25, 0.0) : vec2(0.5, 0.0);
			direction.y -= haveShallowLine ? 1.0 : 0.0;
			direction.x -= haveSteepLine ? 1.0 : 0.0;
		}

		vec4 blendPix = mix(F, B, step(xbr_dist(E, B), xbr_dist(E, F)));
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

		vec2 origin = vec2(0.0, -1.0 / sqrt(2.0));
		vec2 direction = vec2(-1.0, 1.0);
		if (doLineBlend)
		{
			bool haveShallowLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_D_C <= dist_B_G) && XBR_NEQ(E, C) && XBR_NEQ(F, C);
			bool haveSteepLine = (XBR_STEEP_DIRECTION_THRESHOLD * dist_B_G <= dist_D_C) && XBR_NEQ(E, G) && XBR_NEQ(H, G);
			origin = haveShallowLine ? vec2(0.0, -0.25) : vec2(0.0, -0.5);
			direction.x -= haveShallowLine ? 1.0 : 0.0;
			direction.y += haveSteepLine ? 1.0 : 0.0;
		}

		vec4 blendPix = mix(D, B, step(xbr_dist(E, B), xbr_dist(E, D)));
		res = mix(res, blendPix, xbr_left_ratio(pos, origin, direction, scale));
	}

	o_col0 = res;
}

#undef XBR_P
#undef XBR_EQ
#undef XBR_NEQ
#endif

#endif
