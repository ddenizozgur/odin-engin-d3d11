#+build windows
package wm

import "core:container/intrusive/list"
import "core:sys/windows"

//
// Types
//
Window_Style :: enum {
	Windowed,
	FullScreen,
	// Secondary,
}

Window :: struct {
	node_link:            list.Node,
	//
	hwnd:                 windows.HWND, // TODO
	//
	size_last_frame:      [2]i32,
	size_this_frame:      [2]i32,
	is_resized:           bool,
	//
	btns_last_frame:      [Mouse_Btn]bool,
	btns_this_frame:      [Mouse_Btn]bool,
	btns_down_cnt:        i32,
	//
	keys_last_frame:      [Key_VkCode]bool, // TODO: Scancodes ??
	keys_this_frame:      [Key_VkCode]bool,
	//
	placement_last_frame: enum {
		Restore,
		Minimize,
		Maximize,
	},
}

Event_Kind :: enum {
	Key,
	Text,
	MouseBtn,
	MouseMove,
	MouseScroll,
	WindowFocus,
	WindowUnFocus,
	WindowMinimize,
	WindowMaximize,
	WindowRestore,
	WindowClose,
}

Event :: struct {
	kind:    Event_Kind,
	window:  ^Window,
	using _: struct #raw_union {
		key:          struct {
			vkcode:    Key_VkCode,
			mods:      Key_Mods,
			down_up:   bool,
			is_repeat: bool,
			// repeat_count: int,
		},
		text:         rune,
		mouse_btn:    struct {
			btn:     Mouse_Btn,
			down_up: bool,
		},
		mouse_move:   [2]i32,
		mouse_scroll: [2]f32,
	},
}

/*
Event_Key :: struct {
	window:    ^Window,
	vkcode:    Key_VkCode,
	mods:      Key_Mods,
	down_up:   bool,
	is_repeat: bool,
	// repeat_count: int,
}

Event_Text :: struct {
	window: ^Window,
	utf32:  rune,
}

Event_MouseBtn :: struct {
	window:  ^Window,
	btn:     Mouse_Btn,
	down_up: bool,
}

Event_MouseMove :: struct {
	window: ^Window,
	pos:    [2]i32,
}

Event_MouseScroll :: struct {
	window: ^Window,
	scroll: [2]f32,
}

Event_WindowFocus :: struct {
	window: ^Window,
}
Event_WindowUnfocus :: struct {
	window: ^Window,
}
Event_WindowMinimize :: struct {
	window: ^Window,
}
Event_WindowMaximize :: struct {
	window: ^Window,
}
Event_WindowRestore :: struct {
	window: ^Window,
}
Event_WindowClose :: struct {
	window: ^Window,
}

Event :: union {
	Event_Key,
	Event_Text,
	Event_MouseBtn,
	Event_MouseMove,
	Event_MouseScroll,
	Event_WindowFocus,
	Event_WindowUnfocus,
	Event_WindowMinimize,
	Event_WindowMaximize,
	Event_WindowRestore,
	Event_WindowClose,
}
*/

//
// Keys-Buttons
//
Mouse_Btn :: enum {
	Left,
	Middle,
	Right,
	XButton1,
	XButton2,
}

Key_Mod :: enum {
	Shift,
	Ctrl,
	Alt, // AltGr ????
	Super,
	CapsLock,
	NumLock,
}
Key_Mods :: bit_set[Key_Mod]

Key_VkCode :: enum u32 {
	Null = 0,
	Esc,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	F13,
	F14,
	F15,
	F16,
	F17,
	F18,
	F19,
	F20,
	F21,
	F22,
	F23,
	F24,
	Backtick,
	_0,
	_1,
	_2,
	_3,
	_4,
	_5,
	_6,
	_7,
	_8,
	_9,
	Minus,
	Equal,
	Backspace,
	Tab,
	Q,
	W,
	E,
	R,
	T,
	Y,
	U,
	I,
	O,
	P,
	LeftBracket,
	RightBracket,
	BackSlash,
	CapsLock,
	A,
	S,
	D,
	F,
	G,
	H,
	J,
	K,
	L,
	Semicolon,
	Quote,
	Return,
	Shift,
	Z,
	X,
	C,
	V,
	B,
	N,
	M,
	Comma,
	Period,
	Slash,
	Ctrl,
	Alt,
	Space,
	Menu,
	Super,
	// ScrollLock,
	Pause,
	Insert,
	Home,
	PageUp,
	Delete,
	End,
	PageDown,
	Up,
	Left,
	Down,
	Right,
	NumLock,
	NumSlash,
	NumStar,
	NumMinus,
	NumPlus,
	NumPeriod,
	Num0,
	Num1,
	Num2,
	Num3,
	Num4,
	Num5,
	Num6,
	Num7,
	Num8,
	Num9,
}
