package r

ui_to_test :: proc() {
	UI_FRAME_SCOPED()

	@(static) open_menu: u64

	{
		UI_PARENT_SCOPED(ui_panel("###editor_demo").box)

		{
			UI_PARENT_SCOPED(
				ui_panel("###editor_menu_bar", flags = {}, layout_axis = .Horizontal).box,
			)

			{
				UI_PARENT_SCOPED(ui_column("###file_menu_anchor"))

				file := ui_menu_button("File")
				if open_menu != 0 && file.hovered && open_menu != file.box.key {
					open_menu = file.box.key
				}
				if file.clicked {
					open_menu = file.box.key if open_menu != file.box.key else 0
				}

				if open_menu == file.box.key {
					UI_PARENT_SCOPED(ui_overlay("###file_menu"))

					if ui_menu_button("New Text File").clicked do open_menu = 0
					if ui_menu_button("Open File").clicked do open_menu = 0
					if ui_menu_button("Open Folder").clicked do open_menu = 0
					if ui_menu_button("Save").clicked do open_menu = 0
					if ui_menu_button("Save As...").clicked do open_menu = 0
				}
			}

			{
				UI_PARENT_SCOPED(ui_column("###edit_menu_anchor"))

				edit := ui_menu_button("Edit")
				if open_menu != 0 && edit.hovered && open_menu != edit.box.key {
					open_menu = edit.box.key
				}
				if edit.clicked {
					open_menu = edit.box.key if open_menu != edit.box.key else 0
				}

				if open_menu == edit.box.key {
					UI_PARENT_SCOPED(ui_overlay("###edit_menu"))

					if ui_menu_button("Undo").clicked do open_menu = 0
					if ui_menu_button("Redo").clicked do open_menu = 0
					if ui_menu_button("Cut").clicked do open_menu = 0
					if ui_menu_button("Copy").clicked do open_menu = 0
					if ui_menu_button("Paste").clicked do open_menu = 0
				}
			}

			{
				UI_PARENT_SCOPED(ui_column("###selection_menu_anchor"))

				selection := ui_menu_button("Selection")
				if open_menu != 0 && selection.hovered && open_menu != selection.box.key {
					open_menu = selection.box.key
				}
				if selection.clicked {
					open_menu = selection.box.key if open_menu != selection.box.key else 0
				}

				if open_menu == selection.box.key {
					UI_PARENT_SCOPED(ui_overlay("###selection_menu"))

					if ui_menu_button("Select All").clicked do open_menu = 0
					if ui_menu_button("Expand Selection").clicked do open_menu = 0
					if ui_menu_button("Shrink Selection").clicked do open_menu = 0
					if ui_menu_button("Duplicate Line").clicked do open_menu = 0
				}
			}

			{
				UI_PARENT_SCOPED(ui_column("###view_menu_anchor"))

				view := ui_menu_button("View")
				if open_menu != 0 && view.hovered && open_menu != view.box.key {
					open_menu = view.box.key
				}
				if view.clicked {
					open_menu = view.box.key if open_menu != view.box.key else 0
				}

				if open_menu == view.box.key {
					UI_PARENT_SCOPED(ui_overlay("###view_menu"))

					if ui_menu_button("Zoom In").clicked do open_menu = 0
					if ui_menu_button("Zoom Out").clicked do open_menu = 0
					if ui_menu_button("Word Wrap").clicked do open_menu = 0
					if ui_menu_button("Command Palette").clicked do open_menu = 0
				}
			}
		}

		{
			UI_PARENT_SCOPED(ui_panel("###editor_page").box)

			ui_label("untitled.txt")
			ui_label("Click a menu to open it. While open, hover another top menu to switch.")
		}
	}
}

ui_button :: proc(text: string) -> UI_Action {
	return ui_build_widget(
		text,
		{.HasBg, .HasHoverBg, .HasText, .Clickable},
		UI_Size_TextContent{},
	)
}
ui_menu_button :: proc(text: string) -> UI_Action {
	return ui_build_widget(
		text,
		{.HasHoverBg, .HasText, .Clickable, .FillParent},
		UI_Size_TextContent{},
	)
}
ui_label :: proc(text: string) -> UI_Action {
	return ui_build_widget(text, {.HasText}, UI_Size_TextContent{})
}

ui_panel :: proc(
	id: string,
	flags: UI_Box_Flags = {.HasBg, .HasBorder},
	bucket_flags: UI_Bucket_Flags = {},
	layout_axis := UI_Axis.Vertical,
) -> UI_Action {
	return ui_build_bucket(id, flags, bucket_flags, UI_Size_ChildrenSum{}, layout_axis)
}
ui_overlay :: proc(id: string, layout_axis := UI_Axis.Vertical) -> ^UI_Box {
	return ui_panel(id, bucket_flags = {.Overlay}, layout_axis = layout_axis).box
}

ui_column :: proc(id: string) -> ^UI_Box {
	return ui_panel(id, flags = {}, layout_axis = .Vertical).box
}
ui_row :: proc(id: string) -> ^UI_Box {
	return ui_panel(id, flags = {}, layout_axis = .Horizontal).box
}
