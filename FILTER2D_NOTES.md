# Filter 2D Images (Off / Bilinear / xBR) — Branch Notes (`filter2d`)

Custom PCSX2 branch that adds **one setting, off by default**: *Filter 2D Images* in Graphics → Rendering
(Qt: drop-down under Blending; also in the Big Picture graphics settings; ini key `EmuCore/GS/Filter2D`,
0 = Off, 1 = Bilinear, 2 = xBR). With it Off the build behaves exactly like stock PCSX2. It is independent from
the *Bilinear Dirty Upscale* hardware fix, which keeps its stock default.

Maintained with the help of Claude (Anthropic). This file is written so that anyone (or any AI assistant)
can understand, rebase and rebuild the branch without any other context.

## The problem it solves

At internal resolutions above native, stock PCSX2 leaves several kinds of 2D content as blocks of replicated
pixels:

1. Images the CPU writes straight into a render target (FMV frames decoded by the IPU, pre-rendered
   backgrounds, software-rendered 2D, some HUD layers). `GSTextureCache::Target::Update()` stretches them
   into the upscaled target with nearest since upstream `2b49614df` (March 2023) unless the Bilinear Dirty
   Upscale hack is forced.
2. Frames kept at native resolution by the *Native Scaling* fix (GameDB `nativeScaling`, e.g. Dragon Quest
   VIII, Shadow of the Colossus): they are re-upscaled bilinearly or presented at native resolution.
3. The common case: textures used by flat 2D draws (sprites, HUDs, menus, full-screen video quads) are native
   resolution textures sampled with whatever filter the game asked for, usually nearest.

## What each mode does

| | Bilinear | xBR |
|---|---|---|
| CPU → render target uploads (`Target::Update`, >= 16bpp rects, upscaled colour targets) | bilinear stretch | staging texture xBR-upscaled once (`XBR_UPSCALE`) then copied 1:1 (write masks / alpha correction untouched); 2 texel context is read around each rect to avoid seams; falls back to bilinear for non-integer scales or oversized textures |
| Native resolution target brought back to the upscaled resolution (`LookupDrawTarget` rescale, `!preserve_scale`, non-shuffle) | stock (bilinear) | xBR |
| Display of a target still at scale 1 while upscaling (`GetOutput` / `GetFeedbackOutput`) | stock | `UpscaleNativeOutput()` xBR-upscales into a cached per-circuit texture and reports the upscaled scale to `GSRenderer::VSync` |
| Textures used by flat 2D draws (`EmulateTextureSampler`, sprite class or triangle class with constant Z, local memory, non-palette, hash cached, no mipmaps, not a replacement) | sampled bilinearly | `GetUpscaled2DTexture()`: lazily created xBR copy, factor `min(6, upscale)`, bounded by 10M pixels / 4096 / device limit, sampled bilinearly |
| Sampler for flat 2D draws | bilinear forced | bilinear forced |

4/8bpp uploads are never filtered (indexed data / CLUTs being moved). Depth targets, texture shuffles,
palette-from-target sources and 3D geometry are never touched. The overlay settings line shows `F2D=1|2`.

xBR is Hyllian's xBR (MIT) as implemented in DuckStation, ported to PCSX2's convert shaders for all backends
(HLSL for D3D11/D3D12, GLSL for OpenGL and Vulkan, Metal). The shader needs no constant buffer: it derives the
integer scale from the texture coordinate derivative (`fwidth(uv) * textureSize`). Block centres keep the exact
source colour, so nearest readbacks of uploaded data stay bit-exact.

## Files touched (conflict hotspots for rebases)

| File | Change |
|------|--------|
| `pcsx2/Config.h` | `enum class GSFilter2DMode` after `GSBilinearDirtyMode`; `GSFilter2DMode Filter2D = Off` after `TextureFiltering` |
| `pcsx2/Pcsx2Config.cpp` | `OpEqu(Filter2D)` after `TextureFiltering`; `SettingsWrapIntEnumEx(Filter2D, "Filter2D")` after `filter` |
| `pcsx2/GS/Renderers/Common/GSDevice.h` / `.cpp` | `ShaderConvert::XBR_UPSCALE` (before `Count`), `HasColorOutput`, entry point `ps_xbr_upscale`, `ShaderConvertName` (the packed shader list is generated from the enum) |
| `bin/resources/shaders/dx11/convert.fx`, `opengl/convert.glsl`, `vulkan/convert.glsl`, `pcsx2/GS/Renderers/Metal/convert.metal` | `ps_xbr_upscale` block appended at the end of the pixel shader section |
| `pcsx2/GS/Renderers/HW/GSTextureCache.h` | `HashCacheEntry::upscaled/upscaled_factor`; `GetUpscaled2DTexture()`, `ReleaseUpscaled2DTexture()` |
| `pcsx2/GS/Renderers/HW/GSTextureCache.cpp` | `Target::Update()` (decision next to `override_linear`/`linear`, context read, per-rect filter, `t_up` pass and recycle); `LookupDrawTarget` rescale branch; hash cache release in `RemoveAll`, `RemoveFromHashCache`, `InjectHashCacheTexture`; the two new functions before `RemoveFromHashCache` |
| `pcsx2/GS/Renderers/HW/GSRendererHW.h` / `.cpp` | `m_output_upscale_tex[3]`, `UpscaleNativeOutput()`, `ReleaseOutputUpscaleTextures()`, `GetTexture2DUpscaleFactor()`; calls in `Destroy()`, `PurgeTextureCache()`, `GetOutput()`, `GetFeedbackOutput()`; `EmulateTextureSampler()` (texture swap at `m_conf.tex`, `bilinear` initial value) |
| `pcsx2/ImGui/ImGuiOverlays.cpp` | `F2D=` in the settings line |
| `pcsx2/ImGui/FullscreenUI_Settings.cpp` | `s_filter_2d_options`, `DrawIntListSetting` after Trilinear Filtering, `TRANSLATE_NOOP` strings |
| `pcsx2-qt/Settings/GraphicsHardwareRenderingSettingsTab.ui` | label + combo at grid row 6; options layout moved to row 7, spacer to row 8 |
| `pcsx2-qt/Settings/GraphicsSettingsWidget.cpp` | `BindWidgetToIntSetting(... "Filter2D", 0)` after dithering; help text before Trilinear Filtering |
| `.github/workflows/windows-x64-custom.yml` | fork-only CI |

