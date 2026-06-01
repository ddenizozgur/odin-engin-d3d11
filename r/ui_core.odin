package r

import "../wm"
import "core:container/intrusive/list"
import "core:fmt"
import "core:hash"
import "core:mem"
import "core:mem/virtual"
import "core:strings"

UI_SizePerAxis_HardCoded :: distinct f32
UI_SizePerAxis_TextContent :: struct {}
UI_SizePerAxis_ChildrenSum :: struct {}
UI_SizePerAxis :: union {
	UI_SizePerAxis_HardCoded,
	UI_SizePerAxis_TextContent,
	UI_SizePerAxis_ChildrenSum,
}

UI_Widget_Flag :: enum {
	HasBg,
	HasBorder,
	HasText,
	Clickable,
	FillWidth,
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
	pref_size:     [2]UI_SizePerAxis,
	text:          string,
	//
	key:           u64,
	solved:        UI_Widget_Solved,
}

UI_Widget_Solved :: struct {
	pos:  [2]f32,
	size: [2]f32,
}

ui_initialize :: proc(window: ^wm.Window, font: Font, font_size: f32) -> bool {
	if err := virtual.arena_init_growing(&_ui_state.frame_arena); err != .None {
		fmt.eprintfln("[ERROR] Failed to initialize UI frame arena: %v", err)
		return false
	}

	if err := virtual.arena_init_growing(&_ui_state.arena); err != .None {
		fmt.eprintfln("[ERROR] Failed to initialize UI arena: %v", err)
		return false
	}

	{
		allocator := virtual.arena_allocator(&_ui_state.arena)
		// _ui_state.key_occur = make(map[u64]int, allocator = allocator)
		_ui_state.solved_last_frame = make(map[u64]UI_Widget_Solved, allocator = allocator)

		_ui_state.font = font
		_ui_state.font_size = font_size
		_ui_state.window = window
	}

	return true
}

ui_begin_frame :: proc() {
	_ui_state.mouse_pos = wm.get_mouse_pos_2f32(_ui_state.window)

	virtual.arena_free_all(&_ui_state.frame_arena)
	clear(&_ui_state.parent_stack)
	// clear(&_ui_state.key_occur)

	root := ui_build_root()
	ui_push_parent(root)
}
ui_end_frame :: proc() {
	root := _ui_state.parent_stack[0]
	ui_solve_vertical(root)
	ui_draw_tree(root)

	clear(&_ui_state.solved_last_frame)
	ui_store_solved_tree(root)
}
@(deferred_out = ui_end_frame)
UI_FRAME_SCOPED :: #force_inline proc() {
	ui_begin_frame()
}

ui_build_widget :: proc(
	text: string,
	flags: UI_Widget_Flags,
	pref_size: [2]UI_SizePerAxis,
) -> (
	^UI_Widget,
	UI_Action,
) {
	parent := ui_top_parent()
	key := ui_key_from_text(text, parent.key)

	widget, err := virtual.new_clone(
		&_ui_state.frame_arena,
		UI_Widget {
			flags = flags,
			pref_size = pref_size,
			text = ui_display_part_from_text(text),
			key = key,
		},
	)
	ui_link_child(parent, widget)

	if solved, good := _ui_state.solved_last_frame[key]; good {
		hovered := point_within_rect(_ui_state.mouse_pos, solved.pos, solved.size)

		return widget, UI_Action { 	// TODO: implement UI_Widget_Flags interaction
			hovered = hovered,
			pressed = hovered && wm.mouse_is_pressed(_ui_state.window, .Left),
			clicked = hovered && wm.mouse_is_released(_ui_state.window, .Left),
		}
	}

	return widget, {}
}

//
// Draw
//
UI_CRADII :: 6
UI_BORDER_SIZE :: f32(1)

