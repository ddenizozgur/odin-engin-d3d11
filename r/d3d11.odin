#+build windows
package r

import "core:fmt"
import "core:sys/windows"

import D3D11 "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"

import "../wm"

Sampler_Kind :: enum {
	BilinearClamp,
	PointClamp,
}

Depth_Kind :: enum {
	Noop,
	MaskAll_FuncLess,
}

Swapchain :: struct {
	swapchain1:      ^DXGI.ISwapChain1,
	flags:           DXGI.SWAP_CHAIN,
	waitable_handle: windows.HANDLE,
	default_rtv:     ^D3D11.IRenderTargetView,
}

d3d11_swapchain_wait :: proc(swapchain: Swapchain, window: ^wm.Window) {
	// Otherwise window will be stuck when minimized
	if !wm.window_is_minimized(window) {
		windows.WaitForSingleObject(swapchain.waitable_handle, windows.INFINITE)
	}
}

d3d11_present :: proc(swapchain: Swapchain, sync_interval := u32(0)) {
	flags: DXGI.PRESENT
	if sync_interval == 0 && .ALLOW_TEARING in swapchain.flags {
		flags += {.ALLOW_TEARING}
	}
	swapchain.swapchain1->Present(sync_interval, flags)
}

d3d11_clear_default_rtv :: proc(swapchain: Swapchain, color: RGBA8) {
	tmp_color := rgba8_to_vec4f32(color)
	_d3d11_perm.device_ctx->ClearRenderTargetView(swapchain.default_rtv, &tmp_color)
}

d3d11_set_default_rtv :: proc(swapchain: ^Swapchain) {
	_d3d11_perm.device_ctx->OMSetRenderTargets(1, &swapchain.default_rtv, nil)
}

