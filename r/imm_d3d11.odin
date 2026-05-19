#+build windows
package r

import "../wm"
import "core:fmt"
import "core:math/linalg"
import "core:mem"
import "core:sys/windows"
import "vendor:directx/d3d11"

imm_d3d11_resize_default_rtv :: proc() {
	@(static) size_last_frame: [2]f32
	size_this_frame := cast([2]f32)wm.get_client_size()
	if size_this_frame == size_last_frame {
		return
	}
	size_last_frame = size_this_frame

	d3d11_resize_default_rtv(size_this_frame)

	{ 	// Map uniforms
		_imm_d3d11_persist.uniforms.proj_matrix = linalg.matrix_ortho3d_f32(
			0,
			size_this_frame.x,
			size_this_frame.y,
			0,
			0,
			1,
			true,
		)

		sub_rsrc: d3d11.MAPPED_SUBRESOURCE
		hres := _d3d11_persist.device_ctx->Map(
			_imm_d3d11_persist.uniforms_gpu,
			0,
			.WRITE_DISCARD,
			{},
			&sub_rsrc,
		)
		if windows.SUCCEEDED(hres) {
			mem.copy(sub_rsrc.pData, &_imm_d3d11_persist.uniforms, size_of(_Imm_D3D11_Uniforms))
			_d3d11_persist.device_ctx->Unmap(_imm_d3d11_persist.uniforms_gpu, 0)
		}
	}
}

imm_d3d11_bind_sampler :: proc(kind := Sampler_Kind.PointClamp) {
	if kind != _imm_d3d11_last.sampler_kind {
		if len(_batch_list) > 0 {
			_imm_d3d11_flush()
		}
		_imm_d3d11_last.sampler_kind = kind
	}
	_d3d11_persist.device_ctx->PSSetSamplers(0, 1, &_d3d11_persist.samplers[kind])
}

imm_d3d11_bind_depth :: proc(kind := Depth_Kind.Noop) {
	if kind != _imm_d3d11_last.depth_kind {
		if len(_batch_list) > 0 {
			_imm_d3d11_flush()
		}
		_imm_d3d11_last.depth_kind = kind
	}
	_d3d11_persist.device_ctx->OMSetDepthStencilState(_d3d11_persist.depths[kind], 0)
}

imm_d3d11_bind_tex2d :: proc(srv: ^d3d11.IShaderResourceView) {
	if srv != _imm_d3d11_last.srv {
		if len(_batch_list) > 0 {
			_imm_d3d11_flush()
		}
		_imm_d3d11_last.srv = srv
	}
	// Bind to slot t0
	_d3d11_persist.device_ctx->PSSetShaderResources(0, 1, &_imm_d3d11_last.srv)
}

imm_d3d11_load :: proc() -> bool {
	{ 	// Batch Buffer
		desc := d3d11.BUFFER_DESC {
			ByteWidth      = _BATCH_LIST_BYTES,
			Usage          = .DYNAMIC,
			BindFlags      = {.VERTEX_BUFFER},
			CPUAccessFlags = {.WRITE},
		}

		hres := _d3d11_persist.device->CreateBuffer(&desc, nil, &_imm_d3d11_persist.batch_list_gpu)
		if windows.FAILED(hres) {
			fmt.eprintfln("[ERROR] Failed to create IBuffer")
			return false
		}
	}

	{ 	// Init
		d3d11_vshader_init(
			_imm_d3d11_shader,
			"imm_d3d11_shader.hlsl",
			_batch_list_ilayout_desc,
			&_imm_d3d11_persist.vshader,
		) or_return

		d3d11_pshader_init(
			_imm_d3d11_shader,
			"imm_d3d11_shader.hlsl",
			&_imm_d3d11_persist.pshader,
		) or_return

		d3d11_uniforms_init(_Imm_D3D11_Uniforms, &_imm_d3d11_persist.uniforms_gpu) or_return
	}

	{ 	// Bind
		_d3d11_persist.device_ctx->VSSetConstantBuffers(0, 1, &_imm_d3d11_persist.uniforms_gpu)
		_d3d11_persist.device_ctx->IASetInputLayout(_imm_d3d11_persist.vshader.ilayout)
		_d3d11_persist.device_ctx->IASetPrimitiveTopology(.TRIANGLESTRIP)
		_d3d11_persist.device_ctx->VSSetShader(_imm_d3d11_persist.vshader.vshader, nil, 0)
		_d3d11_persist.device_ctx->PSSetShader(_imm_d3d11_persist.pshader, nil, 0)
	}

	return true
}

