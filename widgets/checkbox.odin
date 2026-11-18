package widgets

import ui "../ui"

// CheckboxStyle is the checkbox's visual: the shared WidgetStyle for its box and label, plus the
// check color, the box size, and the gap between the box and the label.
CheckboxStyle :: struct {
	using common: WidgetStyle,
	Check:        [WidgetState]ui.Color,
	Box:          f32,
	Gap:          f32,
}

// Checkbox toggles the bool `Checked` points to and returns whether it changed this frame.
Checkbox :: proc(Text: cstring, Checked: ^bool, Width: ui.Sizing = {}, Height: ui.Sizing = {}, Style: ^CheckboxStyle = nil, Disabled: bool = false) -> bool {
	style := Style if Style != nil else &theme.Checkbox

	if ui.Row({
		Width     = Width,
		Height    = Height,
		Pad       = style.Pad,
		Gap       = style.Gap,
		Justify   = .Start,
		Align     = .Center,
		Hit       = .Ignore if Disabled else .Stop,
		Focusable = !Disabled,
	}) {
		element := ui.LastId()
		changed := !Disabled && ui.Activated(element)
		if changed do Checked^ = !Checked^

		state := widget_state(element, Disabled)

		box := CheckboxBox{Check = style.Check[state], Size = style.Box, Checked = Checked^}
		ui.Custom(
			draw_checkbox,
			Config = {Width = ui.Fixed(style.Box), Height = ui.Fixed(style.Box), Hit = .Pass},
			Style  = widget_style(&style.common, state, ui.Focused(element)),
			User   = box,
		)
		ui.Label(Text, {Hit = .Ignore}, {Color = style.Text[state], Size = style.FontSize, Font = style.Font})

		widget_cursor(element, Disabled)
		return changed
	}
	return false
}

// CheckboxBox is what the box callback paints: the check color and the box size, both resolved
// where the checkbox was declared, and whether the box is checked. The values are copied, since
// the caller's style may be a local that is gone by the time the callback runs.
@(private="file")
CheckboxBox :: struct {
	Check:   ui.Color,
	Size:    f32,
	Checked: bool,
}

// draw_checkbox paints the check inside a box the node already filled and outlined.
@(private="file")
draw_checkbox :: proc(Rect: ui.Rect, List: ^ui.DrawList, Element: ui.ElementId, User: rawptr) {
	box := (^CheckboxBox)(User)
	if !box.Checked do return

	points := [3]ui.Vec2{
		{Rect.x + Rect.w * 0.24, Rect.y + Rect.h * 0.52},
		{Rect.x + Rect.w * 0.43, Rect.y + Rect.h * 0.72},
		{Rect.x + Rect.w * 0.76, Rect.y + Rect.h * 0.30},
	}
	ui.AddPolygonStroke(List, points[:], box.Check, box.Size * 0.12, Closed = false)
}
