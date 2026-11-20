package widgets

import "core:unicode"
import "core:unicode/utf8"
import ui "../ui"

// TextInputStyle is the text input's box and text, plus the color of the caret, the selection
// and the placeholder.
TextInputStyle :: struct {
	using common: WidgetStyle,
	Caret:        ui.Color,
	Selection:    ui.Color,
	Placeholder:  ui.Color,
}

// CharFilter screens a rune that typing or pasting puts in the buffer: the returned rune replaces
// it, and false drops it.
CharFilter :: #type proc(Rune: rune) -> (rune, bool)

// FilterDigits keeps 0 through 9.
FilterDigits :: proc(Rune: rune) -> (rune, bool) {
	return Rune, Rune >= '0' && Rune <= '9'
}

// FilterDecimal keeps digits, the point and the two signs a number needs.
FilterDecimal :: proc(Rune: rune) -> (rune, bool) {
	return Rune, Rune >= '0' && Rune <= '9' || Rune == '.' || Rune == '+' || Rune == '-'
}

// FilterHexadecimal keeps digits and a through f, in either case.
FilterHexadecimal :: proc(Rune: rune) -> (rune, bool) {
	return Rune, Rune >= '0' && Rune <= '9' || Rune >= 'a' && Rune <= 'f' || Rune >= 'A' && Rune <= 'F'
}

// FilterUppercase maps every letter to upper case.
FilterUppercase :: proc(Rune: rune) -> (rune, bool) {
	return unicode.to_upper(Rune), true
}

// TextEdit is the editing state a TextInput keeps for one element: the caret and anchor as byte
// offsets, the scroll and blink the paint reads, and the text Escape reverts to.
@(private="file")
TextEdit :: struct {
	Caret:    int,
	Anchor:   int,
	Scroll:   f32,
	Blink:    f32,
	Active:   bool,
	Original: [dynamic]u8,
}

// TextInputVisual is everything the paint callback needs, copied into the frame so it can hold
// a view of the caller's text.
@(private="file")
TextInputVisual :: struct {
	Text:       string,
	Caret:      int,
	Anchor:     int,
	Scroll:     f32,
	Font:       ui.Font,
	Size:       f32,
	Color:      ui.Color,
	CaretColor: ui.Color,
	SelectColor: ui.Color,
	CaretOn:    bool,
}

