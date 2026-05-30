#+build windows
package r

import "base:runtime"
import "core:fmt"
import "core:image"
import "core:sys/windows"
import D3D11 "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"

RSrc_Kind :: enum {
	Static,
	Dynamic,
	Stream,
}

d3d11_usage_from_rsrc_kind :: proc(
	kind: RSrc_Kind,
) -> (
	usage: D3D11.USAGE,
	cpu_access: D3D11.CPU_ACCESS_FLAGS,
) {
	switch kind {
	case .Static:
		usage = .IMMUTABLE
	case .Dynamic:
		usage = .DEFAULT
	case .Stream:
		usage = .DYNAMIC
		cpu_access += {.WRITE} // WRITE access to use Map with WRITE_DISCARD ??
	}
	return
}

Tex2D_Fmt :: enum {
	R8_UNORM,
	RG8_UNORM,
	RGBA8_UNORM,
	// R16_UNORM,
	// RGBA16_UNORM,
	// R16_FLOAT,
	// RGBA16_FLOAT,
	// R32_FLOAT,
	// RG32_FLOAT,
	// RGBA32_FLOAT,
}

d3d11_dxgi_fmt_from_tex2d :: proc(
	fmt: Tex2D_Fmt,
) -> (
	dxgi_fmt: DXGI.FORMAT,
	bytes_per_texel: u32,
) {
	switch fmt {
	case .R8_UNORM:
		dxgi_fmt = .R8_UNORM
		bytes_per_texel = 1
	case .RG8_UNORM:
		dxgi_fmt = .R8G8_UNORM
		bytes_per_texel = 2
	case .RGBA8_UNORM:
		dxgi_fmt = .R8G8B8A8_UNORM
		bytes_per_texel = 4
	}
	return
}

D3D11_Tex2D :: struct {
	srv:  ^D3D11.IShaderResourceView,
	size: [2]u32,
}

d3d11_tex2d_alloc_ex :: proc(
	bytes: []byte,
	size: [2]u32,
	rsrc_kind := RSrc_Kind.Static,
	tex2d_fmt := Tex2D_Fmt.RGBA8_UNORM,
) -> (
	tex: D3D11_Tex2D,
	good: bool,
) {
	tex.size = size

	d3d_tex: ^D3D11.ITexture2D
	defer if d3d_tex != nil {
		d3d_tex->Release()
	}

	dxgi_fmt, bytes_per_texel := d3d11_dxgi_fmt_from_tex2d(tex2d_fmt)
	{
		usage, cpu_access := d3d11_usage_from_rsrc_kind(rsrc_kind)

		desc := D3D11.TEXTURE2D_DESC {
			Width = size.x,
			Height = size.y,
			MipLevels = 1,
			ArraySize = 1,
			Format = dxgi_fmt,
			SampleDesc = {Count = 1, Quality = 0},
			Usage = usage,
			BindFlags = {.SHADER_RESOURCE},
			CPUAccessFlags = cpu_access,
			MiscFlags = {},
		}

		init_data := D3D11.SUBRESOURCE_DATA {
			pSysMem          = raw_data(bytes),
			SysMemPitch      = size.x * bytes_per_texel,
			SysMemSlicePitch = 0,
		}

		hr := _d3d11_perm.device->CreateTexture2D(&desc, &init_data, &d3d_tex)
		if windows.FAILED(hr) {
			fmt.eprintfln("[ERROR] Failed to create D3D11 Texture2D")
			return
		}
	}

	{
		desc := D3D11.SHADER_RESOURCE_VIEW_DESC {
			Format = dxgi_fmt,
			ViewDimension = .TEXTURE2D,
			Texture2D = {MipLevels = 1},
		}

		hr := _d3d11_perm.device->CreateShaderResourceView(d3d_tex, &desc, &tex.srv)
		if windows.FAILED(hr) {
			fmt.eprintfln("[ERROR] Failed to create D3D11 Shader Resource View")
			return
		}
	}

	return tex, true
}

d3d11_tex2d_alloc_from_img :: proc(img: ^image.Image) -> (tex2d: D3D11_Tex2D, good: bool) {
	tex2d_fmt: Tex2D_Fmt

	switch img.depth {
	case 8:
		switch img.channels {
		case 1:
			tex2d_fmt = .R8_UNORM
		case 2:
			tex2d_fmt = .RG8_UNORM
		case 3:
			fmt.eprintf("[ERROR] Not implemented")
			return
		case 4:
			tex2d_fmt = .RGBA8_UNORM
		}
	case:
		fmt.eprintf("[ERROR] Not implemented")
		return
	}

	size := [2]u32{cast(u32)img.width, cast(u32)img.height}
	return d3d11_tex2d_alloc_ex(img.pixels.buf[:], size, .Static, tex2d_fmt)
}

d3d11_tex2d_alloc_from_file :: proc(filepath: string) -> (tex2d: D3D11_Tex2D, good: bool) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	img, err := image.load_from_file(
		filepath,
		options = {.alpha_add_if_missing},
		allocator = context.temp_allocator,
	)
	if err != image.General_Image_Error.None {
		fmt.eprintfln("[ERROR]: %v", err)
		return
	}

	return d3d11_tex2d_alloc_from_img(img)
}

d3d11_tex2d_free :: proc(tex: ^D3D11_Tex2D) {
	if tex.srv != nil {
		tex.srv->Release()
		tex.srv = nil
	}
}
