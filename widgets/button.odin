package widgets

import ui "../ui"

// ButtonStyle is the button's visual. It composes the common WidgetStyle, so a button can
// override any shared field and add its own when it needs one.
ButtonStyle :: struct {
	using common: WidgetStyle,
}

// Button declares a centered label in a styled box and returns whether it was activated this
// frame. A nil Style uses the theme's button style.
Button :: proc(
	Text:     string,
	Width:    ui.Sizing = {},
	Height:   ui.Sizing = {},
	Style:    ^ButtonStyle = nil,
	Disabled: bool = false,
	loc := #caller_location,
) -> bool {
	style := Style if Style != nil else &theme.Button

	if widget_box({Width = Width, Height = Height, Pad = style.Pad, Justify = .Center, Align = .Center}, Disabled, loc = loc) {
		element := ui.LastId()
		state := widget_state(element, Disabled)
		ui.SetStyle(element, widget_style(&style.common, state, ui.Focused(element)))
		widget_cursor(element, Disabled)

		ui.Label(Text, {Hit = .Ignore}, {Color = style.Text[state], Size = style.FontSize, Font = style.Font})

		return !Disabled && ui.Activated(element)
	}
	return false
}
