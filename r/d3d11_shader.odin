#+build windows
package r

import "core:fmt"
import "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/d3d_compiler"

D3D11_VShader :: struct {
	// Bundled at initialization, dont change
	vshader: ^d3d11.IVertexShader,
	ilayout: ^d3d11.IInputLayout,
}

d3d11_vshader_init :: proc(
	src: string,
	dbg_name: cstring,
	ilayout_desc: []d3d11.INPUT_ELEMENT_DESC,
	out: ^D3D11_VShader,
) -> bool {
	vshader_blob: ^d3d11.IBlob
	vshader_error: ^d3d11.IBlob

	hres := d3d_compiler.Compile(
		raw_data(src),
		len(src),
		dbg_name,
		nil,
		nil,
		"vs_main",
		"vs_5_0",
		0,
		0,
		&vshader_blob,
		&vshader_error,
	)
	defer if vshader_blob != nil {
		vshader_blob->Release()
	}

	if windows.FAILED(hres) {
		err_ptr := cast([^]byte)vshader_error->GetBufferPointer()
		err_len := vshader_error->GetBufferSize()
		err_msg := cast(string)err_ptr[:err_len]
		fmt.eprintfln("[ERROR] Failed to compile vshader:\n%s", err_msg)
		return false
	} else {
		_d3d11_persist.device->CreateVertexShader(
			vshader_blob->GetBufferPointer(),
			vshader_blob->GetBufferSize(),
			nil,
			&out.vshader,
		)
	}

	// Input Layout
	_d3d11_persist.device->CreateInputLayout(
		raw_data(ilayout_desc),
		cast(u32)len(ilayout_desc),
		vshader_blob->GetBufferPointer(),
		vshader_blob->GetBufferSize(),
		&out.ilayout,
	)

	return true
}

d3d11_pshader_init :: proc(src: string, dbg_name: cstring, out: ^^d3d11.IPixelShader) -> bool {
	pshader_blob: ^d3d11.IBlob
	pshader_error: ^d3d11.IBlob

	hres := d3d_compiler.Compile(
		raw_data(src),
		len(src),
		dbg_name,
		nil,
		nil,
		"ps_main",
		"ps_5_0",
		0,
		0,
		&pshader_blob,
		&pshader_error,
	)
	defer if pshader_blob != nil {
		pshader_blob->Release()
	}

	if windows.FAILED(hres) {
		err_ptr := cast([^]byte)pshader_error->GetBufferPointer()
		err_len := pshader_error->GetBufferSize()
		err_msg := cast(string)err_ptr[:err_len]
		fmt.eprintfln("[ERROR] Failed to compile pshader:\n%s", err_msg)
		return false
	} else {
		_d3d11_persist.device->CreatePixelShader(
			pshader_blob->GetBufferPointer(),
			pshader_blob->GetBufferSize(),
			nil,
			out,
		)
	}

	return true
}

d3d11_uniforms_init :: proc($T: typeid, out: ^^d3d11.IBuffer) -> bool {
	if size_of(T) % 16 != 0 {
		assert(false, "Struct size must be align with 16 bytes")
		return false
	}

	desc := d3d11.BUFFER_DESC {
		ByteWidth      = size_of(T),
		Usage          = .DYNAMIC,
		BindFlags      = {.CONSTANT_BUFFER},
		CPUAccessFlags = {.WRITE},
	}

	hres := _d3d11_persist.device->CreateBuffer(&desc, nil, out)
	if windows.FAILED(hres) {
		fmt.eprintfln("[ERROR] Failed to create uniform buffer")
		return false
	}

	return true
}
