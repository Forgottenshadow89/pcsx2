#!/usr/bin/perl
# "Filter 2D Images" (Off / Bilinear / xBR) — complete patch over the upstream base.
#   Off      : stock PCSX2.
#   Bilinear : CPU -> render target uploads (>= 16bpp) stretched bilinearly; flat 2D draws sampled bilinearly.
#   xBR      : the same, but with Hyllian's xBR: uploads, native resolution frames (Native Scaling) and the
#              textures used by flat 2D draws (hash cache textures, factor min(4, upscale)) are xBR-upscaled.
# Independent from the Bilinear Dirty Upscale hardware fix.
use strict;
use warnings;

my ($root, $scratch) = @ARGV;
die "usage: patch_filter2d_v2.pl <repo root> <scratchpad with block_*.txt>" unless $root && $scratch;
local $/;

sub slurp { my $f = shift; open(my $fh, '<', $f) or die "open $f: $!"; my $s = <$fh>; close $fh; return $s; }

sub patch {
	my ($file, @pairs) = @_;
	my $src = slurp($file);
	my ($count, $total) = (0, 0);
	while (@pairs) {
		my $old = shift @pairs;
		my $new = shift @pairs;
		$total++;
		$count += ($src =~ s/\Q$old\E/$new/);
	}
	die "$file: only $count of $total replacements applied\n" if $count != $total;
	open(my $fh, '>', $file) or die "write $file: $!";
	binmode($fh);
	print $fh $src;
	close $fh;
	print "$file: $count/$total\n";
}

# ============================================================ Config ============================================================
patch("$root/pcsx2/Config.h",
<<'OLD', <<'NEW',
enum class GSBilinearDirtyMode : u8
{
	Automatic,
	ForceBilinear,
	ForceNearest,
	MaxCount
};
OLD
enum class GSBilinearDirtyMode : u8
{
	Automatic,
	ForceBilinear,
	ForceNearest,
	MaxCount
};

// Filter 2D Images: filtering applied to 2D content that stock PCSX2 leaves as replicated pixels when upscaling
// (CPU -> render target uploads, native resolution frames, textures used by flat 2D draws). Independent from the
// Bilinear Dirty Upscale hardware fix.
enum class GSFilter2DMode : u8
{
	Off,
	Bilinear,
	xBR,
	MaxCount
};
NEW
<<'OLD', <<'NEW');
		BiFiltering TextureFiltering = DEFAULT_TEXTURE_FILTERING_MODE;
OLD
		BiFiltering TextureFiltering = DEFAULT_TEXTURE_FILTERING_MODE;
		GSFilter2DMode Filter2D = GSFilter2DMode::Off;
NEW

patch("$root/pcsx2/Pcsx2Config.cpp",
<<'OLD', <<'NEW',
		OpEqu(TextureFiltering) &&
OLD
		OpEqu(TextureFiltering) &&
		OpEqu(Filter2D) &&
NEW
<<'OLD', <<'NEW');
	SettingsWrapIntEnumEx(TextureFiltering, "filter");
OLD
	SettingsWrapIntEnumEx(TextureFiltering, "filter");
	SettingsWrapIntEnumEx(Filter2D, "Filter2D");
NEW

# ============================================================ Shader plumbing ============================================================
patch("$root/pcsx2/GS/Renderers/Common/GSDevice.h",
<<'OLD', <<'NEW',
	YUV,
	Count
};
OLD
	YUV,
	XBR_UPSCALE,
	Count
};
NEW
<<'OLD', <<'NEW');
		case ShaderConvert::COLCLIP_RESOLVE:
			return true;
		default:
			return false;
	}
}

static inline constexpr bool HasFloat32Output(ShaderConvert shader)
OLD
		case ShaderConvert::COLCLIP_RESOLVE:
		case ShaderConvert::XBR_UPSCALE:
			return true;
		default:
			return false;
	}
}

static inline constexpr bool HasFloat32Output(ShaderConvert shader)
NEW

patch("$root/pcsx2/GS/Renderers/Common/GSDevice.cpp",
<<'OLD', <<'NEW',
		case ShaderConvert::YUV:                    return "ps_yuv";
OLD
		case ShaderConvert::YUV:                    return "ps_yuv";
		case ShaderConvert::XBR_UPSCALE:            return "ps_xbr_upscale";
NEW
<<'OLD', <<'NEW');
		ENTRY(YUV);
OLD
		ENTRY(YUV);
		ENTRY(XBR_UPSCALE);
NEW