//
// Privates
//
@(private = "file")
_imm_d3d11_last: struct {
	// vshader:      D3D11_VShader,
	// pshader:      ^d3d11.IPixelShader,
	sampler_kind: Sampler_Kind,
	depth_kind:   Depth_Kind,
	srv:          ^d3d11.IShaderResourceView,
}

@(private = "file")
_imm_d3d11_persist: struct {
	batch_list_gpu: ^d3d11.IBuffer,
	uniforms_gpu:   ^d3d11.IBuffer,
	vshader:        D3D11_VShader,
	pshader:        ^d3d11.IPixelShader,
	uniforms:       _Imm_D3D11_Uniforms,
}

@(private)
_imm_d3d11_flush :: proc() {
	defer clear(&_batch_list)

	{ 	// Mapping Vertices
		sub_rsrc: d3d11.MAPPED_SUBRESOURCE
		hres := _d3d11_persist.device_ctx->Map(
			_imm_d3d11_persist.batch_list_gpu,
			0,
			.WRITE_DISCARD,
			{},
			&sub_rsrc,
		)
		if windows.SUCCEEDED(hres) {
			mem.copy(
				sub_rsrc.pData,
				raw_data(_batch_list[:]),
				len(_batch_list) * size_of(Batch_Per_Data),
			)
			_d3d11_persist.device_ctx->Unmap(_imm_d3d11_persist.batch_list_gpu, 0)
		}
	}

	{ 	// Draw
		stride := cast(u32)size_of(Batch_Per_Data)
		offset := u32(0)
		_d3d11_persist.device_ctx->IASetVertexBuffers(
			0,
			1,
			&_imm_d3d11_persist.batch_list_gpu,
			&stride,
			&offset,
		)
		_d3d11_persist.device_ctx->DrawInstanced(4, cast(u32)len(_batch_list), 0, 0)
	}
}

@(private = "file") // Align with GPU register
_Imm_D3D11_Uniforms :: struct #align (16) {
	proj_matrix: matrix[4, 4]f32,
}