// TextInput draws the UTF-8 buffer `Text` as a single-line field, reporting a change and a submit.
// Enter blurs, Escape reverts, and `MaxChars`, `Filter`, `ReadOnly` and `Mask` shape the field.
TextInput :: proc(
	Text:        ^[dynamic]u8,
	Width:       ui.Sizing = {Kind = .Fixed, Grow = 1, Shrink = 1},
	Height:      ui.Sizing = {},
	Placeholder: string = "",
	MaxChars:    int = 0,
	Filter:      CharFilter = nil,
	ReadOnly:    bool = false,
	Mask:        rune = 0,
	Style:       ^TextInputStyle = nil,
	Disabled:    bool = false,
) -> (changed, submitted: bool) {
	style := Style if Style != nil else &theme.TextInput

	height := Height
	if height == {} {
		line := ui.MeasureText("", style.Font, style.FontSize).y
		height = ui.Fixed(line + style.Pad.Top + style.Pad.Bottom + style.BorderWidth.Top + style.BorderWidth.Bottom)
	}

	if widget_box({Width = Width, Height = height, Pad = style.Pad, Clip = true}, Disabled) {
		element := ui.LastId()
		state := widget_state(element, Disabled)
		ui.SetStyle(element, widget_style(&style.common, state, ui.Focused(element)))
		widget_cursor(element, Disabled, .IBeam)

		edit := ui.Storage(element, TextEdit)
		focused := !Disabled && ui.Focused(element)
		buffer := Text^[:]

		if MaxChars > 0 && len(buffer) > MaxChars && utf8.rune_count(buffer) > MaxChars {
			resize(Text, len(rune_prefix(string(buffer), MaxChars)))
			buffer = Text^[:]
		}

		edit.Caret = clamp(edit.Caret, 0, len(buffer))
		edit.Anchor = clamp(edit.Anchor, 0, len(buffer))

		display, mask_size := mask_display(buffer, Mask)

		if focused {
			if !edit.Active {
				clear(&edit.Original)
				append(&edit.Original, ..buffer)
				edit.Active = true
			}

			edit.Blink += ui.DeltaTime()
			if edit.Blink >= 1 do edit.Blink -= 1
			changed, submitted = text_input_keys(Text, edit, MaxChars, Filter, ReadOnly, Mask)
			if changed {
				buffer = Text^[:]
				display, mask_size = mask_display(buffer, Mask)
			}

			rect := ui.ElementRect(element)
			inner_w := rect.w - style.Pad.Left - style.Pad.Right - style.BorderWidth.Left - style.BorderWidth.Right

			if ui.Pressed(element) && inner_w > 0 {
				inner_x := rect.x + style.Pad.Left + style.BorderWidth.Left
				at := index_at_x(display, ui.MousePos().x - inner_x + edit.Scroll, style.Font, style.FontSize)
				if mask_size > 0 do at = len(rune_prefix(string(buffer), at / mask_size))

				// Dragging keeps the anchor the press placed, so the pointer extends the selection.
				move_caret(edit, at, !ui.MousePressed(.Left) || ui.ModifierDown(.Shift))
				edit.Blink = 0
			}

			if ui.DoubleClicked(element) {
				edit.Anchor, edit.Caret = word_span(buffer, edit.Caret)
				edit.Blink = 0
			}

			scroll_to_caret(display, edit, display_at(buffer, edit.Caret, mask_size), inner_w, style.Font, style.FontSize)
		} else {
			edit.Blink = 0
			edit.Active = false
		}

		run, tint := display, style.Text[state]
		if len(buffer) == 0 && !focused {
			run, tint = Placeholder, style.Placeholder
		}

		visual := TextInputVisual{
			Text        = run,
			Caret       = display_at(buffer, edit.Caret, mask_size),
			Anchor      = display_at(buffer, edit.Anchor, mask_size),
			Scroll      = edit.Scroll,
			Font        = style.Font,
			Size        = style.FontSize,
			Color       = tint,
			CaretColor  = style.Caret,
			SelectColor = style.Selection,
			CaretOn     = focused && edit.Blink < 0.5,
		}

		ui.Custom(draw_text_input, {Width = ui.Fill(), Height = ui.Fill(), Hit = .Ignore}, {}, visual)

		return changed, submitted
	}
	return false, false
}

