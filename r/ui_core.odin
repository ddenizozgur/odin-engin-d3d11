package r

import "../wm"
import "core:container/intrusive/list"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"

UI_Size_HardCoded :: distinct [2]f32
UI_Size_TextContent :: distinct [2]f32
UI_Size_ChildrenSum :: distinct [2]f32
UI_Size :: union {
	UI_Size_HardCoded,
	UI_Size_TextContent,
	UI_Size_ChildrenSum,
}

UI_Widget_Flag :: enum {
	DrawBg,
	DrawBorder,
	DrawText,
	Clickable,
}
UI_Widget_Flags :: bit_set[UI_Widget_Flag]

UI_Action :: struct {
	hovered: bool,
	clicked: bool,
}

UI_Widget :: struct {
	parent:        ^UI_Widget,
	children_list: list.List,
	sibling_link:  list.Node,
	// child_layout_axis:               i32,
	flags:         UI_Widget_Flags,
	pref_size:     UI_Size,
	text:          string,
	final_pos:     [2]f32,
	final_size:    [2]f32,
}

ui_init :: proc(font: Font, font_size := f32(18)) -> bool {
	err := virtual.arena_init_static(&_ui_persist.frame_arena, commit_size = 8 * mem.Kilobyte)
	if err != .None {
		fmt.eprintfln("[ERROR] Failed to initialize arena: %v", err)
		return false
	}

	_ui_persist.font = font
	_ui_persist.font_size = font_size

	return true
}

ui_begin_frame :: proc() {
	virtual.arena_free_all(&_ui_persist.frame_arena)

	clear(&_ui_persist.parent_stack)
	root := ui_build_root()
	ui_push_parent(root)
}
ui_end_frame :: proc() {
	root := _ui_persist.parent_stack[0]
	ui_solve_layout_vertical(root)
	ui_draw_tree(root)
}
@(deferred_out = ui_end_frame)
UI_FRAME_SCOPED :: #force_inline proc() {
	ui_begin_frame()
}

ui_draw_tree :: proc(w: ^UI_Widget) {
	if .DrawBg in w.flags {
		bgcol := UI_PANEL_BG
		if .Clickable in w.flags {
			bgcol = UI_CTRL_BG
		}

		if .DrawBorder in w.flags {
			imm_push_rect(w.final_pos, w.final_size, UI_BORDER, UI_CRADII)
			imm_push_rect(
				w.final_pos + UI_BORDER_SIZE,
				w.final_size - UI_BORDER_SIZE * 2,
				bgcol,
				UI_CRADII - UI_BORDER_SIZE,
			)

		} else {
			imm_push_rect(w.final_pos, w.final_size, bgcol, UI_CRADII)
		}
	}

	if .DrawText in w.flags && w.text != "" {
		imm_push_text(
			_ui_persist.font,
			w.text,
			w.final_pos + UI_INNER_PADDING,
			_ui_persist.font_size,
			UI_TEXT,
		)
	}

	it := list.iterator_head(w.children_list, UI_Widget, "sibling_link")
	for child in list.iterate_next(&it) {
		ui_draw_tree(child)
	}
}

ui_solve_layout_vertical :: proc(parent: ^UI_Widget) {
	cursor := parent.final_pos + UI_OUTER_PADDING

	it := list.iterator_head(parent.children_list, UI_Widget, "sibling_link")
	for child in list.iterate_next(&it) {
		child.final_pos = cursor
		child.final_size = ui_get_pref_size(child)

		ui_solve_layout_vertical(child)

		cursor.y += child.final_size.y + UI_OUTER_PADDING.y
	}
}

ui_get_pref_size :: proc(w: ^UI_Widget) -> [2]f32 {
	switch s in w.pref_size {
	case UI_Size_HardCoded:
		return cast([2]f32)s

	case UI_Size_TextContent:
		bbox := text_bbox(_ui_persist.font, w.text, _ui_persist.font_size)
		return bbox + UI_INNER_PADDING * 2

	case UI_Size_ChildrenSum:
		res := [2]f32{0, UI_OUTER_PADDING.y}

		it := list.iterator_head(w.children_list, UI_Widget, "sibling_link")
		for child in list.iterate_next(&it) {
			child_size := ui_get_pref_size(child)
			res.x = max(res.x, child_size.x)
			res.y += child_size.y + UI_OUTER_PADDING.y
		}

		res.x += UI_OUTER_PADDING.x * 2
		return res
	}

	return 0
}

ui_build_root :: proc() -> ^UI_Widget {
	return ui_alloc_widget("", {}, UI_Size_HardCoded{0, 0})
}

ui_build_widget :: proc(text: string, flags: UI_Widget_Flags, pref_size: UI_Size) -> ^UI_Widget {
	w := ui_alloc_widget(text, flags, pref_size)
	parent := ui_top_parent()
	ui_link_child(parent, w)
	return w
}

ui_alloc_widget :: proc(text: string, flags: UI_Widget_Flags, pref_size: UI_Size) -> ^UI_Widget {
	w, err := virtual.new_clone(
		&_ui_persist.frame_arena,
		UI_Widget{text = text, flags = flags, pref_size = pref_size},
	)
	when ODIN_DEBUG {
		if err != .None {
			fmt.eprintfln("[ERROR] Failed to allocate UI_Widget: %v", err)
			return nil
		}
	}
	return w
}

ui_link_child :: proc(parent, child: ^UI_Widget) {
	child.parent = parent
	list.push_back(&parent.children_list, &child.sibling_link)
}

ui_top_parent :: proc() -> ^UI_Widget {
	top := len(_ui_persist.parent_stack) - 1
	return _ui_persist.parent_stack[top]
}

ui_push_parent :: proc(parent: ^UI_Widget) {
	append(&_ui_persist.parent_stack, parent)
}
ui_pop_parent :: proc() {
	pop(&_ui_persist.parent_stack)
}
@(deferred_out = ui_pop_parent)
UI_PARENT_SCOPED :: #force_inline proc(parent: ^UI_Widget) {
	ui_push_parent(parent)
}

@(private = "file")
_ui_persist: struct {
	frame_arena:  virtual.Arena,
	parent_stack: [dynamic; PARENT_STACK_MAX]^UI_Widget,
	// root: ^UI_Widget,
	//
	font:         Font,
	font_size:    f32,
}

PARENT_STACK_MAX :: 256

UI_INNER_PADDING :: [2]f32{6, 2}
UI_OUTER_PADDING :: [2]f32{4, 4}
UI_CRADII :: 6
UI_BORDER_SIZE :: f32(1)

UI_PANEL_BG :: RGBA8{24, 28, 34, 255}
UI_CTRL_BG :: RGBA8{45, 53, 64, 255}
UI_CTRL_HOT :: RGBA8{65, 78, 94, 255}
UI_BORDER :: RGBA8{72, 84, 100, 255}
UI_TEXT :: RGBA8{238, 242, 247, 255}
UI_MUTED_TEXT :: RGBA8{170, 180, 194, 255}
UI_ACCENT :: RGBA8{90, 170, 255, 255}

// UI_DARK_GRAY :: RGBA8{55, 55, 55, 255}
// UI_DARKER_GRAY :: RGBA8{35, 35, 35, 255}
// UI_LIGHT_GRAY :: RGBA8{85, 85, 85, 255}
// UI_ALMOST_WHITE :: RGBA8{245, 245, 245, 255}
