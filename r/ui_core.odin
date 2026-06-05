package r

import "../wm"
import "core:container/intrusive/list"
import "core:fmt"
import "core:hash"
import "core:mem/virtual"
import "core:strings"

UI_Size_HardCoded :: distinct f32
UI_Size_TextContent :: struct {}
UI_Size_ChildrenSum :: struct {}
UI_BucketSize :: union {
	UI_Size_HardCoded,
	UI_Size_ChildrenSum,
}
UI_WidgetSize :: union {
	UI_Size_HardCoded,
	UI_Size_TextContent,
}

UI_Axis :: enum {
	Vertical,
	Horizontal,
}

UI_Box_Flag :: enum {
	HasBg,
	HasHoverBg,
	HasBorder,
	HasText,
	Clickable,
	FillParent, // Fills opposite UI_Axis than parent's
}
UI_Box_Flags :: bit_set[UI_Box_Flag]

UI_Bucket_Flag :: enum {
	Overlay,
	HasPadding,
}
UI_Bucket_Flags :: bit_set[UI_Bucket_Flag]

UI_Box_Kind :: enum {
	Bucket,
	Widget,
}

UI_Box :: struct {
	kind:         UI_Box_Kind,
	parent_link:  ^UI_Box,
	sibling_link: list.Node,
	flags:        UI_Box_Flags,
	text:         string, // TODO: move to widget ??
	key:          u64,
	solved:       UI_Box_Solved,
	using _:      struct #raw_union {
		bucket: struct {
			children_list: list.List,
			flags:         UI_Bucket_Flags,
			pref_size:     [2]UI_BucketSize,
			layout_axis:   UI_Axis,
		},
		widget: struct {
			pref_size: [2]UI_WidgetSize,
		},
	},
}

UI_Box_Solved :: struct {
	pos:  [2]f32,
	size: [2]f32,
}

UI_Action :: struct {
	box:     ^UI_Box,
	hovered: bool,
	down:    bool,
	clicked: bool,
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
		// _ui_state.key_occur = make(map[u64]int, allocator = allocator)
		// _ui_state.solved_last_frame = make(
		// 	map[u64]UI_Box_Solved,
		// 	allocator = virtual.arena_allocator(&_ui_state.arena),
		// )

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
	clear(&_ui_state.overlays)
	// clear(&_ui_state.key_occur)

	ui_push_parent(ui_build_root())
}
ui_end_frame :: proc() {
	ui_solve_tree()
	ui_action_tree()
	ui_draw_tree()

	// clear(&_ui_state.solved_last_frame)
	// ui_store_solved_tree(root)
}
@(deferred_out = ui_end_frame)
UI_FRAME_SCOPED :: #force_inline proc() {
	ui_begin_frame()
}

ui_build_bucket :: proc(
	text: string,
	box_flags: UI_Box_Flags,
	bucket_flags: UI_Bucket_Flags,
	pref_size: [2]UI_BucketSize,
	layout_axis := UI_Axis.Vertical,
) -> UI_Action {
	parent := ui_top_parent()
	key := ui_key_from_text(text, parent.key)

	box, err := virtual.new_clone(
		&_ui_state.frame_arena,
		UI_Box {
			kind = .Bucket,
			flags = box_flags,
			text = ui_display_part_from_text(text),
			key = key,
			bucket = {flags = bucket_flags, pref_size = pref_size, layout_axis = layout_axis},
		},
	)

	ui_link_child(parent, box)
	if .Overlay in bucket_flags {
		append(&_ui_state.overlays, box)
	}

	return UI_Action {
		box = box,
		hovered = box.key == _ui_state.hot_key,
		down = box.key == _ui_state.down_key,
		clicked = box.key == _ui_state.clicked_key,
	}
	/*
	if solved, good := _ui_state.solved_last_frame[key]; good {
		hovered := point_within_rect(_ui_state.mouse_pos, solved.pos, solved.size)

		return UI_Action { 	// TODO: implement UI_Box_Flags interaction
			box     = box,
			hovered = hovered,
			pressed = hovered && wm.mouse_is_pressed(_ui_state.window, .Left),
			clicked = hovered && wm.mouse_is_released(_ui_state.window, .Left),
		}
	}
	*/
}

