package widgets

import "core:unicode/utf8"
import ui "../ui"

// TextInput draws the UTF-8 buffer `Text` as a single-line field, reporting a change and a submit.
// Enter submits and blurs, Escape reverts, and `Mask` draws a rune per rune.
TextInput :: proc(
	Text:        ^[dynamic]u8,
	Width:       ui.Sizing = {Kind = .Fixed, Grow = 1, Shrink = 1},
	Height:      ui.Sizing = {},
	Placeholder: string = "",
	MaxChars:    int = 0,
	Filter:      CharFilter = nil,
	ReadOnly:    bool = false,
	Mask:        rune = 0,
	Style:       ^TextStyle = nil,
	Disabled:    bool = false,
	loc := #caller_location,
) -> (changed, submitted: bool) {
	style := Style if Style != nil else &theme.TextField
	lh := line_height(style.Font, style.FontSize)

	height := Height
	if height == {} do height = ui.Fixed(field_height(style, 1))

	if widget_box({Width = Width, Height = height, Pad = style.Pad, Scroll = {Horizontal = .Never}}, Disabled, loc = loc) {
		element := ui.LastId()
		state := widget_state(element, Disabled, Pressed = false)
		ui.SetStyle(element, widget_style(&style.common, state, ui.Focused(element)))
		widget_cursor(element, Disabled, .IBeam)

		edit := ui.Storage(element, text_state, destroy_text_state)
		focused := !Disabled && ui.Focused(element)

		if MaxChars > 0 && utf8.rune_count(Text^[:]) > MaxChars {
			resize(Text, len(rune_prefix(string(Text^[:]), MaxChars)))
		}
		edit.Caret = clamp(edit.Caret, 0, len(Text))
		edit.Anchor = clamp(edit.Anchor, 0, len(Text))

		display, mask_size := mask_display(Text^[:], Mask, edit)
		lines := text_lines(display, style.Font, style.FontSize)
		block := ui.Vec2{lines[0].Width, 0}
		view := ui.InnerRect(element)

		if focused {
			first := !edit.Active
			if first {
				clear(&edit.Original)
				append(&edit.Original, ..Text^[:])
				edit.Active = true
			}

			edit.Blink += ui.DeltaTime()
			if edit.Blink >= 1 do edit.Blink -= 1

			caret_before, anchor_before := edit.Caret, edit.Anchor
			changed, submitted = text_input_keys(Text, edit, {MaxChars = MaxChars, Filter = Filter, ReadOnly = ReadOnly, Mask = Mask})
			if changed {
				display, mask_size = mask_display(Text^[:], Mask, edit)
				lines = text_lines(display, style.Font, style.FontSize)
				block.x = lines[0].Width
			}

			offset := ui.ScrollOffset(element)
			if ui.MousePressed(.Left) do edit.Selecting = ui.Pressed(element)
			if ui.Pressed(element) && edit.Selecting && view.w > 0 && view.h > 0 {
				if ui.MouseDown(.Left) && !ui.MousePressed(.Left) do offset = autoscroll(element, offset, view, block)
				at := offset_at(display, lines, ui.MousePos() - ui.Vec2{view.x, view.y} + offset, style.Font, style.FontSize, lh)
				if mask_size > 0 do at = len(rune_prefix(string(Text^[:]), at / mask_size))
				move_caret(edit, at, !ui.MousePressed(.Left) || ui.ModifierDown(.Shift))
				edit.Blink = 0
			}

			if ui.DoubleClicked(element) {
				edit.Anchor, edit.Caret = word_span(Text^[:], edit.Caret)
				edit.Blink = 0
			}

			// The view follows the caret only when the caret moved, so the wheel can take it away,
			// and never while the pointer owns the caret, or the pointer would map further away on
			// every frame.
			dragging := edit.Selecting && ui.MouseDown(.Left)
			moved := changed || edit.Caret != caret_before || edit.Anchor != anchor_before
			if !dragging && (moved || first) {
				caret := ui.MeasureText(display[:display_at(Text^[:], edit.Caret, mask_size)], style.Font, style.FontSize).x
				scroll_to_caret(element, {caret, 0}, {1, 0}, {view.w, 0})
			}
		} else {
			edit.Blink = 0
			edit.Active = false
			edit.Selecting = false
		}

		visual := TextInputVisual{
			Text             = display,
			Caret            = display_at(Text^[:], edit.Caret, mask_size),
			Anchor           = display_at(Text^[:], edit.Anchor, mask_size),
			Font             = style.Font,
			Size             = style.FontSize,
			Color            = style.Text[state],
			CaretColor       = style.Caret,
			SelectColor      = style.Selection,
			Placeholder      = Placeholder,
			PlaceholderColor = style.Placeholder,
			CaretOn          = focused && edit.Blink < 0.5,
		}

		ui.Custom(draw_text_input, {Width = ui.Fixed(content_width(block.x, view.w)), Height = ui.Fill(), Hit = .Ignore}, {}, visual)
		return changed, submitted
	}
	return false, false
}

// TextInputVisual is everything the paint callback needs, copied into the frame so it can hold a
// view of the text.
@(private="file")
TextInputVisual :: struct {
	Text:             string,
	Caret:            int,
	Anchor:           int,
	Font:             ui.Font,
	Size:             f32,
	Color:            ui.Color,
	CaretColor:       ui.Color,
	SelectColor:      ui.Color,
	Placeholder:      string,
	PlaceholderColor: ui.Color,
	CaretOn:          bool,
}

// text_lines breaks `Text` at its newlines, measuring each line with `Font` at `Size`.
@(private="file")
text_lines :: proc(Text: string, Font: ui.Font, Size: f32) -> []ui.Line {
	lines := ui.WrapText(Text, Font, Size, .None, 0)
	if len(lines) == 0 do return empty_lines[:]
	return lines
}