d3d11_resize_default_rtv :: proc(swapchain: ^Swapchain, size: [2]f32) {
	{
		_d3d11_perm.device_ctx->OMSetRenderTargets(0, nil, nil)
		if swapchain.default_rtv != nil {
			swapchain.default_rtv->Release()
			swapchain.default_rtv = nil
		}

		hr := swapchain.swapchain1->ResizeBuffers(2, 0, 0, .R8G8B8A8_UNORM, swapchain.flags)
		if windows.FAILED(hr) {
			fmt.eprintfln("[ERROR] DXGI ResizeBuffers failed")
			return
		}

		rt: ^D3D11.ITexture2D
		swapchain.swapchain1->GetBuffer(0, D3D11.ITexture2D_UUID, cast(^rawptr)&rt)
		_d3d11_perm.device->CreateRenderTargetView(rt, nil, &swapchain.default_rtv)
		rt->Release()

		d3d11_set_default_rtv(swapchain)
	}

	{ 	// Viewport
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
}

d3d11_initialize :: proc() -> bool {
	// TODO: Error enum
	_d3d11_create_device_and_ctx(&_d3d11_perm.device, &_d3d11_perm.device_ctx) or_return

	when ODIN_DEBUG {
		debug: ^D3D11.IDebug
		hr := _d3d11_perm.device->QueryInterface(D3D11.IDebug_UUID, cast(^rawptr)&debug)
		if windows.SUCCEEDED(hr) {
			info_queue: ^D3D11.IInfoQueue
			hr = debug->QueryInterface(D3D11.IInfoQueue_UUID, cast(^rawptr)&info_queue)
			if windows.SUCCEEDED(hr) {
				info_queue->SetBreakOnSeverity(.CORRUPTION, true)
				info_queue->SetBreakOnSeverity(.ERROR, true)
				// info_queue->SetBreakOnSeverity(.WARNING, true)
				info_queue->Release()
			}
			debug->Release()
		}
	}

	{
		dxgi_device: ^DXGI.IDevice
		dxgi_adapter: ^DXGI.IAdapter

		_d3d11_perm.device->QueryInterface(DXGI.IDevice_UUID, cast(^rawptr)&dxgi_device)
		dxgi_device->GetAdapter(&dxgi_adapter)
		dxgi_adapter->GetParent(DXGI.IFactory2_UUID, cast(^rawptr)&_d3d11_perm.dxgi_factory2)
		// dxgi_device1->SetMaximumFrameLatency(1)	// not work ??

		dxgi_device->Release()
		dxgi_adapter->Release()
	}

	{ 	// Rasterizer
		desc := D3D11.RASTERIZER_DESC {
			FillMode      = .SOLID,
			CullMode      = .NONE, // check
			ScissorEnable = false,
		}
		_d3d11_perm.device->CreateRasterizerState(&desc, &_d3d11_perm.rasterizer)
	}

	{ 	// Blend Alpha
		desc: D3D11.BLEND_DESC
		{
			desc.RenderTarget[0].BlendEnable = true
			desc.RenderTarget[0].SrcBlend = .SRC_ALPHA
			desc.RenderTarget[0].SrcBlendAlpha = .ONE
			desc.RenderTarget[0].DestBlend = .INV_SRC_ALPHA
			desc.RenderTarget[0].DestBlendAlpha = .ZERO
			desc.RenderTarget[0].BlendOp = .ADD
			desc.RenderTarget[0].BlendOpAlpha = .ADD
			desc.RenderTarget[0].RenderTargetWriteMask = cast(u8)D3D11.COLOR_WRITE_ENABLE_ALL
		}
		_d3d11_perm.device->CreateBlendState(&desc, &_d3d11_perm.blend_state)
	}

	{ 	// Samplers
		desc := D3D11.SAMPLER_DESC {
			Filter         = .MIN_MAG_MIP_POINT,
			AddressU       = .CLAMP,
			AddressV       = .CLAMP,
			AddressW       = .CLAMP,
			ComparisonFunc = .NEVER,
		}
		_d3d11_perm.device->CreateSamplerState(&desc, &_d3d11_perm.samplers[.PointClamp])

		desc.Filter = .MIN_MAG_MIP_LINEAR
		_d3d11_perm.device->CreateSamplerState(&desc, &_d3d11_perm.samplers[.BilinearClamp])
	}

	{ 	// Depth Stencil
		desc := D3D11.DEPTH_STENCIL_DESC {
			DepthEnable    = false,
			DepthWriteMask = .ALL,
			DepthFunc      = .LESS,
		}
		_d3d11_perm.device->CreateDepthStencilState(&desc, &_d3d11_perm.depths[.Noop])

		desc.DepthEnable = true
		_d3d11_perm.device->CreateDepthStencilState(&desc, &_d3d11_perm.depths[.MaskAll_FuncLess])
	}

	{ 	// First Run
		_d3d11_perm.device_ctx->PSSetSamplers(0, 1, &_d3d11_perm.samplers[.BilinearClamp])
		_d3d11_perm.device_ctx->RSSetState(_d3d11_perm.rasterizer)
		_d3d11_perm.device_ctx->OMSetDepthStencilState(_d3d11_perm.depths[.Noop], 0)
		_d3d11_perm.device_ctx->OMSetBlendState(_d3d11_perm.blend_state, nil, 0xffffffff)
	}

	return true
}

d3d11_create_swapchain :: proc(window: ^wm.Window) -> (swapchain: Swapchain, good: bool) {
	// TODO: Error enum

	{ 	// Swapchain
		swapchain.flags = {.FRAME_LATENCY_WAITABLE_OBJECT}
		if _d3d11_is_tearing_supported() {
			swapchain.flags += {.ALLOW_TEARING}
		}

		desc := DXGI.SWAP_CHAIN_DESC1 {
			Width = 0,
			Height = 0,
			Format = .R8G8B8A8_UNORM,
			Stereo = false,
			SampleDesc = {Count = 1, Quality = 0},
			BufferUsage = {.RENDER_TARGET_OUTPUT},
			BufferCount = 2,
			Scaling = .STRETCH,
			SwapEffect = .FLIP_DISCARD,
			AlphaMode = .UNSPECIFIED,
			Flags = swapchain.flags,
		}

		hr := _d3d11_perm.dxgi_factory2->CreateSwapChainForHwnd(
			_d3d11_perm.device,
			window.hwnd,
			&desc,
			nil,
			nil,
			&swapchain.swapchain1,
		)
		if windows.FAILED(hr) {
			fmt.eprintfln("[ERROR] DXGI swapchain creation failed")
			return
		}

		_d3d11_perm.dxgi_factory2->MakeWindowAssociation(window.hwnd, {.NO_ALT_ENTER})
	}

	{ 	// Waitable Obj
		swapchain2: ^DXGI.ISwapChain2
		hr := swapchain.swapchain1->QueryInterface(DXGI.ISwapChain2_UUID, cast(^rawptr)&swapchain2)
		if windows.SUCCEEDED(hr) {
			swapchain2->SetMaximumFrameLatency(1)
			swapchain.waitable_handle = swapchain2->GetFrameLatencyWaitableObject()
			swapchain2->Release()
		} else {
			fmt.eprintfln("[WARNING] Failed to get ISwapChain2 for waitable object")
		}
	}

	{ 	// Render Target
		// desc := D3D11.RENDER_TARGET_VIEW_DESC {
		// 	Format = .R8G8B8A8_UNORM_SRGB,
		// 	ViewDimension = .TEXTURE2D
		// }
		rt: ^D3D11.ITexture2D
		swapchain.swapchain1->GetBuffer(0, D3D11.ITexture2D_UUID, cast(^rawptr)&rt)
		_d3d11_perm.device->CreateRenderTargetView(rt, nil, &swapchain.default_rtv)
		rt->Release()
	}

	return swapchain, true
}

//
// Privates
//
@(private)
_d3d11_perm: struct {
	device:        ^D3D11.IDevice,
	device_ctx:    ^D3D11.IDeviceContext,
	dxgi_factory2: ^DXGI.IFactory2,
	rasterizer:    ^D3D11.IRasterizerState,
	blend_state:   ^D3D11.IBlendState,
	samplers:      [Sampler_Kind]^D3D11.ISamplerState,
	depths:        [Depth_Kind]^D3D11.IDepthStencilState,
}

@(private = "file")
_d3d11_is_tearing_supported :: proc() -> (is: b32) {
	factory5: ^DXGI.IFactory5
	hr := _d3d11_perm.dxgi_factory2->QueryInterface(DXGI.IFactory5_UUID, cast(^rawptr)&factory5)
	if windows.SUCCEEDED(hr) {
		factory5->CheckFeatureSupport(.PRESENT_ALLOW_TEARING, &is, size_of(is))
		factory5->Release()
	}
	return is
}

@(private = "file")
_d3d11_create_device_and_ctx :: proc(
	out_device: ^^D3D11.IDevice,
	out_ctx: ^^D3D11.IDeviceContext,
) -> bool {
	// TODO: IFactory6 & adapter to handle multi-gpu ??
	features := [?]D3D11.FEATURE_LEVEL{._11_0}

	flags: D3D11.CREATE_DEVICE_FLAGS
	when ODIN_DEBUG {
		flags += {.DEBUG}
	}

	hr := D3D11.CreateDevice(
		nil,
		.HARDWARE, // Driver type
		nil,
		flags,
		&features[0],
		len(features),
		D3D11.SDK_VERSION,
		out_device,
		nil,
		out_ctx,
	)

	if windows.FAILED(hr) {
		hr = D3D11.CreateDevice(
			nil,
			.WARP,
			nil,
			flags,
			&features[0],
			len(features),
			D3D11.SDK_VERSION,
			out_device,
			nil,
			out_ctx,
		)

		if windows.FAILED(hr) {
			fmt.eprintfln("[ERROR] Failed to create D3D11 device")
			return false
		}
	}

	return true
}
