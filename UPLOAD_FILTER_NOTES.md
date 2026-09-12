# 2D Upload Filter (xBR / bilinear for CPU -> framebuffer uploads) — Branch Notes

Custom PCSX2 branch (`upload-filter`) that stops 2D images written directly into video memory
(FMVs, pre-rendered backgrounds, software-rendered 2D, some HUD/menu layers) from looking pixelated
when the internal resolution is above native. It is the PCSX2 counterpart of the DuckStation
`vram-write-filtering` branch (`Forgottenshadow89/Duckstation`).

Maintained with the help of Claude (Anthropic). This file documents everything needed to understand
and rebase the branch without any other context. Windows x64 builds are produced by the GitHub
Actions workflow `.github/workflows/windows-x64-custom.yml` (artifact
`PCSX2-windows-Qt-x64-avx2-msvc-upload-filter-sha[...]`, downloadable from each run for 90 days).

## The problem

The GS texture cache keeps render targets at the upscaled resolution. When the game (EE/CPU) writes an
image straight into a region that is tracked as a render target, the cache marks it dirty and
`GSTextureCache::Target::Update()` re-reads that region from GS local memory (native resolution) and
stretches it into the scaled target. Up to March 2023 that stretch was bilinear; commit
`2b49614df` ("GS-HW: Don't bilinear dirty rects by default, added as upscale hack") switched the
default to nearest (pixel replication) and moved bilinear behind the *Bilinear Dirty Upscale*
hardware fix (`UserHacks_BilinearHack`, needs *Manual Hardware Renderer Fixes*; also settable per
game via the GameDB `bilinearUpscale` key: 1 = Force Bilinear, 2 = Force Nearest).

Textured sprites drawn from local memory are not affected by this: *Texture Filtering: Bilinear
(Forced)* already filters them in the sampler. Only the direct-upload path was pixelated.

## What the branch adds

New GS setting `EmuCore/GS/DirtyUploadFilter` (enum `GSDirtyUploadFilter`: 0 Nearest, 1 Bilinear,
2 xBR; **default xBR in this branch**), exposed as *2D Upload Filter* in Graphics → Rendering (Qt) and
in the Big Picture graphics settings. It is a normal setting, not a hardware fix, so it does not
need *Manual Hardware Renderer Fixes*, and it can be overridden per game.

Rules implemented in `GSTextureCache::Target::Update()`:

| Situation | Result |
|-----------|--------|
| Native resolution, or depth targets | Unchanged upstream behaviour |
| `UserHacks_BilinearHack` = Force Nearest / Force Bilinear (user or GameDB) | Unchanged upstream behaviour — the hardware fix wins |
| Automatic + filter Nearest | Unchanged upstream behaviour (nearest, except the preload rects upstream already marks `req_linear`) |
| Automatic + filter Bilinear | Every >= 16bpp dirty rect is stretched bilinearly |
| Automatic + filter xBR, integer scale >= 2 | Every >= 16bpp dirty rect goes through the xBR pass (below); 4/8bpp rects stay nearest |
| Automatic + filter xBR, non-integer scale (1.25x, 1.5x, ...) | Falls back to bilinear |

4/8bpp uploads are left alone because they are normally palette indices / CLUT data being moved
through the framebuffer rather than pictures.

### The xBR pass

- `ShaderConvert::XBR_UPSCALE` (`ps_xbr_upscale`) implemented for all backends: HLSL
  (`bin/resources/shaders/dx11/convert.fx`, shared by D3D11 and D3D12), OpenGL and Vulkan GLSL
  (`bin/resources/shaders/opengl|vulkan/convert.glsl`) and Metal
  (`pcsx2/GS/Renderers/Metal/convert.metal`). It is Hyllian's xBR (MIT), the same algorithm used in
  the DuckStation branch, working on RGBA with `texelFetch`/`Load` and clamped neighbours.
- No new constant buffer: the shader derives the integer upscale factor from the texture coordinate
  derivative (`fwidth(uv) * textureSize`), so no backend-specific plumbing was needed.
- Two-pass approach in `Target::Update()`: the whole staging texture `t` (native size) is upscaled
  once into a temporary render target `t_up` (`t_size * scale`), then the existing
  `DrawMultiStretchRects` copies the dirty rects 1:1 from `t_up` instead of `t`. This keeps the
  per-rect write masks (`rgba`), the RTA alpha correction shader selection and the rect order exactly
  as upstream. If `t_up` would exceed the device's maximum texture size the rects fall back to
  bilinear.
- Context: with xBR active the staging texture and every `read_r` are grown by 2 texels (block
  aligned, clamped to the target size) so that neighbours come from local memory instead of being
  clamped, avoiding seams for images uploaded in strips over several updates.
- Readback exactness: xBR only reshapes block corners along detected edges, so the centre of every
  scaled block keeps the exact source colour. `GSTextureCache::Read()` samples block centres with
  nearest filtering, therefore CPU readbacks of uploaded data stay bit-exact (better than the
  bilinear hack, which blends).