// text_input_keys applies the editing keys a focused text input takes and reports a change and a
// submit.
@(private="file")
text_input_keys :: proc(Text: ^[dynamic]u8, Edit: ^TextEdit, MaxChars: int, Filter: CharFilter, ReadOnly: bool, Mask: rune) -> (changed, submitted: bool) {
	caret, anchor := Edit.Caret, Edit.Anchor
	buffer := Text^[:]
	shift := ui.ModifierDown(.Shift)

	if (ui.ModifierDown(.Ctrl) || ui.ModifierDown(.Super)) && !ui.ModifierDown(.Alt) {
		switch {
		case ui.KeyPressed(.A):
			Edit.Anchor, Edit.Caret = 0, len(buffer)
		case ui.KeyPressed(.C):
			if Mask == 0 do copy_selection(buffer, Edit)
		case ui.KeyPressed(.X):
			if !ReadOnly && Mask == 0 && copy_selection(buffer, Edit) do changed = erase(Text, Edit, .RuneBack)
		case ui.KeyPressed(.V):
			if !ReadOnly do changed = insert_text(Text, Edit, filter_text(one_line(ui.GetClipboard()), Filter), MaxChars)
		case ui.KeyPressed(.Backspace, true):
			if !ReadOnly do changed = erase(Text, Edit, .WordBack)
		case ui.KeyPressed(.Delete, true):
			if !ReadOnly do changed = erase(Text, Edit, .WordForward)
		case ui.KeyPressed(.Left, true):
			step_caret(buffer, Edit, .WordBack, shift)
		case ui.KeyPressed(.Right, true):
			step_caret(buffer, Edit, .WordForward, shift)
		}
	} else {
		switch {
		case ui.KeyPressed(.Left, true):
			step_caret(buffer, Edit, .RuneBack, shift)
		case ui.KeyPressed(.Right, true):
			step_caret(buffer, Edit, .RuneForward, shift)
		case ui.KeyPressed(.Home):
			move_caret(Edit, 0, shift)
		case ui.KeyPressed(.End):
			move_caret(Edit, len(buffer), shift)
		case ui.KeyPressed(.Backspace, true):
			if !ReadOnly do changed = erase(Text, Edit, .RuneBack)
		case ui.KeyPressed(.Delete, true):
			if !ReadOnly do changed = erase(Text, Edit, .RuneForward)
		case ui.KeyPressed(.Enter):
			submitted = true
			Edit.Active = false
			ui.ClearFocus()
		case ui.KeyPressed(.Escape):
			if !ReadOnly && string(Text^[:]) != string(Edit.Original[:]) {
				clear(Text)
				append(Text, ..Edit.Original[:])
				Edit.Caret, Edit.Anchor = len(Text^), len(Text^)
				changed = true
			}
			Edit.Active = false
			ui.ClearFocus()
		}

		if typed := one_line(ui.TextInput()); !ReadOnly && len(typed) > 0 {
			changed = insert_text(Text, Edit, filter_text(typed, Filter), MaxChars) || changed
		}
	}

	if changed || Edit.Caret != caret || Edit.Anchor != anchor do Edit.Blink = 0
	return changed, submitted
}

// TextStep is one step through the buffer: a rune or a word, back or forward.
@(private="file")
TextStep :: enum u8 { RuneBack, RuneForward, WordBack, WordForward }

// step_caret moves the caret one `Step`, collapsing the selection to its edge when `Select`
// is off, so the move starts from there instead of stepping.
@(private="file")
step_caret :: proc(Text: []u8, Edit: ^TextEdit, Step: TextStep, Select: bool) {
	if !Select {
		if start, end := selection(Edit); start != end {
			back := Step == .RuneBack || Step == .WordBack
			move_caret(Edit, start if back else end, false)
			return
		}
	}

	switch Step {
	case .RuneBack:    move_caret(Edit, rune_before(Text, Edit.Caret), Select)
	case .RuneForward: move_caret(Edit, rune_after(Text, Edit.Caret), Select)
	case .WordBack:    move_caret(Edit, word_step(Text, Edit.Caret, false), Select)
	case .WordForward: move_caret(Edit, word_step(Text, Edit.Caret, true), Select)
	}
}

// one_line returns the part of `Text` before the first newline, since a TextInput is single-line.
@(private="file")
one_line :: proc(Text: string) -> string {
	for c, i in Text {
		if c == '\n' || c == '\r' do return Text[:i]
	}
	return Text
}

// selection returns the selected byte range, ordered so start <= end.
@(private="file")
selection :: proc(Edit: ^TextEdit) -> (start, end: int) {
	start = min(Edit.Anchor, Edit.Caret)
	end = max(Edit.Anchor, Edit.Caret)
	return
}

// move_caret places the caret at `At`, keeping the anchor when `Select` is set.
@(private="file")
move_caret :: proc(Edit: ^TextEdit, At: int, Select: bool) {
	if !Select do Edit.Anchor = At
	Edit.Caret = At
}

// rune_before returns the byte offset of the rune before `At`.
@(private="file")
rune_before :: proc(Text: []u8, At: int) -> int {
	if At <= 0 do return 0
	_, size := utf8.decode_last_rune(Text[:At])
	return At - max(size, 1)
}

// rune_after returns the byte offset of the rune after `At`.
@(private="file")
rune_after :: proc(Text: []u8, At: int) -> int {
	if At >= len(Text) do return len(Text)
	_, size := utf8.decode_rune(Text[At:])
	return At + max(size, 1)
}

