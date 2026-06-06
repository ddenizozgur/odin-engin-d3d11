#+build windows
package wm

import "base:runtime"
import "core:container/intrusive/list"
import "core:sys/windows"
import "core:unicode"
import "core:unicode/utf16"

get_client_size :: proc(window: ^Window) -> ([2]i32, bool) {
	return window.size_this_frame, window.is_resized
}
get_client_size_2f32 :: proc(window: ^Window) -> ([2]f32, bool) {
	return cast([2]f32)window.size_this_frame, window.is_resized
}

mouse_is_down :: proc(window: ^Window, btn: Mouse_Btn) -> bool {
	return window.btns_this_frame[btn]
}
mouse_is_pressed :: proc(window: ^Window, btn: Mouse_Btn) -> bool {
	was_down := window.btns_last_frame[btn]
	is_down := window.btns_this_frame[btn]
	return is_down && !was_down
}
mouse_is_released :: proc(window: ^Window, btn: Mouse_Btn) -> bool {
	was_down := window.btns_last_frame[btn]
	is_down := window.btns_this_frame[btn]
	return !is_down && was_down
}

key_is_down :: proc(window: ^Window, key: Key_VkCode) -> bool {
	return window.keys_this_frame[key]
}
key_is_pressed :: proc(window: ^Window, key: Key_VkCode) -> bool {
	was_down := window.keys_last_frame[key]
	is_down := window.keys_this_frame[key]
	return is_down && !was_down
}
key_is_released :: proc(window: ^Window, key: Key_VkCode) -> bool {
	was_down := window.keys_last_frame[key]
	is_down := window.keys_this_frame[key]
	return !is_down && was_down
}

poll_events_this_frame :: proc() -> []Event {
	wnd_it := list.iterator_head(_state.window_list, Window, "node_link")
	for wnd_it in list.iterate_next(&wnd_it) {
		for it in Mouse_Btn {
			down_up := wnd_it.btns_this_frame[it]
			wnd_it.btns_last_frame[it] = down_up
		}
		for it in Key_VkCode {
			down_up := wnd_it.keys_this_frame[it]
			wnd_it.keys_last_frame[it] = down_up
		}
		wnd_it.is_resized = false
	}
	clear(&_state.evnts_this_frame)

	msg: windows.MSG
	for windows.PeekMessageW(&msg, nil, 0, 0, windows.PM_REMOVE) {
		windows.TranslateMessage(&msg)
		windows.DispatchMessageW(&msg)
	}

	return _state.evnts_this_frame[:]
}

