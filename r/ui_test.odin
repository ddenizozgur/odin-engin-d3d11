package r

ui_to_test :: proc() {
	UI_FRAME_SCOPED()

	{
		UI_PARENT_SCOPED(ui_panel("###menu", layout_axis = .Horizontal).box)

		ui_label("Kralsın")
		{
			UI_PARENT_SCOPED(ui_column("###tmp"))

			if ui_menu_button("File").hovered {
				UI_PARENT_SCOPED(ui_overlay("###tmp"))

				ui_menu_button("New")
				ui_menu_button("New Window")
				//ui_menu_button("")
				ui_menu_button("Open File")
				ui_menu_button("Open Folder")
			}
		}

		{
			UI_PARENT_SCOPED(ui_column("###tmp"))

			if ui_menu_button("Edit").hovered {
				UI_PARENT_SCOPED(ui_overlay("###tmp"))

				ui_menu_button("Undo")
				ui_menu_button("Redo")
				//ui_menu_button("")
				ui_menu_button("Cut")
				ui_menu_button("Copy")
			}
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