// is_word reports whether `R` belongs to a word for double-click selection.
@(private="file")
is_word :: proc(R: rune) -> bool {
	return R == '_' || unicode.is_letter(R) || unicode.is_digit(R)
}

// is_word_rune reports whether the rune at `At` is a word rune.
@(private="file")
is_word_rune :: proc(Text: []u8, At: int) -> bool {
	if At >= len(Text) do return false
	r, _ := utf8.decode_rune(Text[At:])
	return is_word(r)
}

// word_span returns the byte range of the word runes around `At`, or of the rune at `At` when
// neither side is a word.
@(private="file")
word_span :: proc(Text: []u8, At: int) -> (start, end: int) {
	at := clamp(At, 0, len(Text))
	start, end = at, at

	for start > 0 {
		r, size := utf8.decode_last_rune(Text[:start])
		if !is_word(r) do break
		start -= size
	}
	for end < len(Text) {
		r, size := utf8.decode_rune(Text[end:])
		if !is_word(r) do break
		end += size
	}
	if start == end {
		if at < len(Text) do return at, rune_after(Text, at)
		if at > 0 do return rune_before(Text, at), at
	}
	return
}

// word_step returns the byte offset one word from `At`: the start of the word before it, or the
// start of the word after it, landing on the buffer edge when there is none.
@(private="file")
word_step :: proc(Text: []u8, At: int, Forward: bool) -> int {
	at := clamp(At, 0, len(Text))
	start, end := word_span(Text, at)

	if Forward {
		at = end
		for at < len(Text) && !is_word_rune(Text, at) do at = rune_after(Text, at)
		return at
	}

	if start < at && is_word_rune(Text, start) do return start
	at = rune_before(Text, at)
	for at > 0 && !is_word_rune(Text, at) do at = rune_before(Text, at)
	start, _ = word_span(Text, at)
	return start
}

// rune_prefix returns the first `Count` runes of `Value`.
@(private="file")
rune_prefix :: proc(Value: string, Count: int) -> string {
	seen := 0
	for _, i in Value {
		if seen == Count do return Value[:i]
		seen += 1
	}
	return Value
}

@(private="file") filtered: [dynamic]u8

// filter_text returns `Value` with the runes `Filter` drops removed and the runes it replaces
// swapped, or `Value` itself when there is no filter.
@(private="file")
filter_text :: proc(Value: string, Filter: CharFilter) -> string {
	if Filter == nil do return Value

	clear(&filtered)
	for r in Value {
		kept, ok := Filter(r)
		if !ok do continue
		bytes, size := utf8.encode_rune(kept)
		append(&filtered, ..bytes[:size])
	}
	return string(filtered[:])
}

@(private="file") masked: [dynamic]u8

// mask_display returns `Text` as it is drawn: itself, or one `Mask` rune per rune of it, with the
// size of one mask rune.
@(private="file")
mask_display :: proc(Text: []u8, Mask: rune) -> (string, int) {
	if Mask == 0 do return string(Text), 0

	bytes, size := utf8.encode_rune(Mask)
	clear(&masked)
	for _ in string(Text) do append(&masked, ..bytes[:size])
	return string(masked[:]), size
}

// display_at maps a buffer offset to its offset in the masked text.
@(private="file")
display_at :: proc(Text: []u8, At, MaskSize: int) -> int {
	if MaskSize == 0 do return At
	return utf8.rune_count(Text[:clamp(At, 0, len(Text))]) * MaskSize
}

// insert_text replaces the selection with `Value` and places the caret after it, keeping at
// most `MaxChars` runes in the buffer. Zero means no limit.
@(private="file")
insert_text :: proc(Text: ^[dynamic]u8, Edit: ^TextEdit, Value: string, MaxChars: int) -> bool {
	if len(Value) == 0 do return false

	start, end := selection(Edit)
	value := Value
	if MaxChars > 0 {
		room := MaxChars - (utf8.rune_count(Text^[:]) - utf8.rune_count(Text^[start:end]))
		if room <= 0 do return false
		value = rune_prefix(value, room)
	}

	remove_range(Text, start, end)
	inject_at(Text, start, value)
	Edit.Caret = start + len(value)
	Edit.Anchor = Edit.Caret
	return true
}

