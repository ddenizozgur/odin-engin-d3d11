#+build windows
package r

import "core:mem"

Batch_Per_Data :: struct {
	dst:      [4]f32,
	src:      [4]f32,
	color_tl: RGBA8,
	color_tr: RGBA8,
	color_bl: RGBA8,
	color_br: RGBA8,
	cradii:   f32,
	kind:     enum u32 {
		Rect,
		Tex2D,
		MSDF,
	},
}

imm_begin_frame :: proc() {
	imm_d3d11_resize_default_rtv()
	d3d11_set_default_rtv() // Flip model unbind rtv after present()
}
imm_end_frame :: proc() {
	if len(_batch_list) > 0 {
		_imm_d3d11_flush()
	}
}
@(deferred_out = imm_end_frame)
IMM_FRAME_SCOPED :: #force_inline proc() {
	imm_begin_frame()
}

imm_push_rect_grad :: proc(
	pos, size: [2]f32,
	color_tl, color_tr, color_bl, color_br: RGBA8,
	cradii := f32(0),
) {
	if len(_batch_list) + 1 > cap(_batch_list) {
		_imm_d3d11_flush()
	}

	tl := pos
	br := pos + size

	append(
		&_batch_list,
		Batch_Per_Data {
			dst = {tl.x, tl.y, br.x, br.y},
			color_tl = color_tl,
			color_tr = color_tr,
			color_bl = color_bl,
			color_br = color_br,
			cradii = cradii,
			kind = .Rect,
		},
	)
}
imm_push_rect :: #force_inline proc(pos, size: [2]f32, color: RGBA8, cradii := f32(0)) {
	imm_push_rect_grad(pos, size, color, color, color, color, cradii)
}

imm_push_circle_grad :: proc(
	center: [2]f32,
	radius: f32,
	color_tl, color_tr, color_bl, color_br: RGBA8,
) {
	real_pos := pos_from_align_kind(center, radius * 2, .Center)
	imm_push_rect_grad(real_pos, radius * 2, color_tl, color_tr, color_bl, color_br, radius)
}
imm_push_circle :: proc(center: [2]f32, radius: f32, color: RGBA8) {
	imm_push_circle_grad(center, radius, color, color, color, color)
}

imm_push_tex2d_ex_grad :: proc(
	tex2d: D3D11_Tex2D,
	src_pos, src_size: [2]f32,
	dst_pos, dst_size: [2]f32,
	tint_tl, tint_tr, tint_bl, tint_br: RGBA8,
	cradii := f32(0),
) {
	if len(_batch_list) + 1 > cap(_batch_list) {
		_imm_d3d11_flush()
	}

	imm_d3d11_bind_tex2d(tex2d.srv)

	dst_tl := dst_pos
	dst_br := dst_pos + dst_size

	tw := cast(f32)tex2d.size.x
	th := cast(f32)tex2d.size.y

	src := [4]f32 {
		src_pos.x / tw,
		src_pos.y / th,
		(src_pos.x + src_size.x) / tw,
		(src_pos.y + src_size.y) / th,
	}

	append(
		&_batch_list,
		Batch_Per_Data {
			src = src,
			dst = {dst_tl.x, dst_tl.y, dst_br.x, dst_br.y},
			color_tl = tint_tl,
			color_tr = tint_tr,
			color_bl = tint_bl,
			color_br = tint_br,
			cradii = cradii,
			kind = .Tex2D,
		},
	)
}
imm_push_tex2d_ex :: proc(
	tex2d: D3D11_Tex2D,
	src_pos, src_size: [2]f32,
	dst_pos, dst_size: [2]f32,
	tint := WHITE,
	cradii := f32(0),
) {
	imm_push_tex2d_ex_grad(
		tex2d,
		src_pos,
		src_size,
		dst_pos,
		dst_size,
		tint,
		tint,
		tint,
		tint,
		cradii,
	)
}
imm_push_tex2d :: proc(tex2d: D3D11_Tex2D, pos, size: [2]f32, tint := WHITE, cradii := f32(0)) {
	imm_push_tex2d_ex(tex2d, {0, 0}, cast([2]f32)tex2d.size, pos, size, tint, cradii)
}

imm_push_text_grad :: proc(
	font: Font,
	text: string,
	pos: [2]f32,
	font_size: f32,
	color_tl, color_tr, color_bl, color_br: RGBA8,
) {
	if text == "" do return

	imm_d3d11_bind_tex2d(font.atlas.srv)

	font_scale := font_size / font.metrics.emSize
	line_h := font.metrics.lineHeight * font_scale

	cursor_x := pos.x
	cursor_y := pos.y + (font.metrics.ascender * font_scale)

	atlas_w := cast(f32)font.atlas.size.x
	atlas_h := cast(f32)font.atlas.size.y

	for char in text {
		if len(_batch_list) + 1 > cap(_batch_list) {
			_imm_d3d11_flush()
		}

		if char == '\n' { 	// TODO: handle other ctrl chars
			cursor_x = pos.x
			cursor_y += line_h
			continue
		}

		glyph, ok := font.glyphs[char]
		if !ok do glyph = font.glyphs['?']

		// if glyph.atlasBounds.left == glyph.atlasBounds.right {
		// cursor_x += glyph.advance * font_scale
		// continue
		// }

		gx := cursor_x
		gy := cursor_y

		dst := [4]f32 {
			gx + (glyph.planeBounds.left * font_scale),
			gy - (glyph.planeBounds.top * font_scale),
			gx + (glyph.planeBounds.right * font_scale),
			gy - (glyph.planeBounds.bottom * font_scale),
		}

		src := [4]f32 {
			glyph.atlasBounds.left / atlas_w,
			1.0 - (glyph.atlasBounds.top / atlas_h),
			glyph.atlasBounds.right / atlas_w,
			1.0 - (glyph.atlasBounds.bottom / atlas_h),
		}

		append(
			&_batch_list,
			Batch_Per_Data {
				dst = dst,
				src = src,
				color_tl = color_tl,
				color_tr = color_tr,
				color_bl = color_bl,
				color_br = color_br,
				kind = .MSDF,
			},
		)

		cursor_x += glyph.advance * font_scale
	}
}
imm_push_text :: proc(font: Font, text: string, pos: [2]f32, font_size: f32, color: RGBA8) {
	imm_push_text_grad(font, text, pos, font_size, color, color, color, color)
}
text_bbox :: proc(font: Font, text: string, font_size: f32) -> [2]f32 {
	if text == "" do return {0, 0}

	cursor_x := f32(0)
	max_x := f32(0)

	font_scale := font_size / font.metrics.emSize
	line_height := font.metrics.lineHeight * font_scale

	total_height := line_height

	for char in text {
		if char == '\n' {
			max_x = max(max_x, cursor_x)
			cursor_x = 0
			total_height += line_height
			continue
		}

		glyph, ok := font.glyphs[char]
		if !ok do glyph = font.glyphs['?']

		cursor_x += glyph.advance * font_scale
	}

	return {max(max_x, cursor_x), total_height}
}

//
// Privates
//
@(private)
_batch_list: [dynamic; _BATCH_LIST_LEN]Batch_Per_Data
@(private)
_BATCH_LIST_BYTES :: mem.Kilobyte * 512
@(private)
_BATCH_LIST_LEN :: _BATCH_LIST_BYTES / size_of(Batch_Per_Data)
