package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:time"

import "r"
import "wm"

varela: r.Font
swapchain: r.Swapchain

to_initialize :: proc(window: ^wm.Window) -> bool {
	r.d3d11_initialize() or_return
	swapchain = r.d3d11_create_swapchain(window) or_return
	r.draw_initialize() or_return

	{
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

		json_path, png_path := r.msdf_atlas_gen(
			"rsrc/font/VarelaRound-Regular.ttf",
			allocator = context.temp_allocator,
		) or_return

		varela = r.msdf_load_from_file(json_path, png_path) or_return
	}

	return true
}

to_render :: proc(window: ^wm.Window, dt: f32) {
	@(static) et: f32
	defer et += dt

	size, _ := wm.get_client_size_2f32(window)
	mouse_pos := wm.get_mouse_pos_2f32(window)

	{
		r.DRAW_FRAME_SCOPED(window, &swapchain)
		r.d3d11_clear_default_rtv(swapchain, r.NAYSAYER_BG)

		some_bg(size, et)

		// liq_neon(window, et)

		// draw_some_text(varela, 0, 1)

		r.draw_rect(mouse_pos, 50, r.RGBA8{0xff, 0xff, 0xff, 0xaa})

		draw_fps(varela, {size.x, 0}, 20, dt, .TopRight)
	}

	r.d3d11_present(swapchain)
}

main :: proc() {
	wm.set_console_utf8()
	_ = wm.initialize()

	window, _ := wm.window_alloc("Kralsin", {1280, 800}, .Windowed)
	_ = to_initialize(window)

	prev_time := time.now()
	frame_loop: for {
		r.d3d11_swapchain_wait(swapchain, window)

		this_time := time.now()
		duration := time.diff(prev_time, this_time)
		dt := cast(f32)time.duration_seconds(duration)
		prev_time = this_time

		for evnt in wm.poll_events_this_frame() {
			#partial switch data in evnt {
			case wm.Event_WindowClose:
				break frame_loop
			}
		}

		/*
		if wm.window_is_minimized(window) {
			// time.sleep(10 * time.Millisecond)
			windows.WaitMessage() // !! PeekMessage !!
			return
		}
		*/

		to_render(window, dt)
	}
}

@(export) //link_name="NvOptimusEnablement"
NvOptimusEnablement: u32 = 1
@(export) //link_name="AmdPowerXpressRequestHighPerformance"
AmdPowerXpressRequestHighPerformance: i32 = 1

draw_fps :: proc(
	font: r.Font,
	pos: [2]f32,
	font_size: f32,
	dt: f32,
	align_kind := r.Align_Kind.TopLeft,
) {
	@(static) et: f32
	@(static) fps: u32

	@(static) fps_buf: [32]u8
	@(static) fps_str: string

	defer {
		et += dt
		fps += 1
	}

	if et >= 1 {
		fps_str = fmt.bprintf(fps_buf[:], "FPS: %v", fps)

		et -= 1
		fps = 0
	}

	bounds := r.text_bbox(font, fps_str, font_size)
	real_pos := r.pos_from_align_kind(pos, bounds, align_kind)
	r.draw_text(font, fps_str, real_pos, font_size, r.YELLOW)
}

some_bg :: proc(client_size: [2]f32, et: f32) {
	s1 := math.sin_f32(et * 0.15)
	s2 := math.cos_f32(et * 0.22)
	s3 := math.sin_f32(et * 0.18 + 1.0)
	s4 := math.cos_f32(et * 0.12 + 2.0)

	tl := r.vec4f32_to_rgba8({0.10 + 0.05 * s1, 0.02, 0.25 + 0.1 * s2, 1.0})
	tr := r.vec4f32_to_rgba8({0.30 + 0.10 * s3, 0.05, 0.15, 1.0})
	bl := r.vec4f32_to_rgba8({0.02, 0.15 + 0.05 * s4, 0.35 + 0.1 * s1, 1.0})
	br := r.vec4f32_to_rgba8({0.15, 0.05, 0.25 + 0.05 * s2, 1.0})

	r.draw_rect({0, 0}, client_size, {tl, tr, bl, br})
}

draw_some_text :: proc(font: r.Font, pos: [2]f32, scale: f32) {
	y := pos.y

	for i in 0 ..= 32 {
		font_size := (cast(f32)i + 4) * scale
		font_scale := font_size / font.metrics.emSize
		line_h := font.metrics.lineHeight * font_scale
		defer y += line_h

		{
			// runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

			r.draw_text(
				font,
				"The quick brown fox jumps over the lazy dog",
				// fmt.tprintf("The quick brown fox jumps over the lazy dog, %v", font_size),
				{pos.x, y},
				font_size,
				r.WHITE,
			)
		}
	}
}

liq_neon :: proc(window: ^wm.Window, et: f32) {
	color_at :: proc(nx, ny, t: f32) -> [4]f32 {
		v1 := math.sin(nx * 10.0 + t * 1.5)
		v2 := math.sin(ny * 8.0 - t * 1.2)
		v3 := math.sin((nx + ny) * 12.0 + t)

		dx := nx - 0.5
		dy := ny - 0.5
		dist := math.sqrt(dx * dx + dy * dy)
		v4 := math.cos(dist * 20.0 - t * 3.0)

		sum := (v1 + v2 + v3 + v4) * 0.25

		r := 0.6 + 0.4 * math.sin(sum * math.PI + 0.0)
		g := 0.3 + 0.3 * math.sin(sum * math.PI + 2.0)
		b := 0.8 + 0.2 * math.sin(sum * math.PI + 4.0)

		return {r, g, b, 1.0}
	}

	client_size, _ := wm.get_client_size_2f32(window)

	cols := 40
	rows := 25
	cell_w := client_size.x / cast(f32)cols
	cell_h := client_size.y / cast(f32)rows

	for y in 0 ..< rows {
		for x in 0 ..< cols {
			xf := cast(f32)x
			yf := cast(f32)y

			nx0 := xf / cast(f32)cols
			ny0 := yf / cast(f32)rows
			nx1 := (xf + 1.0) / cast(f32)cols
			ny1 := (yf + 1.0) / cast(f32)rows

			c0 := color_at(nx0, ny0, et)
			c1 := color_at(nx1, ny0, et)
			c2 := color_at(nx0, ny1, et)
			c3 := color_at(nx1, ny1, et)

			base_pos := [2]f32{xf * cell_w, yf * cell_h}

			pulse := math.sin(et * 3.0 + c0.r * 5.0)
			scale := 0.60 + (0.40 * pulse)

			size := [2]f32{cell_w * scale, cell_h * scale}

			offset := [2]f32{cell_w * (1.0 - scale) * 0.5, cell_h * (1.0 - scale) * 0.5}

			cradii := (cell_w * 0.5) * scale

			r.draw_rect(
				base_pos + offset,
				size,
				{
					r.vec4f32_to_rgba8(c0),
					r.vec4f32_to_rgba8(c1),
					r.vec4f32_to_rgba8(c2),
					r.vec4f32_to_rgba8(c3),
				},
				cradii,
			)
		}
	}
}