// mask_display returns `Text` as it is drawn: itself, or one `Mask` rune per rune of it, with the
// size of one mask rune. The masked text is kept in `State`, so it outlives the call.
@(private="file")
mask_display :: proc(Text: []u8, Mask: rune, State: ^text_state) -> (string, int) {
	if Mask == 0 do return string(Text), 0

	bytes, size := utf8.encode_rune(Mask)
	clear(&State.Display)
	for _ in string(Text) do append(&State.Display, ..bytes[:size])
	return string(State.Display[:]), size
}

// display_at maps a text offset to its offset in the masked text.
@(private="file")
display_at :: proc(Text: []u8, At, MaskSize: int) -> int {
	if MaskSize == 0 do return At
	return utf8.rune_count(Text[:clamp(At, 0, len(Text))]) * MaskSize
}

// text_input_keys applies the editing keys a focused single-line field takes and reports a change
// and a submit.
@(private="file")
text_input_keys :: proc(Text: ^[dynamic]u8, State: ^text_state, Keys: TextKeys) -> (changed, submitted: bool) {
	caret, anchor := State.Caret, State.Anchor
	buffer := Text^[:]
	shift := ui.ModifierDown(.Shift)

	if (ui.ModifierDown(.Ctrl) || ui.ModifierDown(.Super)) && !ui.ModifierDown(.Alt) {
		switch {
		case ui.KeyPressed(.A):
			State.Anchor, State.Caret = 0, len(buffer)
		case ui.KeyPressed(.C):
			if Keys.Mask == 0 do copy_selection(buffer, State)
		case ui.KeyPressed(.X):
			if !Keys.ReadOnly && Keys.Mask == 0 && copy_selection(buffer, State) do changed = erase(Text, State, .RuneBack)
		case ui.KeyPressed(.V):
			if !Keys.ReadOnly do changed = insert_text(Text, State, line_text(ui.GetClipboard(), Keys), Keys.MaxChars)
		case ui.KeyPressed(.Backspace, true):
			if !Keys.ReadOnly do changed = erase(Text, State, .WordBack)
		case ui.KeyPressed(.Delete, true):
			if !Keys.ReadOnly do changed = erase(Text, State, .WordForward)
		case ui.KeyPressed(.Left, true):
			step_caret(buffer, State, .WordBack, shift)
		case ui.KeyPressed(.Right, true):
			step_caret(buffer, State, .WordForward, shift)
		case ui.KeyPressed(.Home):
			move_caret(State, 0, shift)
		case ui.KeyPressed(.End):
			move_caret(State, len(buffer), shift)
		case ui.KeyPressed(.Enter):
			submitted = true
			State.Active = false
			ui.ClearFocus()
		}
	} else {
		switch {
		case ui.KeyPressed(.Left, true):  step_caret(buffer, State, .RuneBack, shift)
		case ui.KeyPressed(.Right, true): step_caret(buffer, State, .RuneForward, shift)
		case ui.KeyPressed(.Home): move_caret(State, 0, shift)
		case ui.KeyPressed(.End):  move_caret(State, len(buffer), shift)
		case ui.KeyPressed(.Backspace, true):
			if !Keys.ReadOnly do changed = erase(Text, State, .RuneBack)
		case ui.KeyPressed(.Delete, true):
			if !Keys.ReadOnly do changed = erase(Text, State, .RuneForward)
		case ui.KeyPressed(.Enter):
			submitted = true
			State.Active = false
			ui.ClearFocus()
		case ui.KeyPressed(.Escape):
			if !Keys.ReadOnly && string(Text^[:]) != string(State.Original[:]) {
				clear(Text)
				append(Text, ..State.Original[:])
				State.Caret, State.Anchor = len(Text^), len(Text^)
				State.Want = -1
				changed = true
			}
			State.Active = false
			ui.ClearFocus()
		}

		if typed := ui.TextInput(); !Keys.ReadOnly && len(typed) > 0 {
			changed = insert_text(Text, State, line_text(typed, Keys), Keys.MaxChars) || changed
		}
	}

	if changed || State.Caret != caret || State.Anchor != anchor do State.Blink = 0
	return changed, submitted
}

// draw_text_input paints the line, the selection, the caret and the placeholder inside the box.
@(private="file")
draw_text_input :: proc(Rect: ui.Rect, Element: ui.ElementId, User: rawptr) {
	visual := (^TextInputVisual)(User)
	height := line_height(visual.Font, visual.Size)
	top := Rect.y + max((Rect.h - height) / 2, 0)

	start := clamp(min(visual.Anchor, visual.Caret), 0, len(visual.Text))
	end := clamp(max(visual.Anchor, visual.Caret), 0, len(visual.Text))
	if start != end {
		x0 := Rect.x + ui.MeasureText(visual.Text[:start], visual.Font, visual.Size).x
		x1 := Rect.x + ui.MeasureText(visual.Text[:end], visual.Font, visual.Size).x
		ui.AddRectFilled({x0, top, x1 - x0, height}, visual.SelectColor)
	}

	run, tint := visual.Text, visual.Color
	if len(run) == 0 {
		run, tint = visual.Placeholder, visual.PlaceholderColor
	}
	ui.AddText({Rect.x, top}, run, tint, visual.Font, visual.Size)

	if visual.CaretOn {
		caret := Rect.x + ui.MeasureText(visual.Text[:clamp(visual.Caret, 0, len(visual.Text))], visual.Font, visual.Size).x
		ui.PushAntialias(false)
		ui.AddRectFilled({caret, top, 1, height}, visual.CaretColor)
		ui.PopAntialias()
	}
}