ui_build_widget :: proc(
	text: string,
	flags: UI_Box_Flags,
	pref_size: [2]UI_WidgetSize,
) -> UI_Action {
	parent := ui_top_parent()
	key := ui_key_from_text(text, parent.key)

	box, err := virtual.new_clone(
		&_ui_state.frame_arena,
		UI_Box {
			kind = .Widget,
			flags = flags,
			text = ui_display_part_from_text(text),
			key = key,
			widget = {pref_size = pref_size},
		},
	)
	ui_link_child(parent, box)

	return UI_Action {
		box = box,
		hovered = box.key == _ui_state.hot_key,
		down = box.key == _ui_state.down_key,
		clicked = box.key == _ui_state.clicked_key,
	}
	/*
	if solved, good := _ui_state.solved_last_frame[key]; good {
		hovered := point_within_rect(_ui_state.mouse_pos, solved.pos, solved.size)

		return UI_Action { 	// TODO: UI_Box_Flags interaction
			box     = box,
			hovered = hovered,
			pressed = hovered && wm.mouse_is_pressed(_ui_state.window, .Left),
			clicked = hovered && wm.mouse_is_released(_ui_state.window, .Left),
		}
	}
	*/
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
		RGBA8{17, 23, 34, 248},
		RGBA8{22, 30, 44, 248},
		RGBA8{10, 15, 24, 248},
		RGBA8{13, 19, 30, 248},
	},
	.PanelBorder       = RGBA8{48, 64, 88, 230},
	.ButtonBg          = {
		RGBA8{31, 41, 58, 252},
		RGBA8{36, 48, 68, 252},
		RGBA8{21, 29, 43, 252},
		RGBA8{25, 35, 51, 252},
	},
	.ButtonHoverBg     = {
		RGBA8{40, 65, 101, 255},
		RGBA8{48, 78, 121, 255},
		RGBA8{25, 45, 74, 255},
		RGBA8{32, 56, 90, 255},
	},
	.ButtonPressedBg   = {
		RGBA8{23, 43, 71, 255},
		RGBA8{29, 55, 90, 255},
		RGBA8{14, 28, 49, 255},
		RGBA8{19, 37, 62, 255},
	},
	.ButtonHoverBorder = RGBA8{94, 143, 214, 255},
	.Text              = RGBA8{229, 237, 248, 255},
	.TextMuted         = RGBA8{147, 160, 179, 255},
}

ui_draw_box :: proc(box: ^UI_Box) {
	hovered := box.key == _ui_state.hot_key
	down := box.key == _ui_state.down_key

	if .HasBg in box.flags || (.HasHoverBg in box.flags && (hovered || down)) {
		bgcol := ui_theme[.PanelBg]

		if .Clickable in box.flags {
			bgcol = ui_theme[.ButtonBg]
			if down {
				bgcol = ui_theme[.ButtonPressedBg]
			} else if hovered {
				bgcol = ui_theme[.ButtonHoverBg]
			}
		}

		if .HasBorder in box.flags {
			border_color := ui_theme[.PanelBorder]
			if .Clickable in box.flags && hovered {
				border_color = ui_theme[.ButtonHoverBorder]
			}

			draw_rect(box.solved.pos, box.solved.size, border_color, UI_CRADII)

			inner_pos := box.solved.pos + UI_BORDER_SIZE
			inner_size := box.solved.size - UI_BORDER_SIZE * 2
			inner_size.x = max(inner_size.x, 0)
			inner_size.y = max(inner_size.y, 0)

			draw_rect(inner_pos, inner_size, bgcol, max(UI_CRADII - UI_BORDER_SIZE, f32(0)))
		} else {
			draw_rect(box.solved.pos, box.solved.size, bgcol, UI_CRADII)
		}
	}

	if .HasText in box.flags && box.text != "" {
		text_color := ui_theme[.Text]
		if .Clickable in box.flags && !hovered {
			text_color = ui_theme[.TextMuted]
		}
		draw_text(
			_ui_state.font,
			box.text,
			box.solved.pos + UI_PAD,
			_ui_state.font_size,
			text_color,
		)
	}
}