UI_Theme :: enum {
	PanelBg,
	PanelBorder,
	ButtonBg,
	ButtonHoverBg,
	ButtonPressedBg,
	ButtonHoverBorder,
	Text,
	TextMuted,
}
ui_theme := [UI_Theme][4]RGBA8 {
	.PanelBg           = {
		RGBA8{22, 34, 54, 190},
		RGBA8{22, 34, 54, 190},
		RGBA8{11, 18, 31, 190},
		RGBA8{11, 18, 31, 190},
	},
	.PanelBorder       = RGBA8{58, 92, 122, 255},
	.ButtonBg          = {
		RGBA8{15, 23, 38, 190},
		RGBA8{15, 23, 38, 190},
		RGBA8{15, 23, 38, 190},
		RGBA8{15, 23, 38, 190},
	},
	.ButtonHoverBg     = {
		RGBA8{43, 82, 116, 190},
		RGBA8{43, 82, 116, 190},
		RGBA8{24, 57, 91, 190},
		RGBA8{24, 57, 91, 190},
	},
	.ButtonPressedBg   = {
		RGBA8{18, 42, 68, 215},
		RGBA8{18, 42, 68, 215},
		RGBA8{18, 42, 68, 215},
		RGBA8{18, 42, 68, 215},
	},
	.ButtonHoverBorder = RGBA8{80, 185, 255, 255},
	.Text              = RGBA8{232, 244, 255, 255},
	.TextMuted         = RGBA8{156, 181, 204, 255},
}

ui_draw_tree :: proc(w: ^UI_Widget) {
	hovered := point_within_rect(_ui_state.mouse_pos, w.solved.pos, w.solved.size)
	down := .Clickable in w.flags && hovered && wm.mouse_is_down(_ui_state.window, .Left)

	if .HasBg in w.flags {
		bgcol := ui_theme[.PanelBg]

		if .Clickable in w.flags {
			bgcol = ui_theme[.ButtonBg]
			if down {
				bgcol = ui_theme[.ButtonPressedBg]
			} else if hovered {
				bgcol = ui_theme[.ButtonHoverBg]
			}
		}

		if .HasBorder in w.flags {
			border_color := ui_theme[.PanelBorder]
			if .Clickable in w.flags && hovered {
				border_color = ui_theme[.ButtonHoverBorder]
			}

			draw_rect(w.solved.pos, w.solved.size, border_color, UI_CRADII)

			inner_pos := w.solved.pos + UI_BORDER_SIZE
			inner_size := w.solved.size - UI_BORDER_SIZE * 2
			inner_size.x = max(inner_size.x, f32(0))
			inner_size.y = max(inner_size.y, f32(0))

			draw_rect(inner_pos, inner_size, bgcol, max(UI_CRADII - UI_BORDER_SIZE, f32(0)))
		} else {
			draw_rect(w.solved.pos, w.solved.size, bgcol, UI_CRADII)
		}
	}

	if .HasText in w.flags && w.text != "" {
		text_color := ui_theme[.Text]
		if .Clickable in w.flags && !hovered {
			text_color = ui_theme[.TextMuted]
		}
		draw_text(_ui_state.font, w.text, w.solved.pos + UI_PAD, _ui_state.font_size, text_color)
	}

	it := list.iterator_head(w.children_list, UI_Widget, "sibling_link")
	for child in list.iterate_next(&it) {
		ui_draw_tree(child)
	}
}

//
// Layout
//
UI_GAP :: f32(4)
UI_PAD :: [2]f32{6, 2}

ui_measure_children_vertical :: proc(parent: ^UI_Widget) -> (res: [2]f32) {
	child_cnt := 0

	it := list.iterator_head(parent.children_list, UI_Widget, "sibling_link")
	for child in list.iterate_next(&it) {
		child_size := ui_get_pref_size(child)
		res.x = max(res.x, child_size.x)
		res.y += child_size.y
		child_cnt += 1
	}

	if child_cnt > 1 {
		res.y += UI_GAP * f32(child_cnt - 1)
	}

	return res
}