### Native Scaling paths (second commit)

Dragon Quest VIII and Shadow of the Colossus (and ~all GameDB entries with `nativeScaling`) never hit
the dirty-upload path: Native Scaling downscales targets to native resolution (`Target::m_downscaled`,
`m_scale == 1`) for post-processing, and 2D drawn while the target is native (HUDs) or whole video frames
end up either re-upscaled with bilinear/nearest or presented at native resolution. Two more hooks apply
xBR there when the filter is set to xBR and the upscale factor is an integer >= 2:

- `GSTextureCache::LookupDrawTarget` rescale block: a downscaled colour target being brought back to the
  upscaled resolution (the `!preserve_scale`, non-shuffle case that upstream stretches bilinearly) is
  upscaled with `XBR_UPSCALE` instead.
- `GSRendererHW::GetOutput` / `GetFeedbackOutput`: if the display target is still at scale 1 while the
  upscale multiplier is > 1, `UpscaleNativeOutput()` xBR-upscales it into a cached per-circuit render
  target (`m_output_upscale_tex[3]`, released in `Destroy()` / `PurgeTextureCache()`) and reports the
  upscaled scale to `GSRenderer::VSync`, so merge/present treat it like a normally upscaled frame.

Note this also runs xBR over 3D content that was rendered at native resolution because of Native Scaling;
set the filter to Nearest/Bilinear per game if that is unwanted.

### Files touched (conflict hotspots for rebases)

- `pcsx2/GS/Renderers/HW/GSTextureCache.cpp` — `Target::Update()` (filter decision, context read, xBR
  pass, per-rect source/filter selection, `t_up` recycle) and the rescale block in `LookupDrawTarget`.
- `pcsx2/GS/Renderers/HW/GSRendererHW.cpp` / `.h` — `UpscaleNativeOutput()`, `ReleaseOutputUpscaleTextures()`,
  calls in `GetOutput()`/`GetFeedbackOutput()`/`Destroy()`/`PurgeTextureCache()`.
- `pcsx2/GS/Renderers/Common/GSDevice.h` / `.cpp` — `ShaderConvert::XBR_UPSCALE`, `HasColorOutput`,
  entry point / name tables (the packed shader list is generated automatically from the enum).
- `bin/resources/shaders/dx11/convert.fx`, `bin/resources/shaders/opengl/convert.glsl`,
  `bin/resources/shaders/vulkan/convert.glsl`, `pcsx2/GS/Renderers/Metal/convert.metal` — the
  `ps_xbr_upscale` block appended at the end of the pixel shader section.
- `pcsx2/Config.h`, `pcsx2/Pcsx2Config.cpp` — enum, member, `operator==`, `LoadSave`.
- `pcsx2-qt/Settings/GraphicsHardwareRenderingSettingsTab.ui` (new grid row 6; options layout and
  spacer moved to rows 7/8), `pcsx2-qt/Settings/GraphicsSettingsWidget.cpp` (binding + help text).
- `pcsx2/ImGui/FullscreenUI_Settings.cpp` (Big Picture setting + `TRANSLATE_NOOP` strings),
  `pcsx2/ImGui/ImGuiOverlays.cpp` (`UPF=` in the settings OSD line).
- `.github/workflows/windows-x64-custom.yml` — CI.

## How to rebase onto upstream

```bash
git clone https://github.com/Forgottenshadow89/pcsx2.git
cd pcsx2
git remote add upstream https://github.com/PCSX2/pcsx2.git
git config core.autocrlf false
git config core.eol lf

git fetch upstream
git checkout upload-filter
git rebase upstream/master
# resolve conflicts (most likely in GSTextureCache.cpp Target::Update, or the .ui grid row numbers)
git push --force-with-lease origin upload-filter
```

If upstream restructures `Target::Update()`, re-apply the concepts from the table above rather than
the literal diff: decide `filter_uploads`/`want_xbr` next to the existing `override_linear`/`linear`
booleans, grow the read area when xBR is on, upscale `t` into `t_up` after `t->Unmap()`, and point
the qualifying rects at `t_up` with nearest filtering.

## Verifying after a rebase

At 4x-6x internal resolution with the filter set to xBR check that: (1) FMVs and pre-rendered
backgrounds are no longer blocky and have clean edges (compare with *Nearest*); (2) 3D rendering and
HUD sprites are unchanged; (3) a game with GameDB `bilinearUpscale: 2` (e.g. the ones listed in
`bin/resources/GameIndex.yaml`) still renders as upstream; (4) save states and screenshots work.
Per-game switch: Game Properties → Graphics → Rendering → 2D Upload Filter.

## Known limitations

- Non-integer internal resolutions get bilinear instead of xBR.
- 4/8bpp uploads are never filtered (by design).
- Uploads that only write some channels (e.g. font data into alpha) are filtered using all channels
  for edge detection; no game is known to be affected, use *Nearest* per game if one is.