// erase removes the selection, or one `Step` from the caret when there is none, and reports
// whether it removed anything.
@(private="file")
erase :: proc(Text: ^[dynamic]u8, Edit: ^TextEdit, Step: TextStep) -> bool {
	start, end := selection(Edit)
	if start == end {
		switch Step {
		case .RuneBack:    start = rune_before(Text^[:], Edit.Caret)
		case .RuneForward: end = rune_after(Text^[:], Edit.Caret)
		case .WordBack:    start = word_step(Text^[:], Edit.Caret, false)
		case .WordForward: end = word_step(Text^[:], Edit.Caret, true)
		}
	}
	if start == end do return false

	remove_range(Text, start, end)
	Edit.Caret = start
	Edit.Anchor = start
	return true
}

// copy_selection copies the selected bytes to the clipboard and reports whether there were any.
@(private="file")
copy_selection :: proc(Text: []u8, Edit: ^TextEdit) -> bool {
	start, end := selection(Edit)
	if start == end do return false
	ui.SetClipboard(string(Text[start:end]))
	return true
}

// text_advance returns the width `Text` takes up to the byte offset `At`, in layout units.
@(private="file")
text_advance :: proc(Text: string, At: int, Font: ui.Font, Size: f32) -> f32 {
	return ui.MeasureText(Text[:clamp(At, 0, len(Text))], Font, Size).x
}

// index_at_x returns the byte offset whose advance is nearest `X`, in layout units.
@(private="file")
index_at_x :: proc(Text: string, X: f32, Font: ui.Font, Size: f32) -> int {
	cursor, width, best, distance := 0, f32(0), 0, abs(X)

	for cursor < len(Text) {
		_, step := utf8.decode_rune(Text[cursor:])
		step = max(step, 1)
		width += ui.MeasureText(Text[cursor:cursor+step], Font, Size).x
		cursor += step

		if d := abs(width - X); d < distance {
			best, distance = cursor, d
		}
		if width > X && width - X > distance do break
	}
	return best
}

// scroll_to_caret moves the scroll so `At` stays inside `Width`, in layout units.
@(private="file")
scroll_to_caret :: proc(Text: string, Edit: ^TextEdit, At: int, Width: f32, Font: ui.Font, Size: f32) {
	if Width <= 0 do return

	caret := text_advance(Text, At, Font, Size)
	full := text_advance(Text, len(Text), Font, Size)

	if caret - Edit.Scroll > Width - 1 do Edit.Scroll = caret - Width + 1
	if caret - Edit.Scroll < 0 do Edit.Scroll = caret
	Edit.Scroll = clamp(Edit.Scroll, 0, max(full - Width + 1, 0))
}

// draw_text_input paints the selection, the text and the caret inside the box the input already
// filled and outlined.
@(private="file")
draw_text_input :: proc(Rect: ui.Rect, Element: ui.ElementId, User: rawptr) {
	visual := (^TextInputVisual)(User)
	line := ui.MeasureText("", visual.Font, visual.Size).y
	origin := ui.Vec2{Rect.x - visual.Scroll, Rect.y + max((Rect.h - line) / 2, 0)}

	caret_x: f32
	if visual.CaretOn || visual.Caret != visual.Anchor {
		caret_x = text_advance(visual.Text, visual.Caret, visual.Font, visual.Size)
	}

	if visual.Caret != visual.Anchor {
		anchor_x := text_advance(visual.Text, visual.Anchor, visual.Font, visual.Size)
		ui.AddRectFilled({origin.x + min(anchor_x, caret_x), origin.y, abs(caret_x - anchor_x), line}, visual.SelectColor)
	}

	ui.AddText(origin, visual.Text, visual.Color, visual.Font, visual.Size)

	if visual.CaretOn {
		ui.PushAntialias(false)
		ui.AddRectFilled({origin.x + caret_x, origin.y, 1, line}, visual.CaretColor)
		ui.PopAntialias()
	}
}
