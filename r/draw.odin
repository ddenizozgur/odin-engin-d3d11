#+build windows
package r

import "../wm"
import "core:fmt"
import "core:math/linalg"
import "core:mem"
import "core:sys/windows"
import D3D11 "vendor:directx/d3d11"

Per_Instanced :: struct {
	dst_rect:   [4]f32, // LT, LR, BL, BR
	src_rect:   [4]f32,
	color_rect: [4]RGBA8,
	cradii:     f32,
	kind:       enum u32 {
		Rect,
		Tex2D,
		MSDF,
	},
}

Draw_State :: struct {
	sampler_kind: Sampler_Kind,
	depth_kind:   Depth_Kind,
	tex2d_srv:    ^D3D11.IShaderResourceView,
}

Batch_Run :: struct {
	state:      Draw_State,
	first, cnt: u32,
}

INSTANCED_MAX_BYTES :: mem.Kilobyte * 512
INSTANCED_MAX :: INSTANCED_MAX_BYTES / size_of(Per_Instanced)
RUNS_MAX :: 1024

Batch :: struct {
	instanced: [dynamic; INSTANCED_MAX]Per_Instanced,
	runs:      [dynamic; RUNS_MAX]Batch_Run,
	state:     Draw_State,
}

draw_initialize :: proc() -> bool {
	{ 	// Instance buffer
		desc := D3D11.BUFFER_DESC {
			ByteWidth      = INSTANCED_MAX_BYTES,
			Usage          = .DYNAMIC,
			BindFlags      = {.VERTEX_BUFFER},
			CPUAccessFlags = {.WRITE},
		}

		hr := _d3d11_perm.device->CreateBuffer(&desc, nil, &_draw_perm.instanced_buffer_gpu)
		if windows.FAILED(hr) {
			fmt.eprintfln("[ERROR] Failed to create draw instance buffer")
			return false
		}
	}

	{ 	// Shader + uniforms
		d3d11_vshader_init(
			_draw_shader,
			"draw_shader.hlsl",
			_draw_ilayout_desc,
			&_draw_perm.vshader,
		) or_return

		d3d11_pshader_init(_draw_shader, "draw_shader.hlsl", &_draw_perm.pshader) or_return

		d3d11_uniforms_init(_Draw_Uniforms, &_draw_perm.uniforms_buffer_gpu) or_return
	}

	{ 	// Bind pipeline
		stride := cast(u32)size_of(Per_Instanced)
		offset := u32(0)
		_d3d11_perm.device_ctx->IASetVertexBuffers(
			0,
			1,
			&_draw_perm.instanced_buffer_gpu,
			&stride,
			&offset,
		)
		_d3d11_perm.device_ctx->IASetInputLayout(_draw_perm.vshader.ilayout)
		_d3d11_perm.device_ctx->IASetPrimitiveTopology(.TRIANGLESTRIP)

		_d3d11_perm.device_ctx->VSSetShader(_draw_perm.vshader.vshader, nil, 0)
		_d3d11_perm.device_ctx->VSSetConstantBuffers(0, 1, &_draw_perm.uniforms_buffer_gpu)

		_d3d11_perm.device_ctx->PSSetShader(_draw_perm.pshader, nil, 0)
		_d3d11_perm.device_ctx->PSSetConstantBuffers(0, 1, &_draw_perm.uniforms_buffer_gpu)

		_d3d11_perm.device_ctx->RSSetState(_d3d11_perm.rasterizer)
		_d3d11_perm.device_ctx->OMSetBlendState(_d3d11_perm.blend_state, nil, 0xffffffff)
	}

	return true
}

draw_begin_frame :: proc(window: ^wm.Window, swapchain: ^Swapchain) {
	size, resized := wm.get_client_size_2f32(window)

	if resized {
		d3d11_resize_default_rtv(swapchain, size)
	} else {
		d3d11_set_default_rtv(swapchain) // Flip model unbind rtv after present()
		_draw_set_viewport(size)
	}

	_draw_upload_uniforms(size) // check
	// clear(&_draw_perm.batch.instanced)
	// clear(&_draw_perm.batch.runs)
	// _draw_perm.batch.state = {}
}
draw_end_frame :: proc() {
	_draw_flush_batch()
}
@(deferred_out = draw_end_frame)
DRAW_FRAME_SCOPED :: #force_inline proc(window: ^wm.Window, swapchain: ^Swapchain) {
	draw_begin_frame(window, swapchain)
}

draw_set_sampler :: proc(kind: Sampler_Kind) {
	_draw_perm.batch.state.sampler_kind = kind
}
draw_set_depth :: proc(kind: Depth_Kind) {
	_draw_perm.batch.state.depth_kind = kind
}

