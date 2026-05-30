#+build windows
package wm

import "base:runtime"
import "core:container/intrusive/list"
import "core:fmt"
import "core:sys/windows"

get_dpi_scale :: proc(window: ^Window) -> f32 {
	dpi := windows.GetDpiForWindow(window.hwnd)
	return cast(f32)dpi / 96.
}

get_mouse_pos :: proc(window: ^Window) -> [2]i32 {
	// check for focused or not ???
	// TODO: impl dpi awareness
	v: [2]i32
	p: windows.POINT
	if (windows.GetCursorPos(&p)) {
		windows.ScreenToClient(window.hwnd, &p)
		v.x, v.y = p.x, p.y
	}
	return v
}
get_mouse_pos_2f32 :: proc(window: ^Window) -> [2]f32 {
	return cast([2]f32)get_mouse_pos(window)
}

window_set_title :: proc(window: ^Window, title: string) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	title16 := windows.utf8_to_wstring(title, context.temp_allocator)
	windows.SetWindowTextW(window.hwnd, title16)
}

window_set_focus :: proc(window: ^Window) {
	windows.SetForegroundWindow(window.hwnd)
	windows.SetFocus(window.hwnd)
}

// TODO: check??
window_minimize :: proc(window: ^Window) {windows.ShowWindow(window.hwnd, windows.SW_MINIMIZE)}
window_maximize :: proc(window: ^Window) {windows.ShowWindow(window.hwnd, windows.SW_MAXIMIZE)}
window_restore :: proc(window: ^Window) {windows.ShowWindow(window.hwnd, windows.SW_RESTORE)}

window_is_minimized :: proc(window: ^Window) -> bool {
	return cast(bool)windows.IsIconic(window.hwnd)
}
window_is_maximized :: proc(window: ^Window) -> bool {
	return cast(bool)windows.IsZoomed(window.hwnd)
}

window_is_focused :: proc(window: ^Window) -> bool {
	active := windows.GetActiveWindow()
	return active == window.hwnd
}

window_is_fullscreen :: proc(window: ^Window) -> bool {
	style := windows.GetWindowLongW(window.hwnd, windows.GWL_STYLE)
	return (cast(u32)style & windows.WS_OVERLAPPEDWINDOW) == 0
}

initialize :: proc() -> bool {
	// startup_info : windows.STARTUPINFOW
	// windows.GetStartupInfoW(&startup_info)

	// hicon := windows.LoadIconW(hinst, cast(windows.LPCWSTR)windows.MAKEINTRESOURCEW(2)) // RESOURCE_ID_FIRST_ICON
	// if (!hIcon) {
	//     exe_path: [MAX_PATH]u16;
	//     GetModuleFileNameW(null, exe_path.data, MAX_PATH);
	//     icon = ExtractIconW(hInstance, exe_path.data, 0); // 0 means first icon.
	// }

	_perm.wndclass = windows.WNDCLASSW {
		lpfnWndProc   = _window_proc,
		style         = windows.CS_VREDRAW | windows.CS_HREDRAW | windows.CS_OWNDC,
		hInstance     = cast(windows.HINSTANCE)windows.GetModuleHandleW(nil),
		hIcon         = windows.LoadIconA(nil, windows.IDI_APPLICATION),
		hCursor       = windows.LoadCursorA(nil, windows.IDC_ARROW),
		hbrBackground = cast(windows.HBRUSH)windows.GetStockObject(windows.WHITE_BRUSH), // This param doesnt matter since we provide WS_EX_NOREDIRECTIONBITMAP
		lpszClassName = "WndClassName",
	}

	if windows.RegisterClassW(&_perm.wndclass) == 0 {
		fmt.eprintfln("[ERROR] Failed to registrate WNDCLASSW") // TODO: maybe GetLastError()
		return false
	}

	return true
}

