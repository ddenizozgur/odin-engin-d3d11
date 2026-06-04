package r

ui_label :: proc(text: string) -> UI_Action {
	return ui_build_widget(text, {.HasText}, UI_Size_TextContent{})
}

ui_button :: proc(text: string) -> UI_Action {
	return ui_build_widget(text, {.HasText, .HasBg, .HasBorder, .Clickable}, UI_Size_TextContent{})
}

ui_menu_button :: proc(text: string) -> UI_Action {
	return ui_build_widget(text, {.HasText, .HasHoverBg, .Clickable}, UI_Size_TextContent{})
}

ui_menu_item :: proc(text: string) -> UI_Action {
	return ui_build_widget(
		text,
		{.HasText, .HasHoverBg, .Clickable, .FillParent},
		UI_Size_TextContent{},
	)
}

ui_panel :: proc(
	text: string,
	layout_axis := UI_Axis.Vertical,
	box_flags: UI_Box_Flags = {.HasBg, .HasBorder},
	bucket_flags: UI_Bucket_Flags = {.HasPadding},
	pref_size: [2]UI_BucketSize = UI_Size_ChildrenSum{},
) -> UI_Action {
	return ui_build_bucket(text, box_flags, bucket_flags, pref_size, layout_axis)
}

ui_row :: proc(
	text: string,
	box_flags: UI_Box_Flags = {},
	bucket_flags: UI_Bucket_Flags = {},
	pref_size: [2]UI_BucketSize = UI_Size_ChildrenSum{},
) -> UI_Action {
	return ui_build_bucket(text, box_flags, bucket_flags, pref_size, .Horizontal)
}

ui_overlay_panel :: proc(
	text: string,
	layout_axis := UI_Axis.Vertical,
	box_flags: UI_Box_Flags = {.HasBg, .HasBorder},
	bucket_flags: UI_Bucket_Flags = {.Overlay, .HasPadding},
	pref_size: [2]UI_BucketSize = UI_Size_ChildrenSum{},
) -> UI_Action {
	return ui_build_bucket(text, box_flags, bucket_flags, pref_size, layout_axis)
}

ui_to_test :: proc() {
	UI_FRAME_SCOPED()

	{
		UI_PARENT_SCOPED(ui_panel("laloli").box)

		{
			UI_PARENT_SCOPED(ui_row("###menu_bar", {.HasBg, .HasBorder}, {.HasPadding}).box)
			ui_menu_button("File")
			ui_menu_button("Edit")
			ui_menu_button("View")
		}

		{
			UI_PARENT_SCOPED(ui_row("###content", {}, {.HasPadding}).box)

			{
				UI_PARENT_SCOPED(ui_panel("###left_panel").box)
				ui_label("Widgets")

				button := ui_button("Button")
				if button.hovered {
					ui_label("Hovered")
				}

				ui_build_widget(
					"Fill parent",
					{.HasText, .HasBg, .HasBorder, .Clickable, .FillParent},
					UI_Size_TextContent{},
				)
			}

			{
				UI_PARENT_SCOPED(ui_panel("###right_panel").box)
				ui_label("Buckets")

				{
					UI_PARENT_SCOPED(ui_row("###button_row", {}, {.HasPadding}).box)
					ui_button("One")
					ui_button("Two")
					ui_button("Three")
				}

				{
					UI_PARENT_SCOPED(ui_panel("###overlay_anchor").box)
					ui_label("Overlay anchor")

					{
						UI_PARENT_SCOPED(ui_overlay_panel("###overlay").box)
						ui_menu_item("Overlay A")
						ui_menu_item("Overlay B")
						ui_menu_item("Overlay C")
					}
				}
			}
		}
	}
}
