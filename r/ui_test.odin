package r

import "core:flags"
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
ui_row :: proc(id: string) -> ^UI_Box {
	return ui_panel(id, flags = {}, layout_axis = .Vertical).box
}
ui_overlay :: proc(id: string, layout_axis := UI_Axis.Vertical) -> ^UI_Box {
	return ui_panel(id, bucket_flags = {.Overlay}, layout_axis = layout_axis).box
}

ui_to_test :: proc() {
	UI_FRAME_SCOPED()

	{
		UI_PARENT_SCOPED(ui_panel("###menu", layout_axis = .Horizontal).box)

		ui_label("Kralsın")
		{
			UI_PARENT_SCOPED(ui_row("###file_menu"))

			if ui_menu_button("File").hovered {
				UI_PARENT_SCOPED(ui_overlay("###tmp"))

				ui_menu_button("Baba tilifon")
				ui_menu_button("Hannamuho")
			}
		}
		{
			UI_PARENT_SCOPED(ui_row("###file_menu"))

			if ui_menu_button("View").hovered {
				UI_PARENT_SCOPED(ui_overlay("###tmp"))

				ui_menu_button("Baba tilifon vs john")
				ui_menu_button("kelalaka")
			}
		}
		ui_menu_button("Tools")
		ui_menu_button("Help")
	}
}
