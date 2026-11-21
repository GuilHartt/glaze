package widgets

import "core:unicode/utf8"
import ui "../ui"

// TextEdit draws the UTF-8 buffer `Text` as a multi-line editor, reporting a change and a submit.
// The text wraps, or scrolls horizontally when `Wrap` is off, through the layout system, which owns
// the offset and the bars. Enter opens a new line, Ctrl+Enter submits, and Escape reverts.
TextEdit :: proc(
	Text:        ^[dynamic]u8,
	Width:       ui.Sizing = {Kind = .Fixed, Grow = 1, Shrink = 1},
	Height:      ui.Sizing = {},
	Placeholder: string = "",
	MaxChars:    int = 0,
	Filter:      CharFilter = nil,
	ReadOnly:    bool = false,
	Wrap:        bool = false,
	Style:       ^TextStyle = nil,
	Disabled:    bool = false,
	loc := #caller_location,
) -> (changed, submitted: bool) {
	// The bar sits this far from the box edge, since the layout adds its strip on top of the pad.
	BAR_EDGE :: f32(4)

	// A box with no Height takes this many rows.
	DEFAULT_ROWS :: 4

	style := Style if Style != nil else &theme.TextField
	lh := line_height(style.Font, style.FontSize)
	wrap := ui.WrapMode.Word if Wrap else .None

	height := Height
	if height == {} do height = ui.Fixed(field_height(style, DEFAULT_ROWS))

	if widget_box({
		Width  = Width,
		Height = height,
		Pad    = {Left = style.Pad.Left, Right = BAR_EDGE, Top = style.Pad.Top, Bottom = style.Pad.Bottom},
		Scroll = {Vertical = .Reserve, Horizontal = .Auto},
	}, Disabled, .Column, loc) {
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

		// The view the layout gave the text last frame, already inside the padding, the border and
		// the strips of the bars that scroll.
		view := ui.InnerRect(element)
		block, lines := text_edit_lines(Text^[:], edit, view.w, style.Font, style.FontSize, wrap)

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
			changed, submitted = text_edit_keys(Text, edit, lines, view, style.Font, style.FontSize, {
				MaxChars = MaxChars, Filter = Filter, ReadOnly = ReadOnly,
			})
			if changed do block, lines = text_edit_lines(Text^[:], edit, view.w, style.Font, style.FontSize, wrap)

			// A press that lands on a bar strip belongs to the layout, not to the caret.
			if ui.MousePressed(.Left) do edit.Selecting = ui.Pressed(element) && over_text(view, ui.MousePos(), !Wrap)
			if ui.Pressed(element) && edit.Selecting {
				offset := ui.ScrollOffset(element)
				if ui.MouseDown(.Left) && !ui.MousePressed(.Left) do offset = autoscroll(element, offset, view, block, lh)

				// The drag maps inside the view, so the caret stays on the edge line while the
				// view scrolls under the pointer.
				local := ui.MousePos() - ui.Vec2{view.x, view.y}
				local.x = clamp(local.x, 0, max(view.w - 1, 0))
				local.y = clamp(local.y, 0, max(view.h - 1, 0))

				at := offset_at(string(Text^[:]), lines, local + offset, style.Font, style.FontSize, lh)
				move_caret(edit, at, !ui.MousePressed(.Left) || ui.ModifierDown(.Shift))
				edit.Blink = 0
			}

			if ui.DoubleClicked(element) && edit.Selecting {
				edit.Anchor, edit.Caret = word_span(Text^[:], edit.Caret)
				edit.Blink = 0
			}

			// The view follows the caret only when the caret moved, so the wheel can take it away,
			// and never while the pointer owns the caret, or the pointer would map further down on
			// every frame.
			dragging := edit.Selecting && ui.MouseDown(.Left)
			moved := changed || edit.Caret != caret_before || edit.Anchor != anchor_before
			if !dragging && (moved || first) {
				caret := caret_point(string(Text^[:]), lines, edit.Caret, style.Font, style.FontSize, lh)
				scroll_to_caret(element, caret, {1, lh}, {view.w, view.h})
			}
		} else {
			edit.Blink = 0
			edit.Active = false
			edit.Selecting = false
		}

		visual := TextEditVisual{
			Lines            = lines,
			Text             = string(Text^[:]),
			Caret            = edit.Caret,
			Anchor           = edit.Anchor,
			View             = view,
			Font             = style.Font,
			Size             = style.FontSize,
			Color            = style.Text[state],
			CaretColor       = style.Caret,
			SelectColor      = style.Selection,
			Placeholder      = Placeholder,
			PlaceholderColor = style.Placeholder,
			CaretOn          = focused && edit.Blink < 0.5,
		}

		ui.Custom(draw_text_edit, {Width = ui.Fixed(content_width(block.x, view.w)), Height = ui.Fixed(block.y), Hit = .Ignore}, {}, visual)
		return changed, submitted
	}
	return false, false
}