ui_get_pref_size :: proc(w: ^UI_Widget) -> [2]f32 {
	ui_pad := UI_PAD
	size: [2]f32

	for axis in 0 ..< 2 {
		switch s in w.pref_size[axis] {
		case UI_SizePerAxis_HardCoded:
			size[axis] = f32(s)

		case UI_SizePerAxis_TextContent:
			bbox := text_bbox(_ui_state.font, w.text, _ui_state.font_size)
			size[axis] = bbox[axis] + ui_pad[axis] * 2

		case UI_SizePerAxis_ChildrenSum:
			size[axis] = ui_measure_children_vertical(w)[axis] + UI_GAP * 2
		}
	}

	return size
}

ui_solve_vertical :: proc(parent: ^UI_Widget) {
	cursor := parent.solved.pos + UI_GAP

	it := list.iterator_head(parent.children_list, UI_Widget, "sibling_link")
	for child in list.iterate_next(&it) {
		final_size := ui_get_pref_size(child)
		if .FillWidth in child.flags {
			final_size.x = parent.solved.size.x - UI_GAP * 2
		}

		child.solved.pos = cursor
		child.solved.size = final_size

		ui_solve_vertical(child)
		cursor.y += final_size.y + UI_GAP
	}
}

ui_store_solved_tree :: proc(w: ^UI_Widget) {
	_ui_state.solved_last_frame[w.key] = w.solved
	it := list.iterator_head(w.children_list, UI_Widget, "sibling_link")
	for child in list.iterate_next(&it) {
		ui_store_solved_tree(child)
	}
}

//
// UI_Key
//
ui_display_part_from_text :: proc(text: string) -> string {
	if idx := strings.index(text, "###"); idx >= 0 {
		return text[:idx]
	}
	return text
}
ui_key_from_text :: proc(text: string, seed := u64(0xcbf29ce484222325)) -> u64 {
	if idx := strings.index(text, "###"); idx >= 0 {
		return hash.fnv64a(transmute([]byte)text[idx:], seed)
	}
	return hash.fnv64a(transmute([]byte)text, seed)
}

//
//
//
ui_link_child :: proc(parent, child: ^UI_Widget) {
	child.parent = parent
	list.push_back(&parent.children_list, &child.sibling_link)
}
ui_top_parent :: proc() -> ^UI_Widget {
	top := len(_ui_state.parent_stack) - 1
	return _ui_state.parent_stack[top]
}
ui_push_parent :: proc(parent: ^UI_Widget) {
	append(&_ui_state.parent_stack, parent)
}
ui_pop_parent :: proc() {
	pop(&_ui_state.parent_stack)
}
@(deferred_out = ui_pop_parent)
UI_PARENT_SCOPED :: #force_inline proc(parent: ^UI_Widget) {
	ui_push_parent(parent)
}

//
// Private
//
@(private = "file")
UI_PARENT_STACK_MAX :: 128
@(private = "file")
UI_State :: struct {
	arena:             virtual.Arena,
	frame_arena:       virtual.Arena,
	parent_stack:      [dynamic; UI_PARENT_STACK_MAX]^UI_Widget,
	// key_occur:         map[u64]int,
	solved_last_frame: map[u64]UI_Widget_Solved,
	// TODO: Theme
	font:              Font,
	font_size:         f32,
	//
	window:            ^wm.Window,
	mouse_pos:         [2]f32,
}
@(private = "file")
_ui_state: UI_State

@(private = "file")
ui_build_root :: proc() -> ^UI_Widget {
	widget, err := virtual.new_clone(
		&_ui_state.frame_arena,
		UI_Widget {
			flags = {},
			pref_size = UI_SizePerAxis_HardCoded(0),
			text = "",
			key = ui_key_from_text("###root"),
			solved = {pos = 0, size = wm.get_client_size_2f32(_ui_state.window) or_else {}},
		},
	)
	return widget
}