draw_rect :: proc(
	pos, size: [2]f32,
	color_rect: [4]RGBA8, // LT, LR, BL, BR
	cradii := f32(0),
) {
	tl := pos
	br := pos + size

	_draw_instanced(
		Per_Instanced {
			dst_rect = {tl.x, tl.y, br.x, br.y},
			color_rect = color_rect,
			cradii = cradii,
			kind = .Rect,
		},
	)
}

draw_circle :: proc(
	center: [2]f32,
	radius: f32,
	color_rect: [4]RGBA8, // LT, LR, BL, BR
) {
	real_pos := pos_from_align_kind(center, radius * 2, .Center)
	draw_rect(real_pos, radius * 2, color_rect, radius)
}

draw_tex2d_ex :: proc(
	tex2d: D3D11_Tex2D,
	src_pos, src_size: [2]f32,
	dst_pos, dst_size: [2]f32,
	tint_rect := cast([4]RGBA8)WHITE, // LT, LR, BL, BR
	cradii := f32(0),
) {
	_draw_set_tex2d(tex2d.srv)

	dst_tl := dst_pos
	dst_br := dst_pos + dst_size

	tw := cast(f32)tex2d.size.x
	th := cast(f32)tex2d.size.y

	src_rect := [4]f32 {
		src_pos.x / tw,
		src_pos.y / th,
		(src_pos.x + src_size.x) / tw,
		(src_pos.y + src_size.y) / th,
	}

	_draw_instanced(
		Per_Instanced {
			src_rect = src_rect,
			dst_rect = {dst_tl.x, dst_tl.y, dst_br.x, dst_br.y},
			color_rect = tint_rect,
			cradii = cradii,
			kind = .Tex2D,
		},
	)
}

draw_tex2d :: proc(
	tex2d: D3D11_Tex2D,
	pos, size: [2]f32,
	tint_rect := cast([4]RGBA8)WHITE, // LT, LR, BL, BR
	cradii := f32(0),
) {
	draw_tex2d_ex(tex2d, 0, cast([2]f32)tex2d.size, pos, size, tint_rect, cradii)
}

draw_text :: proc(font: Font, text: string, pos: [2]f32, font_size: f32, color_rect: [4]RGBA8) {
	if text == "" {
		return
	}

	_draw_set_tex2d(font.atlas.srv)

	font_scale := font_size / font.metrics.emSize
	line_h := font.metrics.lineHeight * font_scale

	cursor_x := pos.x
	cursor_y := pos.y + (font.metrics.ascender * font_scale)

	atlas_w := cast(f32)font.atlas.size.x
	atlas_h := cast(f32)font.atlas.size.y

	for char in text {
		if char == '\n' { 	// TODO: handle other ctrl chars
			cursor_x = pos.x
			cursor_y += line_h
			continue
		}

		glyph := font.glyphs[char] or_else font.glyphs['?']

		// if glyph.atlasBounds.left == glyph.atlasBounds.right {
		// cursor_x += glyph.advance * font_scale
		// continue
		// }

		gx := cursor_x
		gy := cursor_y

		dst_rect := [4]f32 {
			gx + (glyph.planeBounds.left * font_scale),
			gy - (glyph.planeBounds.top * font_scale),
			gx + (glyph.planeBounds.right * font_scale),
			gy - (glyph.planeBounds.bottom * font_scale),
		}

		src_rect := [4]f32 {
			glyph.atlasBounds.left / atlas_w,
			1 - (glyph.atlasBounds.top / atlas_h),
			glyph.atlasBounds.right / atlas_w,
			1 - (glyph.atlasBounds.bottom / atlas_h),
		}

		_draw_instanced(
			Per_Instanced {
				dst_rect = dst_rect,
				src_rect = src_rect,
				color_rect = color_rect,
				kind = .MSDF,
			},
		)

		cursor_x += glyph.advance * font_scale
	}
}

text_bbox :: proc(font: Font, text: string, font_size: f32) -> [2]f32 {
	if text == "" {
		return {0, 0}
	}

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

		glyph := font.glyphs[char] or_else font.glyphs['?']

		// if glyph.atlasBounds.left == glyph.atlasBounds.right {
		// cursor_x += glyph.advance * font_scale
		// continue
		// }

		cursor_x += glyph.advance * font_scale
	}

	return {max(max_x, cursor_x), total_height}
}

//
// Privates
//
@(private = "file")
_draw_set_tex2d :: proc(srv: ^D3D11.IShaderResourceView) {
	_draw_perm.batch.state.tex2d_srv = srv
}