The whole branch is a single commit on top of the upstream base, which keeps rebases simple. The complete
patch is reproducible from the script that generated it: `filter2d-patch/patch_filter2d_v2.pl <repo root> filter2d-patch`
applied to a clean upstream checkout (it needs the `block_*.txt` shader blocks next to it). If an anchor no longer
matches after an upstream change, the concepts above are what matters.

## Rebasing onto upstream

```bash
git clone https://github.com/Forgottenshadow89/pcsx2.git
cd pcsx2
git remote add upstream https://github.com/PCSX2/pcsx2.git
git config core.autocrlf false      # keep LF, the diffs assume it
git config core.eol lf

git fetch upstream
git checkout filter2d
git rebase upstream/master
# resolve conflicts in the files above, then:
git push --force-with-lease origin filter2d
```

Rebase hints: `Target::Update()` and `EmulateTextureSampler()` are the likely conflict points. If upstream
restructures them, re-apply the concepts from the table: decide `filter_2d_uploads`/`want_xbr` next to the
existing `override_linear`/`linear` booleans and route xBR rects through the pre-upscaled staging texture;
in the sampler, swap `m_conf.tex` for the upscaled copy on flat 2D draws and start `bilinear` as true for them.
If upstream renames the convert shader entry-point scheme, the xBR block only needs the `#if defined(__ps_xbr_upscale__)`
(HLSL) / `#ifdef ps_xbr_upscale` (GLSL) guards adjusted.

## Building (GitHub Actions, no local toolchain needed)

- Workflow `Windows x64 (Filter 2D)` (`.github/workflows/windows-x64-custom.yml`) runs on every push to
  `filter2d` and on manual dispatch. It reuses upstream's `windows_deps_build.yml` (cached dependencies) and
  `windows_build_qt.yml` (MSVC, AVX2). First run on a fresh fork ~2 h (dependency cache), later ~30 min.
- Artifact `PCSX2-windows-Qt-x64-avx2-msvc-filter2d-sha[<short sha>]` = the full `bin/` folder; the executable
  is `pcsx2-qtx64-avx2.exe`. Because `bin/resources/shaders` changes, install the whole artifact (or at least
  `resources/shaders`) together with the executable; an official executable of the same upstream commit also
  runs fine with these resources (the extra shader blocks are inert for it).
- `gh run download <run id> -R Forgottenshadow89/pcsx2 -p "PCSX2-windows-Qt-x64-avx2-msvc-filter2d*"`.
- The stock matrix workflows (Windows/Linux/macOS builds) are disabled on the fork (`gh workflow disable`), so
  each push produces exactly one build. A Linux/macOS build can be re-enabled temporarily to validate GLSL/Metal.

## Verifying

Set *Filter 2D Images* and restart the game. GS dumps (`Debug → Save Single Frame GS Dump`) replay with the
current settings in `pcsx2-qt.exe -batch -nogui <dump.gs>`, which makes A/B comparisons easy without a game
running. Checked on 2026-09-12 with dumps of Dragon Quest VIII (intro FMV: 512x448 frame uploaded as 16x16
macroblocks and drawn as one full-screen sprite) and Shadow of the Colossus (HUD): Off = replicated pixels,
xBR = clean edges, 3D pixel-identical between modes. Note for SotC: blocky HUD icons in that game come from
the HD texture pack (nearest-upscaled DDS), not from the emulator.

## Known limitations

- xBR needs an integer internal resolution multiplier; 1.25x/1.5x/1.75x fall back to bilinear for uploads.
- 2D textures are upscaled at most 6x (and within a 40MB per-texture budget: 512x512 textures get 6x, 1024x1024 ones 3x); the bilinear sampler covers the rest.
- In games using Native Scaling, 3D that was rendered at native resolution is also xBR-upscaled by the
  display/rescale hooks. Set the option to Off or Bilinear per game if that is unwanted.
- The option applies regardless of GameDB `bilinearUpscale` entries; set it per game if a game misbehaves.