# shader sources: append the (already tested) xBR blocks
{
	my $hlsl = slurp("$scratch/block_hlsl.txt");
	my $ogl  = slurp("$scratch/block_ogl.txt");
	my $vk   = slurp("$scratch/block_vk.txt");
	my $mtl  = slurp("$scratch/block_metal.txt");
	for my $f ("$root/bin/resources/shaders/dx11/convert.fx") {
		my $s = slurp($f); $s =~ s/(#endif \/\/ PIXEL_SHADER\s*\z)/$hlsl$1/ or die "hlsl anchor"; open(my $fh,'>',$f) or die; binmode($fh); print $fh $s; close $fh; print "$f: xBR block\n";
	}
	for my $f ("$root/bin/resources/shaders/opengl/convert.glsl") {
		my $s = slurp($f); $s =~ s/(#endif\s*\z)/$ogl$1/ or die "ogl anchor"; open(my $fh,'>',$f) or die; binmode($fh); print $fh $s; close $fh; print "$f: xBR block\n";
	}
	for my $f ("$root/bin/resources/shaders/vulkan/convert.glsl") {
		my $s = slurp($f); $s =~ s/(#endif\s*\z)/$vk$1/ or die "vk anchor"; open(my $fh,'>',$f) or die; binmode($fh); print $fh $s; close $fh; print "$f: xBR block\n";
	}
	for my $f ("$root/pcsx2/GS/Renderers/Metal/convert.metal") {
		my $s = slurp($f); $s .= $mtl; open(my $fh,'>',$f) or die; binmode($fh); print $fh $s; close $fh; print "$f: xBR block\n";
	}
}

# ============================================================ Texture cache ============================================================
patch("$root/pcsx2/GS/Renderers/HW/GSTextureCache.h",
<<'OLD', <<'NEW',
	struct HashCacheEntry
	{
		GSTexture* texture;
		u32 refcount;
		u16 age;
		std::pair<u8, u8> alpha_minmax;
		bool valid_alpha_minmax;
		bool is_replacement;
	};
OLD
	struct HashCacheEntry
	{
		GSTexture* texture;
		u32 refcount;
		u16 age;
		std::pair<u8, u8> alpha_minmax;
		bool valid_alpha_minmax;
		bool is_replacement;
		// Filter 2D Images (xBR): lazily created xBR-upscaled copy of texture, used by flat 2D draws.
		GSTexture* upscaled = nullptr;
		u8 upscaled_factor = 0;
	};
NEW
<<'OLD', <<'NEW');
	static void AddDirtyRectTarget(Target* target, GSVector4i rect, u32 psm, u32 bw, RGBAMask rgba, bool req_linear = false);
OLD
	static void AddDirtyRectTarget(Target* target, GSVector4i rect, u32 psm, u32 bw, RGBAMask rgba, bool req_linear = false);

	/// Filter 2D Images (xBR): returns (creating on first use) the xBR-upscaled copy of a hash cache texture, or nullptr
	/// when the source can't be upscaled (targets, indexed/paletted, mipmapped, replacement or oversized textures).
	GSTexture* GetUpscaled2DTexture(Source* src, int factor);
	void ReleaseUpscaled2DTexture(HashCacheEntry& entry);
NEW

patch("$root/pcsx2/GS/Renderers/HW/GSTextureCache.cpp",
# --- Target::Update: filter decision + context read
<<'OLD', <<'NEW',
	const GSVector4i t_offset(total_rect.xyxy());
	const GSVector4i t_size(total_rect - t_offset);
	const GSVector4 t_sizef(t_size.zwzw());

	// This'll leave undefined data in pixels that we're not reading from... shouldn't hurt anything.
	GSTexture* const t = g_gs_device->CreateTexture(t_size.z, t_size.w, 1, GSTexture::Format::Color);
	if (!t) [[unlikely]]
	{
		Console.Error("Failed to allocate %dx%d for update source", t_size.z, t_size.w);
		return;
	}

	GSTexture::GSMap m;
	const bool mapped = t->Map(m);

	GIFRegTEXA TEXA = {};
	TEXA.AEM = 0;
	TEXA.TA0 = 0;
	TEXA.TA1 = 0x80;

	// Bilinear filtering this is probably not a good thing, at least in native, but upscaling Nearest can be gross and messy.
	// It's needed for depth, though.. filtering depth doesn't make much sense, but SMT3 needs it..
	const bool upscaled = (m_scale != 1.0f);
	const bool is_depth = m_type == DepthStencil;
	const bool override_linear = (upscaled && GSConfig.UserHacks_BilinearHack == GSBilinearDirtyMode::ForceBilinear);
	const bool linear = (upscaled && ((!is_depth && GSConfig.UserHacks_BilinearHack != GSBilinearDirtyMode::ForceNearest) || is_depth));
OLD
	// Bilinear filtering this is probably not a good thing, at least in native, but upscaling Nearest can be gross and messy.
	// It's needed for depth, though.. filtering depth doesn't make much sense, but SMT3 needs it..
	const bool upscaled = (m_scale != 1.0f);
	const bool is_depth = m_type == DepthStencil;
	const bool override_linear = (upscaled && GSConfig.UserHacks_BilinearHack == GSBilinearDirtyMode::ForceBilinear);
	const bool linear = (upscaled && ((!is_depth && GSConfig.UserHacks_BilinearHack != GSBilinearDirtyMode::ForceNearest) || is_depth));

	// Filter 2D Images: images the CPU writes straight into a render target (FMVs, pre-rendered backgrounds,
	// software-rendered 2D) are stretched with nearest by default since 2b49614df, which leaves them as blocks of
	// replicated pixels when upscaling. Bilinear/xBR filter every >= 16bpp dirty rect instead (4/8bpp uploads are
	// normally indexed data/CLUTs being moved around rather than images). Independent from the Bilinear Dirty Upscale
	// hardware fix: when this option is on, it decides the filter for those rects.
	const bool filter_2d_uploads = upscaled && !is_depth && GSConfig.Filter2D != GSFilter2DMode::Off;
	const int int_scale = static_cast<int>(m_scale);
	const bool want_xbr = filter_2d_uploads && GSConfig.Filter2D == GSFilter2DMode::xBR &&
	                      static_cast<float>(int_scale) == m_scale && int_scale >= 2;

	// xBR looks at a 2 texel neighbourhood, so read a little extra around the dirty area (from local memory) to avoid
	// seams where images are uploaded in strips across several updates. The extra pixels are only used as context.
	GSVector4i read_area = total_rect;
	if (want_xbr)
	{
		const GSVector2i& bs = GSLocalMemory::m_psm[m_TEX0.PSM].bs;
		read_area = GSVector4i(total_rect.x - 2, total_rect.y - 2, total_rect.z + 2, total_rect.w + 2)
		                .ralign<Align_Outside>(bs)
		                .rintersect(GSVector4i::loadh(m_unscaled_size));
	}

	const GSVector4i t_offset(read_area.xyxy());
	const GSVector4i t_size(read_area - t_offset);
	const GSVector4 t_sizef(t_size.zwzw());

	// This'll leave undefined data in pixels that we're not reading from... shouldn't hurt anything.
	GSTexture* const t = g_gs_device->CreateTexture(t_size.z, t_size.w, 1, GSTexture::Format::Color);
	if (!t) [[unlikely]]
	{
		Console.Error("Failed to allocate %dx%d for update source", t_size.z, t_size.w);
		return;
	}

	GSTexture::GSMap m;
	const bool mapped = t->Map(m);

	GIFRegTEXA TEXA = {};
	TEXA.AEM = 0;
	TEXA.TA0 = 0;
	TEXA.TA1 = 0x80;
NEW
<<'OLD', <<'NEW',
		const GSVector4i read_r = m_dirty.GetDirtyRect(i, m_TEX0, total_rect, true);
		const GSVector4i t_r(read_r - t_offset);
OLD
		GSVector4i read_r = m_dirty.GetDirtyRect(i, m_TEX0, total_rect, true);
		if (want_xbr)
		{
			const GSVector2i& bs = GSLocalMemory::m_psm[m_TEX0.PSM].bs;
			read_r = GSVector4i(read_r.x - 2, read_r.y - 2, read_r.z + 2, read_r.w + 2)
			             .ralign<Align_Outside>(bs)
			             .rintersect(read_area);
		}
		const GSVector4i t_r(read_r - t_offset);
NEW
<<'OLD', <<'NEW',
		drect.filter = BilnIf(linear && (is_depth || m_dirty[i].req_linear || override_linear));
OLD
		// Filter 2D Images: xBR rects are re-pointed at the pre-upscaled texture after the staging texture has been
		// filled (or fall back to bilinear if it can't be created); Bilinear mode just uses the bilinear stretch.
		const bool filter_2d_rect = filter_2d_uploads && GSLocalMemory::m_psm[m_dirty[i].psm].trbpp >= 16;
		const bool xbr_rect = want_xbr && filter_2d_rect;
		drect.filter = BilnIf((linear && (is_depth || m_dirty[i].req_linear || override_linear)) || (filter_2d_rect && !xbr_rect));
		if (xbr_rect)
			drect.src = nullptr;
NEW
<<'OLD', <<'NEW',
	if (mapped)
		t->Unmap();

	if (ndrects > 0)
	{
		if (m_type == RenderTarget && transferring_alpha && bpp >= 16)
OLD
	if (mapped)
		t->Unmap();

	// Filter 2D Images (xBR): upscale the whole staging texture once, then let the per-rect copies below sample the
	// pre-upscaled result 1:1, which keeps the write mask and alpha correction handling untouched.
	GSTexture* t_up = nullptr;
	if (want_xbr && ndrects > 0)
	{
		bool any_xbr = false;
		for (u32 i = 0; i < ndrects; i++)
			any_xbr |= (drects[i].src == nullptr);

		if (any_xbr)
		{
			const int up_w = t_size.z * int_scale;
			const int up_h = t_size.w * int_scale;
			const int max_size = static_cast<int>(g_gs_device->GetMaxTextureSize());
			if (up_w <= max_size && up_h <= max_size)
			{
				t_up = g_gs_device->CreateRenderTarget(up_w, up_h, GSTexture::Format::Color, false);
				if (t_up)
				{
					GL_INS("TC: Dirty upload xBR %dx%d -> %dx%d", t_size.z, t_size.w, up_w, up_h);
					g_gs_device->StretchRect(t, GSVector4(0.0f, 0.0f, 1.0f, 1.0f), t_up,
						GSVector4(0.0f, 0.0f, static_cast<float>(up_w), static_cast<float>(up_h)),
						ShaderConvert::XBR_UPSCALE, Nearest);
				}
			}

			for (u32 i = 0; i < ndrects; i++)
			{
				if (drects[i].src != nullptr)
					continue;

				if (t_up)
				{
					drects[i].src = t_up;
				}
				else
				{
					// Couldn't pre-upscale (texture would be too large), fall back to bilinear.
					drects[i].src = t;
					drects[i].filter = Biln;
				}
			}

			// Rect order is preserved on purpose (later uploads overwrite earlier ones), the backends start a new batch
			// whenever the source texture changes.
		}
	}

	if (ndrects > 0)
	{
		if (m_type == RenderTarget && transferring_alpha && bpp >= 16)
NEW
<<'OLD', <<'NEW',
	g_gs_device->Recycle(t);

	if (m_type == DepthStencil && g_texture_cache->GetTemporaryZ() != nullptr)
OLD
	g_gs_device->Recycle(t);
	if (t_up)
		g_gs_device->Recycle(t_up);

	if (m_type == DepthStencil && g_texture_cache->GetTemporaryZ() != nullptr)
NEW
# --- LookupDrawTarget: native target re-upscale
<<'OLD', <<'NEW',
		else
		{
			g_gs_device->StretchRectAuto(dst->m_texture, FullSrcRect, tex, rescaler.m_dRect,
				BilnIf(type == RenderTarget && !preserve_scale));
		}
OLD
		else if (type == RenderTarget && !preserve_scale && !is_shuffle && dst->m_downscaled && dst->m_scale == 1.0f &&
		         !dst->m_texture->IsDepthLike() && GSConfig.Filter2D == GSFilter2DMode::xBR &&
		         static_cast<float>(static_cast<int>(rescaler.m_scale)) == rescaler.m_scale && rescaler.m_scale >= 2.0f)
		{
			// Filter 2D Images (xBR): a native resolution target (Native Scaling) is being brought back to the upscaled
			// resolution. Use xBR instead of bilinear so 2D drawn while it was native (HUDs, videos) stays sharp.
			GL_INS("TC: Rescale native target with xBR");
			g_gs_device->StretchRect(dst->m_texture, FullSrcRect, tex, rescaler.m_dRect, ShaderConvert::XBR_UPSCALE, Nearest);
		}
		else
		{
			g_gs_device->StretchRectAuto(dst->m_texture, FullSrcRect, tex, rescaler.m_dRect,
				BilnIf(type == RenderTarget && !preserve_scale));
		}
NEW
# --- hash cache: upscaled texture lifetime
<<'OLD', <<'NEW',
	if (hash_cache)
	{
		for (auto it : m_hash_cache)
			g_gs_device->Recycle(it.second.texture);

		m_hash_cache.clear();
OLD
	if (hash_cache)
	{
		for (auto it : m_hash_cache)
		{
			if (it.second.upscaled)
				g_gs_device->Recycle(it.second.upscaled);
			g_gs_device->Recycle(it.second.texture);
		}

		m_hash_cache.clear();
NEW
<<'OLD', <<'NEW',
GSTextureCache::HashCacheMap::iterator GSTextureCache::RemoveFromHashCache(HashCacheMap::iterator it)
{
	HashCacheEntry& e = it->second;
	const u32 mem_usage = e.texture->GetMemUsage();
OLD
void GSTextureCache::ReleaseUpscaled2DTexture(HashCacheEntry& entry)
{
	if (!entry.upscaled)
		return;

	m_hash_cache_memory_usage -= entry.upscaled->GetMemUsage();
	g_gs_device->Recycle(entry.upscaled);
	entry.upscaled = nullptr;
	entry.upscaled_factor = 0;
}

GSTexture* GSTextureCache::GetUpscaled2DTexture(Source* src, int factor)
{
	HashCacheEntry* entry = src->m_from_hash_cache;
	if (!entry || entry->is_replacement || factor < 2 || !entry->texture ||
		entry->texture->GetFormat() != GSTexture::Format::Color || entry->texture->GetMipmapLevels() > 1)
	{
		return nullptr;
	}

	// Keep the output bounded: 10M pixels (40MB) per texture, and never above the device limit. Bigger textures get a
	// smaller factor, the sampler's bilinear filter covers the rest of the way to the internal resolution.
	const int tw = entry->texture->GetWidth();
	const int th = entry->texture->GetHeight();
	const int max_size = std::min<int>(static_cast<int>(g_gs_device->GetMaxTextureSize()), 4096);
	constexpr int max_pixels = 10 * 1024 * 1024;
	int f = factor;
	while (f >= 2 && (tw * f > max_size || th * f > max_size || (tw * f) * (th * f) > max_pixels))
		f--;
	if (f < 2)
		return nullptr;

	if (entry->upscaled && entry->upscaled_factor == f)
		return entry->upscaled;

	ReleaseUpscaled2DTexture(*entry);

	const int w = tw * f;
	const int h = th * f;
	GSTexture* up = g_gs_device->CreateRenderTarget(w, h, GSTexture::Format::Color, false);
	if (!up)
		return nullptr;

	GL_INS("TC: 2D texture upscale %dx%d -> %dx%d (xBR %dx)", tw, th, w, h, f);
	g_gs_device->StretchRect(entry->texture, GSVector4(0.0f, 0.0f, 1.0f, 1.0f), up,
		GSVector4(0.0f, 0.0f, static_cast<float>(w), static_cast<float>(h)), ShaderConvert::XBR_UPSCALE, Nearest);

	entry->upscaled = up;
	entry->upscaled_factor = static_cast<u8>(f);
	m_hash_cache_memory_usage += up->GetMemUsage();
	return up;
}

GSTextureCache::HashCacheMap::iterator GSTextureCache::RemoveFromHashCache(HashCacheMap::iterator it)
{
	HashCacheEntry& e = it->second;
	ReleaseUpscaled2DTexture(e);
	const u32 mem_usage = e.texture->GetMemUsage();
NEW
<<'OLD', <<'NEW');
	it->second.is_replacement = true;
	m_src.SwapTexture(it->second.texture, tex);
OLD
	it->second.is_replacement = true;
	ReleaseUpscaled2DTexture(it->second);
	m_src.SwapTexture(it->second.texture, tex);
NEW

# ============================================================ HW renderer ============================================================
patch("$root/pcsx2/GS/Renderers/HW/GSRendererHW.h",
<<'OLD', <<'NEW',
	GSTexture* GetOutput(int i, float& scale, int& y_offset) override;
	GSTexture* GetFeedbackOutput(float& scale) override;
OLD
	GSTexture* GetOutput(int i, float& scale, int& y_offset) override;
	GSTexture* GetFeedbackOutput(float& scale) override;
	/// Filter 2D Images (xBR): xBR-upscales a native resolution output target before it is merged/presented.
	GSTexture* UpscaleNativeOutput(GSTexture* t, float& scale, u32 slot);
	void ReleaseOutputUpscaleTextures();
	/// Filter 2D Images (xBR): xBR factor for local memory textures used by flat 2D draws (0 = off).
	int GetTexture2DUpscaleFactor() const;
NEW
<<'OLD', <<'NEW');
	std::unique_ptr<GSTextureCacheSW::Texture> m_sw_texture[7 + 1];
OLD
	std::unique_ptr<GSTextureCacheSW::Texture> m_sw_texture[7 + 1];
	GSTexture* m_output_upscale_tex[3] = {};
NEW

patch("$root/pcsx2/GS/Renderers/HW/GSRendererHW.cpp",
<<'OLD', <<'NEW',
void GSRendererHW::Destroy()
{
	g_texture_cache->RemoveAll(true, true, true);
	GSRenderer::Destroy();
}

void GSRendererHW::PurgeTextureCache(bool sources, bool targets, bool hash_cache)
{
	g_texture_cache->RemoveAll(sources, targets, hash_cache);
}
OLD
void GSRendererHW::Destroy()
{
	ReleaseOutputUpscaleTextures();
	g_texture_cache->RemoveAll(true, true, true);
	GSRenderer::Destroy();
}

void GSRendererHW::PurgeTextureCache(bool sources, bool targets, bool hash_cache)
{
	if (targets)
		ReleaseOutputUpscaleTextures();
	g_texture_cache->RemoveAll(sources, targets, hash_cache);
}

void GSRendererHW::ReleaseOutputUpscaleTextures()
{
	for (GSTexture*& tex : m_output_upscale_tex)
	{
		if (tex)
		{
			g_gs_device->Recycle(tex);
			tex = nullptr;
		}
	}
}

int GSRendererHW::GetTexture2DUpscaleFactor() const
{
	if (GSConfig.Filter2D != GSFilter2DMode::xBR)
		return 0;

	// Up to 6x; never go beyond the internal resolution multiplier, it would only cost memory.
	return std::min(6, static_cast<int>(GSConfig.UpscaleMultiplier));
}

GSTexture* GSRendererHW::UpscaleNativeOutput(GSTexture* t, float& scale, u32 slot)
{
	// Filter 2D Images (xBR): frames that ended up at native resolution (Native Scaling downscaled targets, e.g. videos
	// and post-processed frames) would otherwise be presented as blocks of replicated pixels. Upscale them with xBR first.
	const float upscale = GetUpscaleMultiplier();
	const int factor = static_cast<int>(upscale);
	if (!t || GSConfig.Filter2D != GSFilter2DMode::xBR || scale != 1.0f || t->IsDepthLike() ||
		static_cast<float>(factor) != upscale || factor < 2)
	{
		return t;
	}

	const int width = t->GetWidth() * factor;
	const int height = t->GetHeight() * factor;
	const int max_size = static_cast<int>(g_gs_device->GetMaxTextureSize());
	if (width > max_size || height > max_size)
		return t;

	GSTexture*& cache = m_output_upscale_tex[slot];
	if (cache && (cache->GetWidth() != width || cache->GetHeight() != height))
	{
		g_gs_device->Recycle(cache);
		cache = nullptr;
	}
	if (!cache)
	{
		cache = g_gs_device->CreateRenderTarget(width, height, GSTexture::Format::Color, false);
		if (!cache)
			return t;
	}

	GL_INS("HW: Upscaling native output %dx%d with xBR (slot %u)", t->GetWidth(), t->GetHeight(), slot);
	g_gs_device->StretchRect(t, GSVector4(0.0f, 0.0f, 1.0f, 1.0f), cache,
		GSVector4(0.0f, 0.0f, static_cast<float>(width), static_cast<float>(height)), ShaderConvert::XBR_UPSCALE, Nearest);
	scale = upscale;
	return cache;
}
NEW
<<'OLD', <<'NEW',
		if (GSConfig.SaveFrame && GSConfig.ShouldDump(s_n, g_perfmon.GetFrame()))
		{
			t->Save(GetDrawDumpPath("%05lld_f%05lld_fr%d_%05x_%s.bmp", s_n, g_perfmon.GetFrame(), i, static_cast<int>(TEX0.TBP0), GSUtil::GetPSMName(TEX0.PSM)));
		}
	}

	return t;
}
OLD
		if (GSConfig.SaveFrame && GSConfig.ShouldDump(s_n, g_perfmon.GetFrame()))
		{
			t->Save(GetDrawDumpPath("%05lld_f%05lld_fr%d_%05x_%s.bmp", s_n, g_perfmon.GetFrame(), i, static_cast<int>(TEX0.TBP0), GSUtil::GetPSMName(TEX0.PSM)));
		}

		t = UpscaleNativeOutput(t, scale, static_cast<u32>(index));
	}

	return t;
}
NEW
<<'OLD', <<'NEW',
	if (GSConfig.SaveFrame && GSConfig.ShouldDump(s_n, g_perfmon.GetFrame()))
		t->Save(GetDrawDumpPath("%05lld_f%05lld_fr%d_%05x_%s.bmp", s_n, g_perfmon.GetFrame(), 3, static_cast<int>(TEX0.TBP0), GSUtil::GetPSMName(TEX0.PSM)));

	return t;
}
OLD
	if (GSConfig.SaveFrame && GSConfig.ShouldDump(s_n, g_perfmon.GetFrame()))
		t->Save(GetDrawDumpPath("%05lld_f%05lld_fr%d_%05x_%s.bmp", s_n, g_perfmon.GetFrame(), 3, static_cast<int>(TEX0.TBP0), GSUtil::GetPSMName(TEX0.PSM)));

	return UpscaleNativeOutput(t, scale, 2);
}
NEW
<<'OLD', <<'NEW',
	// don't overwrite the texture when using channel shuffle, but keep the palette
	if (!m_channel_shuffle)
	{
		m_conf.cb_ps.ChannelShuffleOffset = GSVector2(0, 0);
		m_conf.tex = tex->m_texture;
	}
	m_conf.pal = tex->m_palette;
OLD
	// Filter 2D Images: flat 2D draws are sprites, or triangles/quads with constant depth (HUDs, menus, backgrounds
	// drawn as textured quads, FMVs drawn as a full screen sprite).
	const bool is_2d_draw = (m_vt.m_primclass == GS_SPRITE_CLASS) || (m_vt.m_primclass == GS_TRIANGLE_CLASS && m_vt.m_eq.z);
	const bool filter_2d_draw = GSConfig.Filter2D != GSFilter2DMode::Off && is_2d_draw;

	// don't overwrite the texture when using channel shuffle, but keep the palette
	GSTexture* upscaled_2d = nullptr;
	if (!m_channel_shuffle)
	{
		m_conf.cb_ps.ChannelShuffleOffset = GSVector2(0, 0);
		m_conf.tex = tex->m_texture;

		// Filter 2D Images (xBR): flat 2D draws that sample a local memory texture use an xBR-upscaled copy of it, so
		// HUDs, menus, backgrounds and videos aren't blocks of replicated texels at higher internal resolutions. 3D
		// geometry, target sources, GPU palette (indexed) textures, mipmapped draws and replacement textures are left
		// alone. Texture coordinates are normalised by the nominal size, so a larger texture samples correctly without
		// any other change (same mechanism as HD texture replacements).
		const int factor_2d = GetTexture2DUpscaleFactor();
		if (factor_2d >= 2 && is_2d_draw && !tex->m_target && !tex->m_palette && tex->m_from_hash_cache && !IsMipMapDraw())
		{
			upscaled_2d = g_texture_cache->GetUpscaled2DTexture(tex, factor_2d);
			if (upscaled_2d)
				m_conf.tex = upscaled_2d;
		}
	}
	m_conf.pal = tex->m_palette;
NEW
<<'OLD', <<'NEW');
	bool bilinear = m_vt.IsLinear();
	int trilinear = 0;
OLD
	// Filter 2D Images: flat 2D draws are sampled bilinearly even if the game asked for nearest (like Texture Filtering
	// "Forced" restricted to 2D). The usual exceptions below (texture shuffles, palette-from-target, depth) still apply.
	bool bilinear = m_vt.IsLinear() || filter_2d_draw;
	int trilinear = 0;
NEW

# ============================================================ Overlay / Big Picture ============================================================
patch("$root/pcsx2/ImGui/ImGuiOverlays.cpp",
<<'OLD', <<'NEW');
		if (GSConfig.UserHacks_BilinearHack != GSBilinearDirtyMode::Automatic)
			APPEND("BLU={} ", static_cast<unsigned>(GSConfig.UserHacks_BilinearHack));
OLD
		if (GSConfig.UserHacks_BilinearHack != GSBilinearDirtyMode::Automatic)
			APPEND("BLU={} ", static_cast<unsigned>(GSConfig.UserHacks_BilinearHack));
		if (GSConfig.Filter2D != GSFilter2DMode::Off)
			APPEND("F2D={} ", static_cast<unsigned>(GSConfig.Filter2D));
NEW

patch("$root/pcsx2/ImGui/FullscreenUI_Settings.cpp",
<<'OLD', <<'NEW',
	static constexpr const char* s_trilinear_options[] = {
OLD
	static constexpr const char* s_filter_2d_options[] = {
		FSUI_NSTR("Off (Default)"),
		FSUI_NSTR("Bilinear"),
		FSUI_NSTR("xBR"),
	};
	static constexpr const char* s_trilinear_options[] = {
NEW
<<'OLD', <<'NEW',
		DrawIntListSetting(bsi, FSUI_ICONSTR(ICON_FA_TABLE_CELLS_LARGE, "Trilinear Filtering"),
			FSUI_CSTR("Selects where trilinear filtering is utilized when rendering textures."), "EmuCore/GS", "TriFilter",
			static_cast<int>(TriFiltering::Automatic), s_trilinear_options, std::size(s_trilinear_options), true, -1);
OLD
		DrawIntListSetting(bsi, FSUI_ICONSTR(ICON_FA_TABLE_CELLS_LARGE, "Trilinear Filtering"),
			FSUI_CSTR("Selects where trilinear filtering is utilized when rendering textures."), "EmuCore/GS", "TriFilter",
			static_cast<int>(TriFiltering::Automatic), s_trilinear_options, std::size(s_trilinear_options), true, -1);
		DrawIntListSetting(bsi, FSUI_ICONSTR(ICON_FA_IMAGE, "Filter 2D Images"),
			FSUI_CSTR("Filters 2D images that are otherwise left as replicated pixels when upscaling: images written directly to video memory (FMVs, pre-rendered backgrounds), native resolution frames and the textures of flat 2D draws (HUDs, menus, sprites). Off behaves like stock PCSX2."),
			"EmuCore/GS", "Filter2D", static_cast<int>(GSFilter2DMode::Off), s_filter_2d_options, std::size(s_filter_2d_options), true);
NEW
<<'OLD', <<'NEW');
TRANSLATE_NOOP("FullscreenUI", "Bilinear (Forced)");
OLD
TRANSLATE_NOOP("FullscreenUI", "Bilinear (Forced)");
TRANSLATE_NOOP("FullscreenUI", "Filter 2D Images");
TRANSLATE_NOOP("FullscreenUI", "Filters 2D images that are otherwise left as replicated pixels when upscaling: images written directly to video memory (FMVs, pre-rendered backgrounds), native resolution frames and the textures of flat 2D draws (HUDs, menus, sprites). Off behaves like stock PCSX2.");
TRANSLATE_NOOP("FullscreenUI", "Off (Default)");
TRANSLATE_NOOP("FullscreenUI", "Bilinear");
TRANSLATE_NOOP("FullscreenUI", "xBR");
NEW

# ============================================================ Qt ============================================================
{
	my $ui = "$root/pcsx2-qt/Settings/GraphicsHardwareRenderingSettingsTab.ui";
	my $src = slurp($ui);
	my $c = 0;
	$c += ($src =~ s/   <item row="6" column="0" colspan="2">\n    <layout class="QGridLayout" name="hardwareRenderingOptionsLayout">/   <item row="7" column="0" colspan="2">\n    <layout class="QGridLayout" name="hardwareRenderingOptionsLayout">/);
	$c += ($src =~ s/   <item row="7" column="0">\n    <spacer name="verticalSpacer">/   <item row="8" column="0">\n    <spacer name="verticalSpacer">/);
	my $newrow = <<'EOT';
   <item row="6" column="0">
    <widget class="QLabel" name="filter2DLabel">
     <property name="text">
      <string>Filter 2D Images:</string>
     </property>
     <property name="buddy">
      <cstring>filter2D</cstring>
     </property>
    </widget>
   </item>
   <item row="6" column="1">
    <widget class="QComboBox" name="filter2D">
     <item>
      <property name="text">
       <string>Off (Default)</string>
      </property>
     </item>
     <item>
      <property name="text">
       <string>Bilinear</string>
      </property>
     </item>
     <item>
      <property name="text">
       <string>xBR</string>
      </property>
     </item>
    </widget>
   </item>
EOT
	$c += ($src =~ s/(   <item row="7" column="0" colspan="2">\n    <layout class="QGridLayout" name="hardwareRenderingOptionsLayout">)/$newrow$1/);
	die "ui: $c/3\n" if $c != 3;
	open(my $fh, '>', $ui) or die; binmode($fh); print $fh $src; close $fh;
	print "$ui: 3/3\n";
}

patch("$root/pcsx2-qt/Settings/GraphicsSettingsWidget.cpp",
<<'OLD', <<'NEW',
	SettingWidgetBinder::BindWidgetToIntSetting(sif, m_hw.dithering, "EmuCore/GS", "dithering_ps2", 2);
OLD
	SettingWidgetBinder::BindWidgetToIntSetting(sif, m_hw.dithering, "EmuCore/GS", "dithering_ps2", 2);
	SettingWidgetBinder::BindWidgetToIntSetting(sif, m_hw.filter2D, "EmuCore/GS", "Filter2D", static_cast<int>(GSFilter2DMode::Off));
NEW
<<'OLD', <<'NEW');
		dialog()->registerWidgetHelp(m_hw.trilinearFiltering, tr("Trilinear Filtering"), tr("Automatic (Default)"),
OLD
		dialog()->registerWidgetHelp(
			m_hw.filter2D, tr("Filter 2D Images"), tr("Off (Default)"),
			tr("Filters 2D images that stock PCSX2 leaves as blocks of replicated pixels when upscaling: images the game writes "
			   "directly into video memory (FMVs, pre-rendered backgrounds, software-rendered 2D), frames kept at native resolution "
			   "by Native Scaling, and the textures used by flat 2D draws (HUDs, menus, sprites), which are also sampled bilinearly "
			   "even when the game asked for nearest.<br> "
			   "Off: identical to stock PCSX2.<br> "
			   "Bilinear: smooths them.<br> "
			   "xBR: edge-preserving upscaler (Hyllian's xBR) that keeps lines and text sharp; 2D textures are upscaled up to 6x. "
			   "Never touches 3D geometry, render target sources, GPU palette textures or HD texture replacements.<br> "
			   "Independent from the Bilinear Dirty Upscale hardware fix. Has no effect at native resolution."));

		dialog()->registerWidgetHelp(m_hw.trilinearFiltering, tr("Trilinear Filtering"), tr("Automatic (Default)"),
NEW

print "filter2d v2 patched\n";
