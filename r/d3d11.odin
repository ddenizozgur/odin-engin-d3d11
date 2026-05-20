#+build windows
package r

import "core:fmt"
import "core:sys/windows"
import "core:time"

import "vendor:directx/d3d11"
import "vendor:directx/dxgi"

import "../wm"

Sampler_Kind :: enum {
	PointClamp,
	BilinearClamp,
}

Depth_Kind :: enum {
	Noop,
	MaskAll_FuncLess,
}

d3d11_set_sync_interval :: #force_inline proc(si: u32) {
	_d3d11_per_window.sync_interval = si
}

d3d11_swapchain_wait :: proc() {
	// Otherwise window will be stuck when minimized
	if !wm.window_is_minimized() {
		windows.WaitForSingleObject(_d3d11_per_window.swapchain_wait_handle, windows.INFINITE)
	}
}

d3d11_present :: proc() {
	if wm.window_is_minimized() {
		time.sleep(10 * time.Millisecond) // TODO: !! Hardcoded !!
		return
	}
	_d3d11_per_window.swapchain1->Present(_d3d11_per_window.sync_interval, {})
}

d3d11_clear_default_rtv :: proc(color: RGBA8) {
	tmp := rgba8_to_vec4f32(color)
	_d3d11_persist.device_ctx->ClearRenderTargetView(_d3d11_per_window.default_rtv, &tmp)
}

d3d11_set_default_rtv :: #force_inline proc() {
	_d3d11_persist.device_ctx->OMSetRenderTargets(1, &_d3d11_per_window.default_rtv, nil)
}

d3d11_resize_default_rtv :: proc(size: [2]f32) {
	{
		_d3d11_persist.device_ctx->OMSetRenderTargets(0, nil, nil)
		if _d3d11_per_window.default_rtv != nil { 	// do we need check nil??
			_d3d11_per_window.default_rtv->Release()
			_d3d11_per_window.default_rtv = nil
		}

		hres := _d3d11_per_window.swapchain1->ResizeBuffers(
			2,
			0,
			0,
			.R8G8B8A8_UNORM,
			{.FRAME_LATENCY_WAITABLE_OBJECT},
		)
		when ODIN_DEBUG {
			if windows.FAILED(hres) {
				fmt.eprintfln("[ERROR] DXGI ResizeBuffers failed")
				return
			}
		}

		rt: ^d3d11.ITexture2D
		_d3d11_per_window.swapchain1->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr)&rt)
		_d3d11_persist.device->CreateRenderTargetView(rt, nil, &_d3d11_per_window.default_rtv)
		rt->Release()

		d3d11_set_default_rtv()
	}

	{ 	// Viewport
		viewport := d3d11.VIEWPORT {
			TopLeftX = 0,
			TopLeftY = 0,
			Width    = size.x,
			Height   = size.y,
			MinDepth = 0,
			MaxDepth = 1,
		}
		_d3d11_persist.device_ctx->RSSetViewports(1, &viewport)
	}
}

// TODO: Error enum
d3d11_load :: proc() -> bool {
	_d3d11_load_persist() or_return

	{ 	// Swapchain
		desc := dxgi.SWAP_CHAIN_DESC1 {
			Width = 0,
			Height = 0,
			Format = .R8G8B8A8_UNORM,
			Stereo = false,
			SampleDesc = {Count = 1, Quality = 0},
			BufferUsage = {.RENDER_TARGET_OUTPUT},
			BufferCount = 2,
			Scaling = .NONE, // .STRETCH
			SwapEffect = .FLIP_DISCARD,
			AlphaMode = .UNSPECIFIED,
			Flags = {.FRAME_LATENCY_WAITABLE_OBJECT},
		}

		hres := _d3d11_persist.dxgi_factory2->CreateSwapChainForHwnd(
			_d3d11_persist.device,
			wm.get_hwnd(),
			&desc,
			nil,
			nil,
			&_d3d11_per_window.swapchain1,
		)
		if windows.FAILED(hres) {
			fmt.eprintfln("[ERROR] DXGI swapchain creation failed")
			return false
		}

		{ 	// Waitable Obj
			swapchain2: ^dxgi.ISwapChain2
			hres := _d3d11_per_window.swapchain1->QueryInterface(
				dxgi.ISwapChain2_UUID,
				cast(^rawptr)&swapchain2,
			)
			if windows.SUCCEEDED(hres) {
				swapchain2->SetMaximumFrameLatency(1)
				_d3d11_per_window.swapchain_wait_handle = swapchain2->GetFrameLatencyWaitableObject(

				)
				swapchain2->Release()
			} else {
				fmt.eprintfln("[WARNING] Failed to get ISwapChain2 for waitable object")
			}
		}

		_d3d11_persist.dxgi_factory2->MakeWindowAssociation(wm.get_hwnd(), {.NO_ALT_ENTER})
	}

	// Render Target
	{
		// desc := d3d11.RENDER_TARGET_VIEW_DESC {
		// 	Format = .R8G8B8A8_UNORM_SRGB,
		// 	ViewDimension = .TEXTURE2D
		// }
		rt: ^d3d11.ITexture2D
		_d3d11_per_window.swapchain1->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr)&rt)
		_d3d11_persist.device->CreateRenderTargetView(rt, nil, &_d3d11_per_window.default_rtv)
		rt->Release()
	}

	return true
}

//
// Privates
//
@(private)
_d3d11_persist: struct {
	device:        ^d3d11.IDevice,
	device_ctx:    ^d3d11.IDeviceContext,
	dxgi_factory2: ^dxgi.IFactory2,
	rasterizer:    ^d3d11.IRasterizerState,
	blend_state:   ^d3d11.IBlendState,
	samplers:      [Sampler_Kind]^d3d11.ISamplerState,
	depths:        [Depth_Kind]^d3d11.IDepthStencilState,
}