@(private)
_window_proc :: proc "system" (
	hwnd: windows.HWND,
	msg: windows.UINT,
	wparam: windows.WPARAM,
	lparam: windows.LPARAM,
) -> windows.LRESULT {
	context = runtime.default_context()

	result := windows.LRESULT(0)
	window := _find_window_from_hwnd(hwnd)
	if window == nil {
		return windows.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	switch msg {
	// case windows.WM_DESTROY:
	case windows.WM_CLOSE:
		append(&_state.evnts_this_frame, Event{kind = .WindowClose, window = window})

	// TODO: WM_INPUTLANGCHANGE ??
	// case windows.WM_ENTERSIZEMOVE:
	// 	_entersizemove = true
	// case windows.WM_EXITSIZEMOVE:
	// 	_entersizemove = false
	// case windows.WM_SIZING:
	// 	result = 1

	case windows.WM_SIZE:
		_on_resize(window, wparam, lparam)
	case windows.WM_SETFOCUS:
		append(&_state.evnts_this_frame, Event{kind = .WindowFocus, window = window})
	case windows.WM_KILLFOCUS:
		append(&_state.evnts_this_frame, Event{kind = .WindowUnFocus, window = window})
		_release_btns(window)
		_release_keys(window)

	// case windows.WM_INPUT: // TODO: rawinput
	case windows.WM_PAINT:
		ps: windows.PAINTSTRUCT
		_ = windows.BeginPaint(hwnd, &ps)
		// do NOTHING here...
		windows.EndPaint(hwnd, &ps)
	// DwmFlush();

	case windows.WM_LBUTTONUP:
		_update_btns(window, .Left, false)
	case windows.WM_LBUTTONDOWN:
		_update_btns(window, .Left, true)
	case windows.WM_MBUTTONUP:
		_update_btns(window, .Middle, false)
	case windows.WM_MBUTTONDOWN:
		_update_btns(window, .Middle, true)
	case windows.WM_RBUTTONUP:
		_update_btns(window, .Right, false)
	case windows.WM_RBUTTONDOWN:
		_update_btns(window, .Right, true)
	case windows.WM_XBUTTONUP:
		_update_btns(window, windows.HIWORD(wparam) == 1 ? .XButton1 : .XButton2, false)
		// https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-xbuttondown
		// Unlike the WM_LBUTTONDOWN, WM_MBUTTONDOWN, and WM_RBUTTONDOWN messages,
		// an application should return TRUE from this message if it processes it
		result = 1
	case windows.WM_XBUTTONDOWN:
		_update_btns(window, windows.HIWORD(wparam) == 1 ? .XButton1 : .XButton2, true)
		result = 1

	case windows.WM_MOUSEMOVE:
		x := windows.GET_X_LPARAM(lparam)
		y := windows.GET_Y_LPARAM(lparam)
		append(
			&_state.evnts_this_frame,
			Event{kind = .MouseMove, window = window, mouse_move = {x, y}},
		)

	case windows.WM_MOUSEWHEEL:
		vert_scroll := cast(f32)windows.GET_WHEEL_DELTA_WPARAM(wparam) / _MOUSE_SCROLL_NORMVAL // TODO: check sign
		append(
			&_state.evnts_this_frame,
			Event{kind = .MouseScroll, window = window, mouse_scroll = {0., vert_scroll}},
		)
	case windows.WM_MOUSEHWHEEL:
		horz_scroll := cast(f32)windows.GET_WHEEL_DELTA_WPARAM(wparam) / _MOUSE_SCROLL_NORMVAL // TODO: check sign
		append(
			&_state.evnts_this_frame,
			Event{kind = .MouseScroll, window = window, mouse_scroll = {horz_scroll, 0.}},
		)

	case windows.WM_SYSKEYDOWN:
		if wparam == windows.VK_F4 {
			// return windows.DefWindowProcW(hwnd, msg, wparam, lparam)
			append(&_state.evnts_this_frame, Event{kind = .WindowClose, window = window})
			break
		}
		if wparam != windows.VK_MENU && (wparam < windows.VK_F1 || wparam > windows.VK_F24) {
			result = windows.DefWindowProcW(hwnd, msg, wparam, lparam)
		}
		fallthrough
	case windows.WM_SYSKEYUP, windows.WM_KEYUP, windows.WM_KEYDOWN:
		_update_keys(window, wparam, lparam)

	case windows.WM_SYSCHAR:
		result = windows.DefWindowProcW(hwnd, msg, wparam, lparam)
	case windows.WM_CHAR:
		@(static) high_surrogate: rune
		w := cast(rune)wparam

		is_high_surrogate := (w >= 0xD800 && w <= 0xDBFF)
		is_low_surrogate := (w >= 0xDC00 && w <= 0xDFFF)

		codepoint := unicode.REPLACEMENT_CHAR
		if is_high_surrogate {
			high_surrogate = w
			break
		} else if is_low_surrogate {
			if high_surrogate != 0 {
				codepoint = utf16.decode_surrogate_pair(high_surrogate, w)
				high_surrogate = 0
			} else {
				// invalid
				break
			}
		} else {
			codepoint = w
			high_surrogate = 0
		}

		if codepoint == unicode.REPLACEMENT_CHAR {
			break
		}

		if unicode.is_graphic(codepoint) {
			append(
				&_state.evnts_this_frame,
				Event{kind = .Text, window = window, text = codepoint},
			)
		}

	case windows.WM_ERASEBKGND:
		result = 1 // we fill out the client area so no need to erase the background

	case:
		result = windows.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	return result
}

// _get_mouse_source :: proc() -> Mouse_Source {
// 	signature := windows.GetMessageExtraInfo() & 0xFFFFFF80
// 	if signature == 0xFF515700 do return .Pen
// 	if signature == 0xFF515780 do return .TouchScreen
// 	return .Mouse
// }

// ?? const bool swapped = (TRUE == GetSystemMetrics(SM_SWAPBUTTON));
@(private = "file")
_MOUSE_SCROLL_NORMVAL :: f32(120)

@(private = "file")
_update_btns :: proc(window: ^Window, btn: Mouse_Btn, down_up: bool) {
	if window.btns_this_frame[btn] != down_up {
		window.btns_this_frame[btn] = down_up

		if down_up {
			if window.btns_down_cnt == 0 {
				windows.SetCapture(window.hwnd)
			}
			window.btns_down_cnt += 1
		} else {
			window.btns_down_cnt -= 1
			if window.btns_down_cnt <= 0 && windows.GetCapture() == window.hwnd {
				windows.ReleaseCapture()
				window.btns_down_cnt = 0
			}
		}
	}

	append(
		&_state.evnts_this_frame,
		Event{kind = .MouseBtn, window = window, mouse_btn = {btn = btn, down_up = down_up}},
	)
}

@(private = "file")
_release_btns :: proc(window: ^Window) {
	for btn in Mouse_Btn {
		if window.btns_this_frame[btn] {
			_update_btns(window, btn, false)
		}
	}
	window.btns_down_cnt = 0
}

@(private = "file")
_update_keys :: proc(window: ^Window, wparam: windows.WPARAM, lparam: windows.LPARAM) {
	was_down := (lparam & (1 << 30)) != 0
	is_down := (lparam & (1 << 31)) == 0
	is_repeat := is_down && was_down

	vkcode := _vkcode_from_vk(cast(u32)wparam)
	keymods := _get_keymods()

	// do we want this???
	#partial switch vkcode {
	case .Ctrl:
		keymods -= {.Ctrl}
	case .Shift:
		keymods -= {.Shift}
	case .Alt:
		keymods -= {.Alt}
	case .Super:
		keymods -= {.Super}
	case .CapsLock:
		keymods -= {.CapsLock}
	case .NumLock:
		keymods -= {.NumLock}
	}

	if vkcode != .Null {
		window.keys_this_frame[vkcode] = is_down
	}

	append(
		&_state.evnts_this_frame,
		Event {
			kind = .Key,
			window = window,
			key = {
				vkcode    = vkcode,
				mods      = keymods,
				down_up   = is_down,
				is_repeat = is_repeat,
				// repeat_count = is_repeat ? lparam & 0xffff : 0,
			},
		},
	)
}

@(private = "file")
_release_keys :: proc(window: ^Window) {
	for vkcode in Key_VkCode {
		if window.keys_this_frame[vkcode] {
			window.keys_this_frame[vkcode] = false
			append(
				&_state.evnts_this_frame,
				Event {
					kind = .Key,
					window = window,
					key = {vkcode = vkcode, mods = {}, down_up = false, is_repeat = false},
				},
			)
		}
	}
}

@(private = "file")
_get_keymods :: proc() -> (mod: Key_Mods) {
	if cast(u16)windows.GetKeyState(windows.VK_SHIFT) & 0x8000 != 0 do mod += {.Shift}
	if cast(u16)windows.GetKeyState(windows.VK_CONTROL) & 0x8000 != 0 do mod += {.Ctrl}
	if cast(u16)windows.GetKeyState(windows.VK_MENU) & 0x8000 != 0 do mod += {.Alt}

	lwin := cast(u16)windows.GetKeyState(windows.VK_LWIN) & 0x8000 != 0
	rwin := cast(u16)windows.GetKeyState(windows.VK_RWIN) & 0x8000 != 0
	if lwin || rwin do mod += {.Super}

	if cast(u16)windows.GetKeyState(windows.VK_CAPITAL) & 1 != 0 do mod += {.CapsLock}
	if cast(u16)windows.GetKeyState(windows.VK_NUMLOCK) & 1 != 0 do mod += {.NumLock}

	return mod
}

@(private = "file")
_on_resize :: proc(window: ^Window, wparam: windows.WPARAM, lparam: windows.LPARAM) {
	window.size_this_frame.x = cast(i32)windows.LOWORD(lparam)
	window.size_this_frame.y = cast(i32)windows.HIWORD(lparam)
	if window.size_this_frame != window.size_last_frame {
		window.is_resized = true
		window.size_last_frame = window.size_this_frame
	}

	switch wparam {
	case windows.SIZE_MINIMIZED:
		append(&_state.evnts_this_frame, Event{kind = .WindowMinimize, window = window})
		window.placement_last_frame = .Minimize
	case windows.SIZE_MAXIMIZED:
		append(&_state.evnts_this_frame, Event{kind = .WindowMaximize, window = window})
		window.placement_last_frame = .Maximize
	case windows.SIZE_RESTORED:
		if window.placement_last_frame != .Restore {
			append(&_state.evnts_this_frame, Event{kind = .WindowRestore, window = window})
			window.placement_last_frame = .Restore
		}
	}
}

@(private = "file")
_vkcode_from_vk :: proc(vk: u32) -> Key_VkCode {
	switch vk {
	case 'A':
		return .A
	case 'B':
		return .B
	case 'C':
		return .C
	case 'D':
		return .D
	case 'E':
		return .E
	case 'F':
		return .F
	case 'G':
		return .G
	case 'H':
		return .H
	case 'I':
		return .I
	case 'J':
		return .J
	case 'K':
		return .K
	case 'L':
		return .L
	case 'M':
		return .M
	case 'N':
		return .N
	case 'O':
		return .O
	case 'P':
		return .P
	case 'Q':
		return .Q
	case 'R':
		return .R
	case 'S':
		return .S
	case 'T':
		return .T
	case 'U':
		return .U
	case 'V':
		return .V
	case 'W':
		return .W
	case 'X':
		return .X
	case 'Y':
		return .Y
	case 'Z':
		return .Z
	case '0' ..= '9':
		return ._0 + cast(Key_VkCode)(vk - '0')
	case windows.VK_NUMPAD0 ..= windows.VK_NUMPAD9:
		return .Num0 + cast(Key_VkCode)(vk - windows.VK_NUMPAD0)
	case windows.VK_F1 ..= windows.VK_F24:
		return .F1 + cast(Key_VkCode)(vk - windows.VK_F1)
	case windows.VK_SPACE:
		return .Space
	case windows.VK_OEM_3:
		return .Backtick
	case windows.VK_OEM_MINUS:
		return .Minus
	case windows.VK_OEM_PLUS:
		return .Equal
	case windows.VK_OEM_4:
		return .LeftBracket
	case windows.VK_OEM_6:
		return .RightBracket
	case windows.VK_OEM_1:
		return .Semicolon
	case windows.VK_OEM_7:
		return .Quote
	case windows.VK_OEM_COMMA:
		return .Comma
	case windows.VK_OEM_PERIOD:
		return .Period
	case windows.VK_OEM_2:
		return .Slash
	case windows.VK_OEM_5:
		return .BackSlash
	case windows.VK_TAB:
		return .Tab
	case windows.VK_PAUSE:
		return .Pause
	case windows.VK_ESCAPE:
		return .Esc
	case windows.VK_UP:
		return .Up
	case windows.VK_LEFT:
		return .Left
	case windows.VK_DOWN:
		return .Down
	case windows.VK_RIGHT:
		return .Right
	case windows.VK_BACK:
		return .Backspace
	case windows.VK_RETURN:
		return .Return
	case windows.VK_DELETE:
		return .Delete
	case windows.VK_INSERT:
		return .Insert
	case windows.VK_PRIOR:
		return .PageUp
	case windows.VK_NEXT:
		return .PageDown
	case windows.VK_HOME:
		return .Home
	case windows.VK_END:
		return .End
	case windows.VK_CAPITAL:
		return .CapsLock
	case windows.VK_NUMLOCK:
		return .NumLock
	case windows.VK_LWIN, windows.VK_RWIN:
		return .Super
	// case windows.VK_SCROLL:
	// 	return .ScrollLock
	case windows.VK_APPS:
		return .Menu
	case windows.VK_CONTROL, windows.VK_LCONTROL, windows.VK_RCONTROL:
		return .Ctrl
	case windows.VK_SHIFT, windows.VK_LSHIFT, windows.VK_RSHIFT:
		return .Shift
	case windows.VK_MENU, windows.VK_LMENU, windows.VK_RMENU:
		return .Alt
	case windows.VK_DIVIDE:
		return .NumSlash
	case windows.VK_MULTIPLY:
		return .NumStar
	case windows.VK_SUBTRACT:
		return .NumMinus
	case windows.VK_ADD:
		return .NumPlus
	case windows.VK_DECIMAL:
		return .NumPeriod
	// case 0xDF ..= 0xFC:
	// 	// TODO: check
	// 	return .Ex0 + cast(Key_Code)(vkey - 0xDF)
	}
	return .Null
}

@(private = "file")
_vk_from_vkcode :: proc(vkcode: Key_VkCode) -> u32 {
	switch vkcode {
	case .Null:
		return 0
	case .Esc:
		return windows.VK_ESCAPE
	case .F1 ..= .F24:
		return cast(u32)windows.VK_F1 + cast(u32)(vkcode - .F1)
	case .Backtick:
		return windows.VK_OEM_3
	case ._0 ..= ._9:
		return cast(u32)'0' + cast(u32)(vkcode - ._0)
	case .Minus:
		return windows.VK_OEM_MINUS
	case .Equal:
		return windows.VK_OEM_PLUS
	case .Backspace:
		return windows.VK_BACK
	case .Tab:
		return windows.VK_TAB
	case .Q:
		return 'Q'
	case .W:
		return 'W'
	case .E:
		return 'E'
	case .R:
		return 'R'
	case .T:
		return 'T'
	case .Y:
		return 'Y'
	case .U:
		return 'U'
	case .I:
		return 'I'
	case .O:
		return 'O'
	case .P:
		return 'P'
	case .LeftBracket:
		return windows.VK_OEM_4
	case .RightBracket:
		return windows.VK_OEM_6
	case .BackSlash:
		return windows.VK_OEM_5
	case .CapsLock:
		return windows.VK_CAPITAL
	case .Super:
		return windows.VK_LWIN
	case .A:
		return 'A'
	case .S:
		return 'S'
	case .D:
		return 'D'
	case .F:
		return 'F'
	case .G:
		return 'G'
	case .H:
		return 'H'
	case .J:
		return 'J'
	case .K:
		return 'K'
	case .L:
		return 'L'
	case .Semicolon:
		return windows.VK_OEM_1
	case .Quote:
		return windows.VK_OEM_7
	case .Return:
		return windows.VK_RETURN
	case .Shift:
		return windows.VK_SHIFT
	case .Z:
		return 'Z'
	case .X:
		return 'X'
	case .C:
		return 'C'
	case .V:
		return 'V'
	case .B:
		return 'B'
	case .N:
		return 'N'
	case .M:
		return 'M'
	case .Comma:
		return windows.VK_OEM_COMMA
	case .Period:
		return windows.VK_OEM_PERIOD
	case .Slash:
		return windows.VK_OEM_2
	case .Ctrl:
		return windows.VK_CONTROL
	case .Alt:
		return windows.VK_MENU
	case .Space:
		return windows.VK_SPACE
	case .Menu:
		return windows.VK_APPS
	// case .ScrollLock:
	// 	return windows.VK_SCROLL
	case .Pause:
		return windows.VK_PAUSE
	case .Insert:
		return windows.VK_INSERT
	case .Home:
		return windows.VK_HOME
	case .PageUp:
		return windows.VK_PRIOR
	case .Delete:
		return windows.VK_DELETE
	case .End:
		return windows.VK_END
	case .PageDown:
		return windows.VK_NEXT
	case .Up:
		return windows.VK_UP
	case .Left:
		return windows.VK_LEFT
	case .Down:
		return windows.VK_DOWN
	case .Right:
		return windows.VK_RIGHT
	// case .Ex0 ..= .Ex29:
	// 	return cast(u32)0xDF + cast(u32)(keycode - .Ex0)
	case .NumLock:
		return windows.VK_NUMLOCK
	case .NumSlash:
		return windows.VK_DIVIDE
	case .NumStar:
		return windows.VK_MULTIPLY
	case .NumMinus:
		return windows.VK_SUBTRACT
	case .NumPlus:
		return windows.VK_ADD
	case .NumPeriod:
		return windows.VK_DECIMAL
	case .Num0 ..= .Num9:
		return cast(u32)windows.VK_NUMPAD0 + cast(u32)(vkcode - .Num0)
	}
	return 0
}