ui_draw_tree :: proc() {
	inner :: proc(box: ^UI_Box) {
		ui_draw_box(box)

		if box.kind == .Bucket {
			it := list.iterator_head(box.bucket.children_list, UI_Box, "sibling_link")
			for child in list.iterate_next(&it) {
				if !(child.kind == .Bucket && .Overlay in child.bucket.flags) {
					inner(child)
				}
			}
		}
	}

	inner(_ui_state.parent_stack[0])
	for ovr in _ui_state.overlays {inner(ovr)}
}

//
// Action Pass
//
ui_action_tree :: proc() {
	inner :: proc(box: ^UI_Box) {
		if point_within_rect(_ui_state.mouse_pos, box.solved.pos, box.solved.size) {
			_ui_state.hot_key = box.key
			if .Clickable in box.flags {
				if wm.mouse_is_down(_ui_state.window, .Left) {_ui_state.down_key = box.key}
				if wm.mouse_is_released(_ui_state.window, .Left) {_ui_state.clicked_key = box.key}
			}
		}

		if box.kind == .Bucket {
			it := list.iterator_head(box.bucket.children_list, UI_Box, "sibling_link")
			for child in list.iterate_next(&it) {
				if !(child.kind == .Bucket && .Overlay in child.bucket.flags) {
					inner(child)
				}
			}
		}
	}

	root := _ui_state.parent_stack[0]
	_ui_state.hot_key = root.key
	_ui_state.down_key = root.key
	_ui_state.clicked_key = root.key

	inner(root)
	for ovr in _ui_state.overlays {inner(ovr)}
}

//
// Layout
//
UI_GAP :: f32(4)
UI_PAD :: [2]f32{6, 2}

ui_solve_tree :: proc() {
	inner :: proc(parent: ^UI_Box) {
		padding := f32(0)
		if .HasPadding in parent.bucket.flags {
			padding = UI_GAP
		}

		cursor := parent.solved.pos + padding

		it := list.iterator_head(parent.bucket.children_list, UI_Box, "sibling_link")
		for child in list.iterate_next(&it) {
			final_size := ui_get_pref_size(child)

			if child.kind == .Bucket && .Overlay in child.bucket.flags {
				if .FillParent in child.flags {
					switch parent.bucket.layout_axis {
					case .Horizontal:
						final_size.y = parent.solved.size.y - padding * 2
					case .Vertical:
						final_size.x = parent.solved.size.x - padding * 2
					}
				}

				child.solved.pos = cursor
				child.solved.size = final_size

				inner(child)
				continue
			}

			if .FillParent in child.flags {
				switch parent.bucket.layout_axis {
				case .Horizontal:
					final_size.y = parent.solved.size.y - padding * 2
				case .Vertical:
					final_size.x = parent.solved.size.x - padding * 2
				}
			}

			child.solved.pos = cursor
			child.solved.size = final_size

			if child.kind == .Bucket {
				inner(child)
			}

			switch parent.bucket.layout_axis {
			case .Horizontal:
				cursor.x += final_size.x + padding
			case .Vertical:
				cursor.y += final_size.y + padding
			}
		}
	}

	inner(_ui_state.parent_stack[0])
}