@(private) // We only have one window for now..
_d3d11_per_window: struct {
	swapchain1:            ^dxgi.ISwapChain1,
	swapchain_wait_handle: windows.HANDLE,
	default_rtv:           ^d3d11.IRenderTargetView,
	sync_interval:         u32,
}

@(private = "file")
_d3d11_base_device_and_ctx :: proc(
) -> (
	device: ^d3d11.IDevice,
	ctx: ^d3d11.IDeviceContext,
	good: bool,
) {
	// TODO: IFactory6 & adapter to handle multi-gpu ??
	features := [?]d3d11.FEATURE_LEVEL{._11_0}

	flags: d3d11.CREATE_DEVICE_FLAGS
	when ODIN_DEBUG {
		flags += {.DEBUG}
	}

	hres := d3d11.CreateDevice(
		nil,
		.HARDWARE, // Driver type
		nil,
		flags,
		&features[0],
		len(features),
		d3d11.SDK_VERSION,
		&device,
		nil,
		&ctx,
	)

	if windows.FAILED(hres) {
		hres = d3d11.CreateDevice(
			nil,
			.WARP,
			nil,
			flags,
			&features[0],
			len(features),
			d3d11.SDK_VERSION,
			&device,
			nil,
			&ctx,
		)

		if windows.FAILED(hres) {
			fmt.eprintfln("[ERROR] D3D11 base device creation failed")
			return
		}
	}

	return device, ctx, true
}

@(private = "file") // TODO: Error enum
_d3d11_load_persist :: proc() -> bool {
	{
		base_device, base_device_ctx := _d3d11_base_device_and_ctx() or_return
		defer {
			base_device->Release()
			base_device_ctx->Release()
		}

		base_device->QueryInterface(d3d11.IDevice_UUID, cast(^rawptr)&_d3d11_persist.device)
		base_device_ctx->QueryInterface(
			d3d11.IDeviceContext_UUID,
			cast(^rawptr)&_d3d11_persist.device_ctx,
		)
	}

	{
		dxgi_device: ^dxgi.IDevice
		dxgi_adapter: ^dxgi.IAdapter

		_d3d11_persist.device->QueryInterface(dxgi.IDevice_UUID, cast(^rawptr)&dxgi_device)
		dxgi_device->GetAdapter(&dxgi_adapter)
		dxgi_adapter->GetParent(dxgi.IFactory2_UUID, cast(^rawptr)&_d3d11_persist.dxgi_factory2)
		// dxgi_device1->SetMaximumFrameLatency(1)	// dont work ??

		dxgi_device->Release()
		dxgi_adapter->Release()
	}

	{ 	// Rasterizer
		desc := d3d11.RASTERIZER_DESC {
			FillMode      = .SOLID,
			CullMode      = .NONE, // check
			ScissorEnable = false,
		}
		_d3d11_persist.device->CreateRasterizerState(&desc, &_d3d11_persist.rasterizer)
	}

	{ 	// Blend Alpha
		desc: d3d11.BLEND_DESC
		{
			desc.RenderTarget[0].BlendEnable = true
			desc.RenderTarget[0].SrcBlend = .SRC_ALPHA
			desc.RenderTarget[0].SrcBlendAlpha = .ONE
			desc.RenderTarget[0].DestBlend = .INV_SRC_ALPHA
			desc.RenderTarget[0].DestBlendAlpha = .ZERO
			desc.RenderTarget[0].BlendOp = .ADD
			desc.RenderTarget[0].BlendOpAlpha = .ADD
			desc.RenderTarget[0].RenderTargetWriteMask = cast(u8)d3d11.COLOR_WRITE_ENABLE_ALL
		}
		_d3d11_persist.device->CreateBlendState(&desc, &_d3d11_persist.blend_state)
	}

	{ 	// Samplers
		desc := d3d11.SAMPLER_DESC {
			Filter         = .MIN_MAG_MIP_POINT,
			AddressU       = .CLAMP,
			AddressV       = .CLAMP,
			AddressW       = .CLAMP,
			ComparisonFunc = .NEVER,
		}
		_d3d11_persist.device->CreateSamplerState(&desc, &_d3d11_persist.samplers[.PointClamp])

		desc.Filter = .MIN_MAG_MIP_LINEAR
		_d3d11_persist.device->CreateSamplerState(&desc, &_d3d11_persist.samplers[.BilinearClamp])
	}

	{ 	// Depth Stencil
		desc := d3d11.DEPTH_STENCIL_DESC {
			DepthEnable    = false,
			DepthWriteMask = .ALL,
			DepthFunc      = .LESS,
		}
		_d3d11_persist.device->CreateDepthStencilState(&desc, &_d3d11_persist.depths[.Noop])

		desc.DepthEnable = true
		_d3d11_persist.device->CreateDepthStencilState(
			&desc,
			&_d3d11_persist.depths[.MaskAll_FuncLess],
		)
	}

	{ 	// First Run
		_d3d11_persist.device_ctx->PSSetSamplers(0, 1, &_d3d11_persist.samplers[.BilinearClamp])
		_d3d11_persist.device_ctx->RSSetState(_d3d11_persist.rasterizer)
		_d3d11_persist.device_ctx->OMSetDepthStencilState(_d3d11_persist.depths[.Noop], 0)
		_d3d11_persist.device_ctx->OMSetBlendState(_d3d11_persist.blend_state, nil, 0xffffffff)
	}

	return true
}