@(private = "file")
_draw_instanced :: proc(inst: Per_Instanced) {
	batch := &_draw_perm.batch
	if len(batch.instanced) + 1 > cap(batch.instanced) {
		if !_draw_flush_batch() {
			return
		}
	}

	needs_new_run := len(batch.runs) == 0
	if !needs_new_run {
		last_state := batch.runs[len(batch.runs) - 1].state
		needs_new_run = last_state != batch.state
	}
	if needs_new_run && len(batch.runs) + 1 > cap(batch.runs) {
		if !_draw_flush_batch() {
			return
		}
	}
	if needs_new_run {
		start_index := cast(u32)len(batch.instanced)
		append(&batch.runs, Batch_Run{state = batch.state, first = start_index, cnt = 0})
	}

	append(&batch.instanced, inst)
	batch.runs[len(batch.runs) - 1].cnt += 1
}

@(private = "file")
_draw_flush_batch :: proc() -> bool {
	if len(_draw_perm.batch.instanced) == 0 {
		return true
	}

	{ 	// Map instances
		sub_rsrc: D3D11.MAPPED_SUBRESOURCE
		hr := _d3d11_perm.device_ctx->Map(
			_draw_perm.instanced_buffer_gpu,
			0,
			.WRITE_DISCARD,
			{},
			&sub_rsrc,
		)
		if windows.FAILED(hr) {
			fmt.eprintfln("[ERROR] Failed to map instanced buffer")
			return false
		}

		mem.copy(
			sub_rsrc.pData,
			raw_data(_draw_perm.batch.instanced[:]),
			len(_draw_perm.batch.instanced) * size_of(Per_Instanced),
		)
		_d3d11_perm.device_ctx->Unmap(_draw_perm.instanced_buffer_gpu, 0)
	}

	for &run in _draw_perm.batch.runs {
		_d3d11_perm.device_ctx->PSSetShaderResources(0, 1, &run.state.tex2d_srv)
		_d3d11_perm.device_ctx->PSSetSamplers(0, 1, &_d3d11_perm.samplers[run.state.sampler_kind])
		_d3d11_perm.device_ctx->OMSetDepthStencilState(_d3d11_perm.depths[run.state.depth_kind], 0)
		_d3d11_perm.device_ctx->DrawInstanced(4, run.cnt, 0, run.first)
	}

	clear(&_draw_perm.batch.instanced)
	clear(&_draw_perm.batch.runs)

	return true
}

@(private = "file")
_draw_set_viewport :: proc(size: [2]f32) {
	viewport := D3D11.VIEWPORT {
		TopLeftX = 0,
		TopLeftY = 0,
		Width    = size.x,
		Height   = size.y,
		MinDepth = 0,
		MaxDepth = 1,
	}
	_d3d11_perm.device_ctx->RSSetViewports(1, &viewport)
}

@(private = "file")
_draw_upload_uniforms :: proc(size: [2]f32) {
	_draw_uniforms.proj_matrix = linalg.matrix_ortho3d_f32(0, size.x, size.y, 0, 0, 1, true)

	sub_rsrc: D3D11.MAPPED_SUBRESOURCE
	hr := _d3d11_perm.device_ctx->Map(
		_draw_perm.uniforms_buffer_gpu,
		0,
		.WRITE_DISCARD,
		{},
		&sub_rsrc,
	)
	if windows.SUCCEEDED(hr) {
		mem.copy(sub_rsrc.pData, &_draw_uniforms, size_of(_draw_uniforms))
		_d3d11_perm.device_ctx->Unmap(_draw_perm.uniforms_buffer_gpu, 0)
	}
}

@(private = "file")
_draw_perm: struct {
	instanced_buffer_gpu: ^D3D11.IBuffer,
	uniforms_buffer_gpu:  ^D3D11.IBuffer,
	vshader:              D3D11_VShader,
	pshader:              ^D3D11.IPixelShader,
	batch:                Batch,
}

@(private = "file")
_Draw_Uniforms :: struct #align (16) {
	proj_matrix: matrix[4, 4]f32,
}
@(private = "file")
_draw_uniforms: _Draw_Uniforms

