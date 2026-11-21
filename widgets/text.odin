package widgets

import "core:unicode"
import "core:unicode/utf8"
import ui "../ui"

// TextStyle is what a text field paints: the box and the text of the shared widget style, plus the
// color of the caret, of the selection and of the placeholder.
TextStyle :: struct {
	using common: WidgetStyle,
	Caret:        ui.Color,
	Selection:    ui.Color,
	Placeholder:  ui.Color,
}

// CharFilter screens a rune that typing or pasting puts in the text: the returned rune replaces it,
// and false drops it.
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

// text_state is what a text widget keeps between frames, keyed by the element id: the caret and
// the anchor as byte offsets, the blink, and what the widget derives from the caller's text.
@(private)
text_state :: struct {
	Caret:     int,
	Anchor:    int,
	Want:      f32,
	Blink:     f32,
	Active:    bool,
	Selecting: bool,
	Original:  [dynamic]u8,
	Display:   [dynamic]u8,
	Source:    [dynamic]u8,
	Lines:     [dynamic]ui.Line,
	Block:     ui.Vec2,
	Width:     f32,
	Font:      ui.Font,
	Size:      f32,
	Wrap:      ui.WrapMode,
}

// destroy_text_state frees the buffers a text state keeps, so the storage can drop it.
@(private)
destroy_text_state :: proc(Value: rawptr) {
	State := (^text_state)(Value)
	delete(State.Original)
	delete(State.Display)
	delete(State.Source)
	delete(State.Lines)
}

// TextKeys is what a keymap needs besides the text and the state.
@(private)
TextKeys :: struct {
	MaxChars: int,
	Filter:   CharFilter,
	ReadOnly: bool,
	Mask:     rune,
	First:    bool,
}

// selection returns the selected byte range, ordered so start <= end.
@(private="file")
selection :: proc(State: ^text_state) -> (start, end: int) {
	return min(State.Anchor, State.Caret), max(State.Anchor, State.Caret)
}

// move_caret places the caret at `At`, keeping the anchor when `Select` is set, and drops the
// column a vertical move was holding.
@(private)
move_caret :: proc(State: ^text_state, At: int, Select: bool) {
	if !Select do State.Anchor = At
	State.Caret = At
	State.Want = -1
}

// TextStep is one step through the text: a rune or a word, back or forward.
@(private)
TextStep :: enum u8 { RuneBack, RuneForward, WordBack, WordForward }

// step_caret moves the caret one `Step`, collapsing the selection to its edge when `Select`
// is off, so the move starts from there instead of stepping.
@(private)
step_caret :: proc(Text: []u8, State: ^text_state, Step: TextStep, Select: bool) {
	if !Select {
		if start, end := selection(State); start != end {
			back := Step == .RuneBack || Step == .WordBack
			move_caret(State, start if back else end, false)
			return
		}
	}

	switch Step {
	case .RuneBack:    move_caret(State, rune_before(Text, State.Caret), Select)
	case .RuneForward: move_caret(State, rune_after(Text, State.Caret), Select)
	case .WordBack:    move_caret(State, word_step(Text, State.Caret, false), Select)
	case .WordForward: move_caret(State, word_step(Text, State.Caret, true), Select)
	}
}