// TextEditVisual is everything the paint callback needs, copied into the frame so it can hold a
// view of the lines and of the text.
@(private="file")
TextEditVisual :: struct {
	Lines:            []ui.Line,
	Text:             string,
	Caret:            int,
	Anchor:           int,
	View:             ui.Rect,
	Font:             ui.Font,
	Size:             f32,
	Color:            ui.Color,
	CaretColor:       ui.Color,
	SelectColor:      ui.Color,
	Placeholder:      string,
	PlaceholderColor: ui.Color,
	CaretOn:          bool,
}

// text_edit_lines returns the lines `Text` wraps into at `Width` in `Mode`, rebuilding the cache in
// `State` only when the text or the geometry changed.
@(private="file")
text_edit_lines :: proc(Text: []u8, State: ^text_state, Width: f32, Font: ui.Font, Size: f32, Mode: ui.WrapMode) -> (block: ui.Vec2, lines: []ui.Line) {
	if State.Width != Width || State.Font != Font || State.Size != Size || State.Wrap != Mode ||
	   string(State.Source[:]) != string(Text) {
		clear(&State.Source)
		append(&State.Source, ..Text)
		State.Width, State.Font, State.Size, State.Wrap = Width, Font, Size, Mode

		wrapped := ui.WrapText(string(Text), Font, Size, Mode, Width)
		if len(wrapped) == 0 do wrapped = empty_lines[:]

		clear(&State.Lines)
		append(&State.Lines, ..wrapped)
		State.Block = content_size(State.Lines[:], line_height(Font, Size))
	}
	return State.Block, State.Lines[:]
}

// content_size returns the size the block of `Lines` takes, in layout units.
@(private="file")
content_size :: proc(Lines: []ui.Line, LineHeight: f32) -> ui.Vec2 {
	width: f32
	for line in Lines do width = max(width, line.Width)
	return {width, f32(len(Lines)) * LineHeight}
}

// over_text reports whether `Pos` can move the caret: anywhere in the box, away from the bar
// strips, so a press that starts a bar drag leaves the caret alone. `Horizontal` says whether the
// bottom strip is there to skip.
@(private="file")
over_text :: proc(View: ui.Rect, Pos: ui.Vec2, Horizontal: bool) -> bool {
	if View.w <= 0 || View.h <= 0 do return false
	return Pos.x < View.x + View.w && (!Horizontal || Pos.y < View.y + View.h)
}

