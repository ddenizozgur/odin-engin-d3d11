package r

ui_to_test :: proc() {
	UI_FRAME_SCOPED()

	{
		UI_PARENT_SCOPED(ui_panel("###demo", layout_axis = .Horizontal).box)

		{
			UI_PARENT_SCOPED(ui_panel("###file", flags = {}).box)

			if ui_menu_button("File").hovered {
				UI_PARENT_SCOPED(ui_panel("###tmp", bucket_flags = {.Overlay}).box)

				ui_menu_button("New File")
				ui_menu_button("Open File")
			}
		}

		{
			UI_PARENT_SCOPED(ui_panel("###edit", flags = {}).box)

			if ui_menu_button("Edit").hovered {
				UI_PARENT_SCOPED(ui_panel("###tmp", bucket_flags = {.Overlay}).box)

				ui_menu_button("Cursor")
				ui_menu_button("Mekanize")
			}
		}

		{
			UI_PARENT_SCOPED(ui_panel("###hidden", flags = {}).box)

			if ui_menu_button("HarlyBarluy").hovered {
				UI_PARENT_SCOPED(ui_panel("###tmp", bucket_flags = {.Overlay}).box)

				ui_menu_button("Falan")
				ui_menu_button("Felan")
			}
		}

		ui_button("Pain")
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
