#+build windows
package r

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"

Glyph :: struct {
	advance:     f32,
	atlasBounds: MSDF_Bounds,
	planeBounds: MSDF_Bounds,
}

Font :: struct {
	atlas:   D3D11_Tex2D,
	// distanceRange: f32, hardcoded to 8
	metrics: MSDF_Metrics,
	glyphs:  map[rune]Glyph,
	// kerning: map[[2]rune]f32,
}

//
// Parsing
//
MSDF_Atlas :: struct {
	// dont change var names
	type:                string,
	distanceRange:       f32,
	distanceRangeMiddle: f32,
	size:                f32,
	width, height:       i32,
	yOrigin:             string,
}

MSDF_Metrics :: struct {
	// dont change var names
	emSize:             f32,
	lineHeight:         f32,
	ascender:           f32,
	descender:          f32,
	underlineY:         f32,
	underlineThickness: f32,
}

// MSDF_KerningPair :: struct {
// 	// dont change var names
// 	unicode1, unicode2: i32,
// 	advance:            f32,
// }

MSDF_Bounds :: struct {
	left, bottom, right, top: f32,
}

MSDF_Glyph :: struct {
	// dont change var names
	unicode:     u32,
	advance:     f32,
	planeBounds: MSDF_Bounds,
	atlasBounds: MSDF_Bounds,
}

MSDF_File :: struct {
	// dont change var names
	atlas:   MSDF_Atlas,
	metrics: MSDF_Metrics,
	glyphs:  []MSDF_Glyph,
	// kerning: []MSDF_KerningPair,
}

// TODO: msdf_load_ex ??
msdf_load_from_file :: proc(
	json_path: string,
	img_path: string,
	allocator := context.allocator,
) -> (
	Font,
	bool,
) {
	inner :: proc(
		json_path: string,
		img_path: string,
		temp_alloc: runtime.Allocator,
		final_alloc: runtime.Allocator,
	) -> (
		font: Font,
		good: bool,
	) {
		json_bytes, json_err := os.read_entire_file(json_path, allocator = temp_alloc)
		if json_err != os.General_Error.None {
			fmt.eprintfln("[ERROR] Failed to read font JSON: %v", json_path)
			return
		}

		msdf_data: MSDF_File
		{
			if err := json.unmarshal(json_bytes, &msdf_data, allocator = temp_alloc); err != nil {
				fmt.eprintfln("[ERROR] Failed to parse MSDF JSON: %v", err)
				return
			}
		}

		atlas_h := cast(f32)msdf_data.atlas.height
		y_flip := msdf_data.atlas.yOrigin == "top"

		font.atlas = d3d11_tex2d_alloc_from_file(img_path) or_return
		font.metrics = msdf_data.metrics

		font.glyphs = make(map[rune]Glyph, allocator = final_alloc)
		for glyph in msdf_data.glyphs {
			// ab := g.atlasBounds.bottom
			// at := g.atlasBounds.top
			// if y_flip {
			// 	// (0,0) is bottom-left in UV space
			// 	ab, at = atlas_h - g.atlasBounds.top, atlas_h - g.atlasBounds.bottom
			// }
			font.glyphs[cast(rune)glyph.unicode] = Glyph {
				advance     = glyph.advance,
				atlasBounds = glyph.atlasBounds,
				planeBounds = glyph.planeBounds,
			}
		}

		// font.kerning = make(map[[2]rune]f32, allocator = final_alloc)
		// for k in msdf_data.kerning {
		// 	font.kerning[[2]rune{cast(rune)k.unicode1, cast(rune)k.unicode2}] = k.advance
		// }

		return font, true
	}

	if allocator == context.temp_allocator {
		return inner(json_path, img_path, allocator, allocator)
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	return inner(json_path, img_path, context.temp_allocator, allocator)
}

//
// Atlas gen
//
import "core:path/filepath"
import "core:strings"

MSDF_ATLAS_GEN_EXEC_PATH :: "msdf-atlas-gen"
MSDF_ATLAS_GEN_CHARSET :: "[32, 126], [160, 255], [256, 383], [8192, 8223]" // 65533

@(require_results)
msdf_atlas_gen :: proc(
	ttf_path: string,
	allocator := context.allocator,
) -> (
	string,
	string,
	bool,
) {
	inner :: proc(
		ttf_path: string,
		temp_alloc: runtime.Allocator,
		final_alloc: runtime.Allocator,
	) -> (
		json_path: string,
		png_path: string,
		good: bool,
	) {
		if !os.exists(ttf_path) {
			fmt.printfln("[ERROR] File missing for '%s'", ttf_path)
			return
		}

		ext := filepath.ext(ttf_path)
		name_no_ext := strings.trim_suffix(ttf_path, ext)

		json_path = fmt.aprintf("%s.json", name_no_ext, allocator = final_alloc)
		png_path = fmt.aprintf("%s.png", name_no_ext, allocator = final_alloc)

		if os.exists(json_path) && os.exists(png_path) {
			return json_path, png_path, true
		}

		fmt.printfln("[INFO] Atlas missing for '%s'. Generating now...", ttf_path)

		args := []string {
			MSDF_ATLAS_GEN_EXEC_PATH,
			"-font",
			ttf_path,
			"-type",
			"msdf",
			"-format",
			"png",
			"-imageout",
			png_path,
			"-json",
			json_path,
			"-pxrange",
			"8",
			"-size",
			"32",
			"-chars",
			MSDF_ATLAS_GEN_CHARSET,
		}

		desc := os.Process_Desc {
			command = args,
		}

		process, start_err := os.process_start(desc)
		if start_err != os.General_Error.None {
			fmt.eprintfln(
				"[ERROR] Failed to start generator. Is '%s' in your PATH? Error: %v",
				MSDF_ATLAS_GEN_EXEC_PATH,
				start_err,
			)
			return
		}
		defer _ = os.process_terminate(process) // TODO: check

		state, wait_err := os.process_wait(process)
		if wait_err != os.General_Error.None || !state.success {
			fmt.eprintfln("[ERROR] %s failed or exited with an error.", MSDF_ATLAS_GEN_EXEC_PATH)
			return
		}

		fmt.printfln("[INFO] Successfully generated atlas for '%s'.", ttf_path)
		return json_path, png_path, true
	}

	if allocator == context.temp_allocator {
		return inner(ttf_path, allocator, allocator)
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	return inner(ttf_path, context.temp_allocator, allocator)
}
