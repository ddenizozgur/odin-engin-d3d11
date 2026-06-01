package r

ui_button :: proc(text: string) -> UI_Action {
	_, action := ui_build_widget(
		text,
		{.HasText, .HasBg, .FillWidth, .Clickable},
		UI_SizePerAxis_TextContent{},
	)
	return action
}

ui_panel :: proc(
	text: string,
	pref_size: [2]UI_SizePerAxis = UI_SizePerAxis_ChildrenSum{},
) -> ^UI_Widget {
	widget, action := ui_build_widget(text, {.HasBg, .HasBorder}, pref_size)
	return widget
}

ui_to_test :: proc() {
	UI_FRAME_SCOPED()

	{
		UI_PARENT_SCOPED(ui_panel("###panel"))

		if ui_button("Kralsin").hovered {
			ui_button("Kralsin2")
			ui_button("Kralsin3")
		}

		{
			UI_PARENT_SCOPED(
				ui_panel(
					"###panel2",
					{UI_SizePerAxis_HardCoded(400), UI_SizePerAxis_ChildrenSum{}},
				),
			)

			ui_button("Kralsin4")
			ui_button("Kralsin5")
			ui_button("Kralsin6")
			ui_button("Kralsin7")
			ui_button("Kralsin8")
			ui_button("Kralsin9")
		}
	}
}