ui_solve_children_layout :: proc(parent: ^UI_Box) -> (res: [2]f32) {
	child_cnt := 0

	it := list.iterator_head(parent.bucket.children_list, UI_Box, "sibling_link")
	for child in list.iterate_next(&it) {
		if child.kind == .Bucket && .Overlay in child.bucket.flags {
			continue
		}

		child_size := ui_get_pref_size(child)

		switch parent.bucket.layout_axis {
		case .Horizontal:
			res.x += child_size.x
			res.y = max(res.y, child_size.y)
		case .Vertical:
			res.x = max(res.x, child_size.x)
			res.y += child_size.y
		}

		child_cnt += 1
	}

	if .HasPadding in parent.bucket.flags && child_cnt > 1 {
		switch parent.bucket.layout_axis {
		case .Horizontal:
			res.x += f32(child_cnt - 1) * UI_GAP
		case .Vertical:
			res.y += f32(child_cnt - 1) * UI_GAP
		}
	}

	return res
}

ui_get_pref_size :: proc(box: ^UI_Box) -> [2]f32 {
	ui_pad := UI_PAD
	size: [2]f32

	for axis in 0 ..< 2 {
		switch box.kind {
		case .Bucket:
			switch s in box.bucket.pref_size[axis] {
			case UI_Size_HardCoded:
				size[axis] = f32(s)
			case UI_Size_ChildrenSum:
				size[axis] = ui_solve_children_layout(box)[axis]
				if .HasPadding in box.bucket.flags {
					size[axis] += UI_GAP * 2
				}
			}
		case .Widget:
			switch s in box.widget.pref_size[axis] {
			case UI_Size_HardCoded:
				size[axis] = f32(s)
			case UI_Size_TextContent:
				bbox := text_bbox(_ui_state.font, box.text, _ui_state.font_size)
				size[axis] = bbox[axis] + ui_pad[axis] * 2
			}
		}
	}

	return size
}
/*
ui_store_solved_tree :: proc(box: ^UI_Box) {
	_ui_state.solved_last_frame[box.key] = box.solved
	if box.kind == .Bucket {
		it := list.iterator_head(box.bucket.children_list, UI_Box, "sibling_link")
		for child in list.iterate_next(&it) {
			ui_store_solved_tree(child)
		}
	}
}
*/

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
// Links
//
@(private)
ui_link_child :: proc(parent, child: ^UI_Box) {
	child.parent_link = parent
	list.push_back(&parent.bucket.children_list, &child.sibling_link)
}
ui_top_parent :: proc() -> ^UI_Box {
	top := len(_ui_state.parent_stack) - 1
	return _ui_state.parent_stack[top]
}
ui_push_parent :: proc(parent: ^UI_Box) {
	assert(parent.kind == .Bucket)
	append(&_ui_state.parent_stack, parent)
}
ui_pop_parent :: proc() {
	pop(&_ui_state.parent_stack)
}
@(deferred_out = ui_pop_parent)
UI_PARENT_SCOPED :: #force_inline proc(parent: ^UI_Box) {
	ui_push_parent(parent)
}

//
// Private
//
@(private = "file")
UI_PARENT_STACK_MAX :: 256
@(private = "file")
UI_OVERLAY_MAX :: 2048
@(private = "file")
UI_State :: struct {
	arena:        virtual.Arena,
	frame_arena:  virtual.Arena,
	parent_stack: [dynamic; UI_PARENT_STACK_MAX]^UI_Box,
	overlays:     [dynamic; UI_OVERLAY_MAX]^UI_Box,
	// key_occur:         map[u64]int,
	// solved_last_frame: map[u64]UI_Box_Solved,	// TODO
	hot_key:      u64,
	down_key:     u64,
	clicked_key:  u64,
	// TODO: Theme
	font:         Font,
	font_size:    f32,
	//
	window:       ^wm.Window,
	mouse_pos:    [2]f32,
}
@(private)
_ui_state: UI_State

@(private = "file")
ui_build_root :: proc() -> ^UI_Box {
	res, err := virtual.new_clone(
		&_ui_state.frame_arena,
		UI_Box {
			kind = .Bucket,
			text = "",
			key = ui_key_from_text("###root"),
			solved = {pos = 0, size = wm.get_client_size_2f32(_ui_state.window) or_else {}},
			bucket = {pref_size = UI_Size_HardCoded(0)},
		},
	)
	return res
}
