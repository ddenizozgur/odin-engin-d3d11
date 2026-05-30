package r

import "../wm"
import "core:container/intrusive/list"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"

UI_Size_TextContent :: distinct [2]f32
UI_Size_ChildrenSum :: distinct [2]f32
UI_Size_HardCoded :: distinct [2]f32
UI_Size :: union {
	UI_Size_TextContent,
	UI_Size_ChildrenSum,
	UI_Size_HardCoded,
}

UI_Widget_Flag :: enum {
	DrawBg,
	// DrawBorder,
	DrawText,
	Clickable,
}
UI_Widget_Flags :: bit_set[UI_Widget_Flag]

UI_Action :: struct {
	hovered: bool,
	pressed: bool,
	clicked: bool,
}

UI_Widget :: struct {
	parent:        ^UI_Widget,
	children_list: list.List,
	sibling_link:  list.Node,
	//
	flags:         UI_Widget_Flags,
	pref_size:     UI_Size,
	text:          string,
	//
	final_pos:     [2]f32,
	final_size:    [2]f32,
	action:        UI_Action,
}

ui_init :: proc(font: Font, font_size: f32) -> bool {
	{
		err := virtual.arena_init_growing(&_ui_per_frame.arena)
		if err != .None {
			fmt.eprintfln("[ERROR] Failed to initialize UI frame arena: %v", err)
			return false
		}
	}

	{
		_ui_perm.font = font
		_ui_perm.font_size = font_size
	}

	return true
}

ui_begin_frame :: proc() {

}

//
// Private
//
@(private)
_ui_per_frame: struct {
	arena: virtual.Arena,
}

@(private)
_ui_perm: struct {
	font:      Font,
	font_size: f32,
}