// text_edit_keys applies the editing keys a focused multi-line editor takes and reports a change
// and a submit.
@(private="file")
text_edit_keys :: proc(
	Text:  ^[dynamic]u8,
	State: ^text_state,
	Lines: []ui.Line,
	View:  ui.Rect,
	Font:  ui.Font,
	Size:  f32,
	Keys:  TextKeys,
) -> (changed, submitted: bool) {
	caret, anchor := State.Caret, State.Anchor
	shift := ui.ModifierDown(.Shift)
	lh := line_height(Font, Size)

	if (ui.ModifierDown(.Ctrl) || ui.ModifierDown(.Super)) && !ui.ModifierDown(.Alt) {
		switch {
		case ui.KeyPressed(.A):
			State.Anchor, State.Caret = 0, len(Text)
		case ui.KeyPressed(.C):
			copy_selection(Text^[:], State)
		case ui.KeyPressed(.X):
			if !Keys.ReadOnly && copy_selection(Text^[:], State) do changed = erase(Text, State, .RuneBack)
		case ui.KeyPressed(.V):
			if !Keys.ReadOnly do changed = insert_text(Text, State, input_text(ui.GetClipboard(), Keys), Keys.MaxChars)
		case ui.KeyPressed(.Backspace, true):
			if !Keys.ReadOnly do changed = erase(Text, State, .WordBack)
		case ui.KeyPressed(.Delete, true):
			if !Keys.ReadOnly do changed = erase(Text, State, .WordForward)
		case ui.KeyPressed(.Left, true):
			step_caret(Text^[:], State, .WordBack, shift)
		case ui.KeyPressed(.Right, true):
			step_caret(Text^[:], State, .WordForward, shift)
		case ui.KeyPressed(.Home):
			move_caret(State, 0, shift)
		case ui.KeyPressed(.End):
			move_caret(State, len(Text), shift)
		case ui.KeyPressed(.Enter):
			submitted = true
			State.Active = false
			ui.ClearFocus()
		}
	} else {
		line := Lines[line_at(Lines, State.Caret)]
		page := max(int(View.h / lh) - 1, 1)
		switch {
		case ui.KeyPressed(.Left, true):
			step_caret(Text^[:], State, .RuneBack, shift)
		case ui.KeyPressed(.Right, true):
			step_caret(Text^[:], State, .RuneForward, shift)
		case ui.KeyPressed(.Up, true):
			move_line(string(Text^[:]), Lines, State, -1, shift, Font, Size)
		case ui.KeyPressed(.Down, true):
			move_line(string(Text^[:]), Lines, State, 1, shift, Font, Size)
		case ui.KeyPressed(.PageUp, true):
			move_line(string(Text^[:]), Lines, State, -page, shift, Font, Size)
		case ui.KeyPressed(.PageDown, true):
			move_line(string(Text^[:]), Lines, State, page, shift, Font, Size)
		case ui.KeyPressed(.Home):
			move_caret(State, int(line.Start), shift)
		case ui.KeyPressed(.End):
			move_caret(State, int(line.End), shift)
		case ui.KeyPressed(.Backspace, true):
			if !Keys.ReadOnly do changed = erase(Text, State, .RuneBack)
		case ui.KeyPressed(.Delete, true):
			if !Keys.ReadOnly do changed = erase(Text, State, .RuneForward)
		case ui.KeyPressed(.Enter):
			changed = insert_text(Text, State, "\n", Keys.MaxChars)
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
			changed = insert_text(Text, State, input_text(typed, Keys), Keys.MaxChars) || changed
		}
	}

	if changed || State.Caret != caret || State.Anchor != anchor do State.Blink = 0
	return changed, submitted
}

// draw_text_edit paints the visible lines, the selection, the caret and the placeholder.
@(private="file")
draw_text_edit :: proc(Rect: ui.Rect, Element: ui.ElementId, User: rawptr) {
	visual := (^TextEditVisual)(User)
	lh := line_height(visual.Font, visual.Size)
	if lh <= 0 do return

	first, last := 0, len(visual.Lines)
	if visual.View.h > 0 {
		first = clamp(int((visual.View.y - Rect.y) / lh), 0, len(visual.Lines))
		last = clamp(int((visual.View.y + visual.View.h - Rect.y) / lh) + 1, first, len(visual.Lines))
	}

	if len(visual.Text) == 0 {
		if len(visual.Placeholder) > 0 {
			ui.AddText({Rect.x, Rect.y}, visual.Placeholder, visual.PlaceholderColor, visual.Font, visual.Size)
		}
	} else {
		start := clamp(min(visual.Anchor, visual.Caret), 0, len(visual.Text))
		end := clamp(max(visual.Anchor, visual.Caret), 0, len(visual.Text))

		if start != end {
			// The selection is a solid block, so its lines must not feather into each other.
			ui.PushAntialias(false)
			for i in first ..< last {
				line := visual.Lines[i]
				from := max(int(line.Start), start)
				to := min(int(line.End), end)
				if from >= to do continue

				x0 := Rect.x + ui.MeasureText(visual.Text[int(line.Start):from], visual.Font, visual.Size).x
				x1 := Rect.x + ui.MeasureText(visual.Text[int(line.Start):to], visual.Font, visual.Size).x
				ui.AddRectFilled({x0, Rect.y + f32(i) * lh, x1 - x0, lh}, visual.SelectColor)
			}
		}

		for i in first ..< last {
			line := visual.Lines[i]
			ui.AddText({Rect.x, Rect.y + f32(i) * lh}, visual.Text[line.Start:line.End], visual.Color, visual.Font, visual.Size)
		}
	}

	if visual.CaretOn {
		caret := caret_point(visual.Text, visual.Lines, visual.Caret, visual.Font, visual.Size, lh)
		ui.PushAntialias(false)
		ui.AddRectFilled({Rect.x + caret.x, Rect.y + caret.y, 1, lh}, visual.CaretColor)
		ui.PopAntialias()
	}
}