@(private = "file")
_batch_list_ilayout_desc := []d3d11.INPUT_ELEMENT_DESC {
	{"POS", 0, .R32G32B32A32_FLOAT, 0, 0, .INSTANCE_DATA, 1},
	{"TEX", 0, .R32G32B32A32_FLOAT, 0, d3d11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"COL", 0, .R8G8B8A8_UNORM, 0, d3d11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"COL", 1, .R8G8B8A8_UNORM, 0, d3d11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"COL", 2, .R8G8B8A8_UNORM, 0, d3d11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"COL", 3, .R8G8B8A8_UNORM, 0, d3d11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"CRAD", 0, .R32_FLOAT, 0, d3d11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
	{"KIND", 0, .R32_UINT, 0, d3d11.APPEND_ALIGNED_ELEMENT, .INSTANCE_DATA, 1},
}

@(private = "file")
_imm_d3d11_shader := `
cbuffer Globals : register(b0) {
  float4x4 proj_matrix;
}

Texture2D tex2d : register(t0);
SamplerState sampler_ : register(s0);

struct vs_in {
  float4 dst : POS;
  float4 src : TEX;
  float4 color_tl : COL0;
  float4 color_tr : COL1;
  float4 color_bl : COL2;
  float4 color_br : COL3;
  float cradii : CRAD;
  uint kind : KIND;
  uint vertex_id : SV_VertexID;
};

struct vs_out {
	float4 sv_pos : SV_POSITION;
	float4 color : COL;
	float2 tex2d_uv : TEXCOORD0;
	float2 sdf_pos : TEXCOORD1;
	float2 half_size : TEXCOORD2;
	float cradii : CRAD;
	nointerpolation uint kind : KIND;
};

vs_out vs_main(vs_in input) {
	float2 local_vert;
	float4 local_color;
	float2 local_uv;

	switch (input.vertex_id) {
	case 0:	// TL
		local_vert  = input.dst.xy;
		local_color = input.color_tl;
		local_uv = input.src.xy;
		break;
	case 1:	// TR
		local_vert  = input.dst.zy;
		local_color = input.color_tr;
		local_uv = input.src.zy;
		break;
	case 2:	// BL
		local_vert  = input.dst.xw;
		local_color = input.color_bl;
		local_uv = input.src.xw;
		break;
	case 3:	// BR
		local_vert  = input.dst.zw;
		local_color = input.color_br;
		local_uv = input.src.zw;
		break;
	}

	float2 half_size = (input.dst.zw - input.dst.xy) * 0.5;
  float2 center = input.dst.xy + half_size;
  float2 sdf_pos = local_vert - center;

	vs_out output;
	{
		output.sv_pos = mul(proj_matrix, float4(local_vert, 0.f, 1.f));
		output.color = local_color;
		output.tex2d_uv = local_uv;
		output.sdf_pos = sdf_pos;
		output.half_size = half_size;
		output.cradii = input.cradii;
		output.kind = input.kind;
	}
	return output;
}

#define TEXT_THICKNESS  0.6
#define MSDF_PXRANGE    8.0

#define KIND_RECT		0
#define KIND_TEX2D	1
#define KIND_MSDF		2

float rect_sdf(float2 pos, float2 half_size, float r) {
	float2 q = abs(pos) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float msdf_median(float r, float g, float b) {
  return max(min(r, g), min(max(r, g), b));
}

float gradient_noise(float2 n) {
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
			// float aa = fwidth(dist);
			float aa = length(float2(ddx(dist), ddy(dist)));
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
    float screen_px_distance = screen_px_range * sd;

    float opacity = clamp(screen_px_distance + TEXT_THICKNESS, 0.0, 1.0);
    tex_color = float4(1.0, 1.0, 1.0, opacity);
	} break;
	// default:
	// 	break;
	}

  float4 out_color = input.color * tex_color;
  out_color.a *= alpha;

  // May broke video compression algos
  float noise = gradient_noise(input.sv_pos.xy);
  noise = (noise - 0.5) / 255.0;
  out_color.rgb += noise;

	return out_color;
}`

/*
#pragma pack_matrix( row_major )

float sRGBtoLinear(float v)
{
    if (v <= 0.04045) {
        v = (v / 12.92);
    } else {
        v = pow(abs(v + 0.055) / 1.055, 2.4);
    }
    return v;
}

float sRGBfromLinear(float v)
{
    if (v <= 0.0031308) {
        v = (v * 12.92);
    } else {
        v = (pow(abs(v), 1.0 / 2.4) * 1.055 - 0.055);
    }
    return v;
}
*/

/*
imm_d3d11_bind_vshader :: proc(vshader: D3D11_VShader) {
	if vshader != _imm_last.vshader {
		if len(_batch_list) > 0 {
			_imm_flush()
		}
		_imm_last.vshader = vshader
	}

	_d3d11_persist.device_ctx->IASetInputLayout(_imm_last.vshader.ilayout)
	_d3d11_persist.device_ctx->IASetPrimitiveTopology(.TRIANGLESTRIP)
	_d3d11_persist.device_ctx->VSSetShader(_imm_last.vshader.vshader, nil, 0)
}
imm_d3d11_bind_pshader :: proc(pshader: ^d3d11.IPixelShader) {
	if pshader != _imm_last.pshader {
		if len(_batch_list) > 0 {
			_imm_flush()
		}
		_imm_last.pshader = pshader
	}
	_d3d11_persist.device_ctx->PSSetShader(_imm_last.pshader, nil, 0)
}
*/