// move_line moves the caret one line up or down, holding the column it had.
@(private)
move_line :: proc(Text: string, Lines: []ui.Line, State: ^text_state, Delta: int, Select: bool, Font: ui.Font, Size: f32) {
	lh := line_height(Font, Size)
	want := State.Want
	if want < 0 do want = caret_point(Text, Lines, State.Caret, Font, Size, lh).x

	line := Lines[clamp(line_at(Lines, State.Caret) + Delta, 0, len(Lines) - 1)]
	move_caret(State, int(line.Start) + index_at_x(Text[int(line.Start):int(line.End)], want, Font, Size), Select)
	State.Want = want
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
@(private)
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
// start of the word after it, landing on the edge when there is none.
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
@(private)
rune_prefix :: proc(Value: string, Count: int) -> string {
	seen := 0
	for _, i in Value {
		if seen == Count do return Value[:i]
		seen += 1
	}
	return Value
}

// insert_text replaces the selection with `Value` and places the caret after it, keeping at
// most `MaxChars` runes in the text. Zero means no limit.
@(private)
insert_text :: proc(Text: ^[dynamic]u8, State: ^text_state, Value: string, MaxChars: int) -> bool {
	if len(Value) == 0 do return false

	start, end := selection(State)
	value := Value
	if MaxChars > 0 {
		room := MaxChars - (utf8.rune_count(Text^[:]) - utf8.rune_count(Text^[start:end]))
		if room <= 0 do return false
		value = rune_prefix(value, room)
	}

	remove_range(Text, start, end)
	inject_at(Text, start, value)
	State.Caret = start + len(value)
	State.Anchor = State.Caret
	State.Want = -1
	return true
}

// erase removes the selection, or one `Step` from the caret when there is none, and reports
// whether it removed anything.
@(private)
erase :: proc(Text: ^[dynamic]u8, State: ^text_state, Step: TextStep) -> bool {
	start, end := selection(State)
	if start == end {
		switch Step {
		case .RuneBack:    start = rune_before(Text^[:], State.Caret)
		case .RuneForward: end = rune_after(Text^[:], State.Caret)
		case .WordBack:    start = word_step(Text^[:], State.Caret, false)
		case .WordForward: end = word_step(Text^[:], State.Caret, true)
		}
	}
	if start == end do return false

	remove_range(Text, start, end)
	State.Caret = start
	State.Anchor = start
	State.Want = -1
	return true
}

// copy_selection copies the selected bytes to the clipboard and reports whether there were any.
@(private)
copy_selection :: proc(Text: []u8, State: ^text_state) -> bool {
	start, end := selection(State)
	if start == end do return false
	ui.SetClipboard(string(Text[start:end]))
	return true
}

@(private)
empty_lines := [1]ui.Line{{}}

// line_at returns the index of the line `At` falls in.
@(private)
line_at :: proc(Lines: []ui.Line, At: int) -> int {
	lo, hi := 0, len(Lines) - 1
	for lo < hi {
		mid := (lo + hi + 1) / 2
		switch {
		case int(Lines[mid].Start) <= At: lo = mid
		case:                             hi = mid - 1
		}
	}
	return lo
}

// caret_point returns where `At` sits in the block of `Lines`, in layout units.
@(private)
caret_point :: proc(Text: string, Lines: []ui.Line, At: int, Font: ui.Font, Size: f32, LineHeight: f32) -> ui.Vec2 {
	i := line_at(Lines, At)
	line := Lines[i]
	at := clamp(At, int(line.Start), int(line.End))
	return {ui.MeasureText(Text[int(line.Start):at], Font, Size).x, f32(i) * LineHeight}
}

// offset_at returns the byte offset nearest `Pos`, in layout units, in the block of `Lines`.
@(private)
offset_at :: proc(Text: string, Lines: []ui.Line, Pos: ui.Vec2, Font: ui.Font, Size: f32, LineHeight: f32) -> int {
	if LineHeight <= 0 do return 0

	i := clamp(int(Pos.y / LineHeight), 0, len(Lines) - 1)
	line := Lines[i]
	return int(line.Start) + index_at_x(Text[int(line.Start):int(line.End)], Pos.x, Font, Size)
}

// line_height returns the height one line of `Font` at `Size` takes, in layout units.
@(private)
line_height :: proc(Font: ui.Font, Size: f32) -> f32 {
	return ui.MeasureText("", Font, Size).y
}

// field_height returns the height `Rows` lines of `Style` take, padding and border included.
@(private)
field_height :: proc(Style: ^TextStyle, Rows: int) -> f32 {
	return line_height(Style.Font, Style.FontSize) * f32(Rows) +
		Style.Pad.Top + Style.Pad.Bottom + Style.BorderWidth.Top + Style.BorderWidth.Bottom
}

// content_width returns the width a text leaf takes at `View` width: the block, plus the pixel the
// caret at the end needs to stay inside the view, or the view itself when the text fits.
@(private)
content_width :: proc(Block, View: f32) -> f32 {
	if Block > View do return Block + 1
	return View
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

// edge_distance returns how far `Value` sits past `Lo`..`Hi`, and zero inside it.
@(private="file")
edge_distance :: proc(Value, Lo, Hi: f32) -> f32 {
	if Value < Lo do return Value - Lo
	if Value > Hi do return Value - Hi
	return 0
}

// autoscroll moves the view of `Element` while the pointer is dragged past `View`, and returns the
// offset the drag maps through. `Block` is the content size.
@(private)
autoscroll :: proc(Element: ui.ElementId, Offset: ui.Vec2, View: ui.Rect, Block: ui.Vec2, LineHeight: f32) -> ui.Vec2 {
	// The view moves this many lines per second one line past the edge, growing with the distance
	// until AUTOSCROLL_REACH lines.
	AUTOSCROLL :: f32(10)
	AUTOSCROLL_REACH :: f32(4)

	if LineHeight <= 0 || View.w <= 0 || View.h <= 0 do return Offset

	pos := ui.MousePos()
	over := ui.Vec2{
		edge_distance(pos.x, View.x, View.x + View.w),
		edge_distance(pos.y, View.y, View.y + View.h),
	}
	if over == 0 do return Offset

	next := Offset
	step := LineHeight * AUTOSCROLL * ui.DeltaTime()
	if over.x != 0 {
		speed := step * clamp(abs(over.x) / LineHeight, 1, AUTOSCROLL_REACH)
		next.x += (-speed if over.x < 0 else speed)
	}
	if over.y != 0 {
		speed := step * clamp(abs(over.y) / LineHeight, 1, AUTOSCROLL_REACH)
		next.y += (-speed if over.y < 0 else speed)
	}

	next = {
		clamp(next.x, 0, max(Block.x - View.w, 0)),
		clamp(next.y, 0, max(Block.y - View.h, 0)),
	}
	if next != Offset do ui.SetScroll(next, Element)
	return next
}

// scroll_to_caret moves the view of `Element` so the caret at `At` sits inside `View`, where `Step`
// is the room the caret takes on each axis. An axis with no view keeps its offset, and the layout
// clamps the result to the content.
@(private)
scroll_to_caret :: proc(Element: ui.ElementId, At, Step, View: ui.Vec2) {
	if View.x <= 0 && View.y <= 0 do return

	offset := ui.ScrollOffset(Element)
	next := offset

	if View.x > 0 {
		if At.x + Step.x - next.x > View.x do next.x = At.x + Step.x - View.x
		if At.x - next.x < 0 do next.x = At.x
	}
	if View.y > 0 {
		if At.y + Step.y - next.y > View.y do next.y = At.y + Step.y - View.y
		if At.y - next.y < 0 do next.y = At.y
	}
	if next != offset do ui.SetScroll(next, Element)
}

@(private="file") filtered: [dynamic]u8

// filter_text returns `Value` with the runes `Filter` drops removed and the runes it replaces
// swapped. A multi-line field also loses the carriage returns a pasted CRLF carries.
@(private="file")
filter_text :: proc(Value: string, Filter: CharFilter, Multiline: bool) -> string {
	if Filter == nil {
		if !Multiline do return Value
		clear(&filtered)
		for i in 0 ..< len(Value) {
			if Value[i] != '\r' do append(&filtered, Value[i])
		}
		return string(filtered[:])
	}

	clear(&filtered)
	for r in Value {
		if Multiline && r == '\r' do continue
		kept, ok := Filter(r)
		if !ok do continue
		bytes, size := utf8.encode_rune(kept)
		append(&filtered, ..bytes[:size])
	}
	return string(filtered[:])
}

// input_text returns `Value` as a multi-line field takes it: filtered, without the carriage
// returns a pasted CRLF carries.
@(private)
input_text :: proc(Value: string, Keys: TextKeys) -> string {
	return filter_text(Value, Keys.Filter, true)
}

// one_line returns the part of `Text` before the first newline, since a single-line field holds
// one row.
@(private="file")
one_line :: proc(Text: string) -> string {
	for c, i in Text {
		if c == '\n' || c == '\r' do return Text[:i]
	}
	return Text
}

// line_text returns `Value` as a single-line field takes it: its first row, filtered.
@(private)
line_text :: proc(Value: string, Keys: TextKeys) -> string {
	return filter_text(one_line(Value), Keys.Filter, false)
}