window_alloc :: proc(
	title: string,
	size: [2]i32,
	style := Window_Style.Windowed,
) -> (
	window: ^Window,
	good: bool,
) {
	// expects user to pass client size

	// TODO: check https://stackoverflow.com/q/63096226 and here: https://stackoverflow.com/q/53000291
	// WS_EX_NOREDIRECTIONBITMAP flag here is needed to fix ugly bug with Windows 10
	// when window is resized and DXGI swap chain uses FLIP presentation model
	// !!! just for directx11 !!! dont use it for opengl vulkan !!!

	dw_style: windows.DWORD // | windows.WS_CLIPCHILDREN | windows.WS_CLIPSIBLINGS
	ex_style := windows.WS_EX_APPWINDOW | windows.WS_EX_NOREDIRECTIONBITMAP

	xpos := windows.CW_USEDEFAULT
	ypos := windows.CW_USEDEFAULT
	window_rect: windows.RECT = {
		right  = size.x,
		bottom = size.y,
	}

	switch style {
	case .Windowed:
		dw_style = windows.WS_OVERLAPPEDWINDOW
		windows.AdjustWindowRectEx(&window_rect, dw_style, false, ex_style)
	case .FullScreen:
		dw_style = windows.WS_VISIBLE | windows.WS_POPUP

		// since window isn't created yet, we use the primary monitor
		hmonitor := windows.MonitorFromWindow(nil, .MONITOR_DEFAULTTOPRIMARY)
		mi: windows.MONITORINFO = {
			cbSize = size_of(windows.MONITORINFO),
		}
		if windows.GetMonitorInfoW(hmonitor, &mi) {
			window_rect = mi.rcMonitor
			xpos = mi.rcMonitor.left
			ypos = mi.rcMonitor.top
			// SetWindowPos(res.hwnd, HWND_TOPMOST, xpos, ypos, width, height,
			//     SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
		}
	// Secondary = windows.WS_OVERLAPPED | windows.WS_CAPTION | windows.WS_SYSMENU | windows.WS_THICKFRAME,
	}

	{
		window_w := window_rect.right - window_rect.left
		window_h := window_rect.bottom - window_rect.top

		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
		title16 := windows.utf8_to_wstring(title, context.temp_allocator)

		hwnd := windows.CreateWindowExW(
			ex_style,
			_perm.wndclass.lpszClassName,
			title16,
			dw_style,
			xpos,
			ypos,
			window_w,
			window_h,
			nil,
			nil,
			_perm.wndclass.hInstance,
			nil,
		)
		// DragAcceptFiles(_hwnd, TRUE);
		if (hwnd == nil) {
			fmt.eprintfln("[ERROR] Failed to create HWND")
			return
		}

		{
			r: windows.RECT
			windows.GetClientRect(hwnd, &r)
			client_w := r.right - r.left
			client_h := r.bottom - r.top

			window = new_clone(
				Window {
					hwnd = hwnd,
					size_this_frame = {client_w, client_h},
					size_last_frame = {client_w, client_h},
				},
			)
			list.push_back(&_perm.window_list, &window.node_link)
		}

		windows.ShowWindow(hwnd, windows.SW_SHOW)
		windows.UpdateWindow(hwnd)
	}

	return window, true
}

// window_free :: proc(window: ^Window) {
// 	list.remove(&_perm.window_list, &window.node_link)
// 	// windows.ReleaseDC(_hwnd, _hdc)
// 	windows.DestroyWindow(window.hwnd)
// }

// cleanup :: proc() {
// windows.UnregisterClassW(_wndclass.lpszClassName, _wndclass.hInstance)
// }

//
// Privates
//
@(private)
_find_window_from_hwnd :: proc(hwnd: windows.HWND) -> ^Window {
	it := list.iterator_head(_perm.window_list, Window, "node_link")
	for it in list.iterate_next(&it) {
		if it.hwnd == hwnd {
			return it
		}
	}
	return nil
}

@(private)
_perm: struct {
	window_list:      list.List,
	wndclass:         windows.WNDCLASSW,
	evnts_this_frame: [dynamic]Event,
}
// hdc: windows.HDC
