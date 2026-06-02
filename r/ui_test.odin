package r

ui_button :: proc(text: string) -> UI_Action {
	_, action := ui_build_widget(
		text,
		{.HasText, .HasBg, .Clickable},
		UI_SizePerAxis_TextContent{},
	)
	return action
}
ui_menu_button :: proc(text: string) -> UI_Action {
	_, action := ui_build_widget(
		text,
		{.HasText, .HasHoverBg, .FillParent, .Clickable},
		UI_SizePerAxis_TextContent{},
	)
	return action
}

ui_panel_with_action :: proc(
	text: string,
	pref_size: [2]UI_SizePerAxis = UI_SizePerAxis_ChildrenSum{},
	layout_axis := UI_Axis.Vert,
) -> (
	^UI_Widget,
	UI_Action,
) {
	return ui_build_widget(text, {.HasBg, .HasBorder}, pref_size, layout_axis)
}
ui_panel :: proc(
	text: string,
	pref_size: [2]UI_SizePerAxis = UI_SizePerAxis_ChildrenSum{},
	layout_axis := UI_Axis.Vert,
) -> UI_Action {
	_, action := ui_build_widget(text, {.HasBg, .HasBorder}, pref_size, layout_axis)
	return action
}

ui_label :: proc(text: string) {
	ui_build_widget(text, {.HasText}, UI_SizePerAxis_TextContent{})
}

ui_to_test :: proc() {
	UI_FRAME_SCOPED()


}