@(private = "file")
_draw_ilayout_desc := []D3D11.INPUT_ELEMENT_DESC {
	{"POS", 0, .R32G32B32A32_FLOAT, 0, 0, .INSTANCE_DATA, 1},
	{"TEX", 0, .R32G32B32A32_FLOAT, 0, D3D11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"COL", 0, .R8G8B8A8_UNORM, 0, D3D11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"COL", 1, .R8G8B8A8_UNORM, 0, D3D11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"COL", 2, .R8G8B8A8_UNORM, 0, D3D11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"COL", 3, .R8G8B8A8_UNORM, 0, D3D11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"CRADII", 0, .R32_FLOAT, 0, D3D11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"KIND", 0, .R32_UINT, 0, D3D11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
}

@(private = "file")
_draw_shader := `
cbuffer Globals : register(b0) {
  float4x4 proj_matrix;
}

Texture2D tex2d : register(t0);
SamplerState sampler_ : register(s0);

struct vs_in {
  float4 dst_rect : POS;
  float4 src_rect : TEX;
  float4 color_rect[4] : COL;
  float cradii : CRADII;
  uint kind : KIND;
  uint vertex_id : SV_VertexID;
};

struct vs_out {
	float4 sv_pos : SV_POSITION;
	float4 color : COL;
	float2 tex2d_uv : TEXCOORD0;
	float2 sdf_pos : TEXCOORD1;
	float2 half_size : TEXCOORD2;
	float cradii : CRADII;
	nointerpolation uint kind : KIND;
};

vs_out vs_main(vs_in input) {
	static const float2 corners[] = {
		{-1, -1},	// TL
		{+1, -1},	// TR
		{-1, +1},	// BL
		{+1, +1},	// BR
	};

	float2 local_pos = corners[input.vertex_id];
	float4 local_color = input.color_rect[input.vertex_id];
	float2 local_uv = local_pos * 0.5 + 0.5;

	float2 half_size = (input.dst_rect.zw - input.dst_rect.xy) * 0.5;
  float2 center = input.dst_rect.xy + half_size;

  float2 sdf_pos = local_pos * half_size;
  float2 pixel_pos = local_pos * half_size + center;
  float2 tex2d_uv = lerp(input.src_rect.xy, input.src_rect.zw, local_uv);

	vs_out output;
	{
		output.sv_pos = mul(proj_matrix, float4(pixel_pos, 0.f, 1.f));
		output.color = local_color;
		output.tex2d_uv = tex2d_uv;
		output.sdf_pos = sdf_pos;
		output.half_size = half_size;
		output.cradii = input.cradii;
		output.kind = input.kind;
	}
	return output;
}

#define TEXT_THICKNESS  0.6
#define MSDF_PXRANGE    8.0

#define KIND_RECT   0
#define KIND_TEX2D  1
#define KIND_MSDF   2

float rect_sdf(float2 pos, float2 half_size, float r) {
	float2 q = abs(pos) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float msdf_median(float r, float g, float b) {
  return max(min(r, g), min(max(r, g), b));
}

float some_noise(float2 n) {
  float f = 0.06711056 * n.x + 0.00583715 * n.y;
  return frac(52.9829189 * frac(f));
}

float4 ps_main(vs_out input) : SV_TARGET {
	float alpha = 1.f;
	float4 tex_color = float4(1,1,1,1);

	if (input.kind == KIND_TEX2D || input.kind == KIND_MSDF) {
		tex_color = tex2d.Sample(sampler_, input.tex2d_uv);
	}

	switch (input.kind) {
	case KIND_TEX2D:
	case KIND_RECT:
		if (input.cradii > 0) {
			float safe_radius = min(input.cradii, min(input.half_size.x, input.half_size.y));
			float dist = rect_sdf(input.sdf_pos, input.half_size, safe_radius);
			float aa = fwidth(dist);
			// float aa = length(float2(ddx(dist), ddy(dist)));
			float feather = aa * 0.5;
  		alpha = 1 - smoothstep(-feather, feather, dist);
  	}
		break;
	case KIND_MSDF: {
		float sd = msdf_median(tex_color.r, tex_color.g, tex_color.b) - 0.5;

		uint tex_w, tex_h;
    tex2d.GetDimensions(tex_w, tex_h);
    float2 msdf_tex_size = float2((float)tex_w, (float)tex_h);

    float2 unit_range = float2(MSDF_PXRANGE, MSDF_PXRANGE) / msdf_tex_size;
    float2 screen_tex_size = float2(1.0, 1.0) / fwidth(input.tex2d_uv);

    float screen_px_range = max(0.5 * dot(unit_range, screen_tex_size), 1.0);
    float screen_px_dist = screen_px_range * sd;

    float opacity = clamp(screen_px_dist + TEXT_THICKNESS, 0.0, 1.0);
    tex_color = float4(1.0, 1.0, 1.0, opacity);
	} break;
	}

  float4 out_color = input.color * tex_color;
  out_color.a *= alpha;

  // TODO: check for video compression algos
  float noise = some_noise(input.sv_pos.xy);
  noise = (noise - 0.5) / 255.0;
  out_color.rgb += noise;

	return out_color;
}`
