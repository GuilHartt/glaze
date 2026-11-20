package ui

import "core:unicode/utf8"

// MouseButton identifies one of the three mouse buttons.
MouseButton :: enum u8 {Left, Right, Middle}

// Modifier identifies a keyboard modifier, independent of its left/right key.
Modifier :: enum u8 {Shift, Ctrl, Alt, Super}

// Key identifies a physical key. Letters, digits and symbols map to the US layout; the backend
// should report the physical key, not the produced text.
Key :: enum u8 {
	A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	Num0, Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9,

	Escape, Enter, Tab, Backspace, Insert, Delete,
	Right, Left, Down, Up, PageUp, PageDown, Home, End,
	CapsLock, ScrollLock, NumLock, PrintScreen, Pause,
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,

	LeftShift, LeftCtrl, LeftAlt, LeftSuper,
	RightShift, RightCtrl, RightAlt, RightSuper,

	Space,
	Apostrophe, Comma, Minus, Period, Slash, Semicolon, Equal,
	LeftBracket, Backslash, RightBracket, Grave,

	Kp0, Kp1, Kp2, Kp3, Kp4, Kp5, Kp6, Kp7, Kp8, Kp9,
	KpDecimal, KpDivide, KpMultiply, KpSubtract, KpAdd, KpEnter, KpEqual,
}

// CursorIcon is the pointer shape a widget asks for. The backend maps it to its own cursor.
CursorIcon :: enum u8 {
	Arrow,
	IBeam,
	Crosshair,
	Hand,
	ResizeEW,
	ResizeNS,
	ResizeNWSE,
	ResizeNESW,
	ResizeAll,
	NotAllowed,
}

// KEY_REPEAT_DELAY and KEY_REPEAT_RATE are the defaults for how long a key is held before it
// starts repeating and the interval between repeats, both in seconds. The engine owns the
// mechanism; an application may change the values with SetKeyRepeat, and a backend never repeats
// a key itself.
@(private)
KEY_REPEAT_DELAY :: 0.40

@(private)
KEY_REPEAT_RATE :: 0.05

// Input holds the input state for the current frame. The backend fills it through the Add*
// procedures and widgets read it through the query procedures.
@(private)
Input :: struct {
	Pos:         Vec2,
	PrevPos:     Vec2,
	Wheel:       Vec2,
	Buttons:     [MouseButton]bool,
	PrevButtons: [MouseButton]bool,
	Keys:        bit_set[Key],
	PrevKeys:    bit_set[Key],
	RepeatWait:  [Key]f32, // seconds until a held key repeats again

	RepeatDelay: f32,
	RepeatRate:  f32,
	Text:        [dynamic]u8,

	ClipboardGet:  proc(User: rawptr) -> string,
	ClipboardSet:  proc(Text: string, User: rawptr),
	ClipboardUser: rawptr,
}

@(private)
input: Input = {RepeatDelay = KEY_REPEAT_DELAY, RepeatRate = KEY_REPEAT_RATE}

// input_end_frame snapshots the current state for the next frame's edge queries and clears the
// per-frame accumulators. Called by End.
@(private)
input_end_frame :: proc() {
	input.PrevPos = input.Pos
	input.PrevButtons = input.Buttons
	input.PrevKeys = input.Keys
	input.Wheel = 0

	for key in input.Keys {
		if wait := &input.RepeatWait[key]; wait^ > 0 {
			wait^ = max(wait^ - time.Delta, 0)
		}
	}

	clear(&input.Text)
	append(&input.Text, 0)
}

// MousePos returns the pointer position for the current frame, in layout units.
MousePos :: proc() -> Vec2 {
	return input.Pos
}

// MouseDelta returns how far the pointer moved since the previous frame.
MouseDelta :: proc() -> Vec2 {
	return input.Pos - input.PrevPos
}

// MouseDown reports whether `Button` is currently held.
MouseDown :: proc(Button: MouseButton) -> bool {
	return input.Buttons[Button]
}

// MousePressed reports whether `Button` went down this frame.
MousePressed :: proc(Button: MouseButton) -> bool {
	return input.Buttons[Button] && !input.PrevButtons[Button]
}

// MouseReleased reports whether `Button` went up this frame.
MouseReleased :: proc(Button: MouseButton) -> bool {
	return !input.Buttons[Button] && input.PrevButtons[Button]
}

// MouseWheel returns the accumulated wheel delta for this frame.
MouseWheel :: proc() -> Vec2 {
	return input.Wheel
}

// Cursor returns the cursor requested for this frame, or Arrow when no widget asked for one.
Cursor :: proc() -> CursorIcon {
	return state.cursor
}

// SetCursor asks for `Icon` as the pointer for this frame. The last call wins, and the
// backend reads it with Cursor after End.
SetCursor :: proc(Icon: CursorIcon) {
	state.cursor = Icon
}

// KeyDown reports whether `Key` is currently held.
KeyDown :: proc(Key: Key) -> bool {
	return Key in input.Keys
}

// KeyPressed reports whether `Key` went down this frame. With `Repeat`, a held key also answers
// after KEY_REPEAT_DELAY and then every KEY_REPEAT_RATE, which is what a slider needs to move
// while an arrow stays down.
KeyPressed :: proc(Key: Key, Repeat := false) -> bool {
	if Key not_in input.Keys do return false
	if Key not_in input.PrevKeys do return true
	if !Repeat do return false

	wait := &input.RepeatWait[Key]
	if wait^ > 0 do return false
	wait^ = input.RepeatRate
	return true
}

// SetKeyRepeat sets how long a key is held before it starts repeating and the interval between
// repeats, both in seconds, for the queries that ask for repeat. Both must be positive.
SetKeyRepeat :: proc(Delay, Rate: f32) {
	if Delay <= 0 || Rate <= 0 {
		report("ui: key repeat values must be positive")
		return
	}
	input.RepeatDelay = Delay
	input.RepeatRate = Rate
}

// KeyReleased reports whether `Key` went up this frame.
KeyReleased :: proc(Key: Key) -> bool {
	return Key not_in input.Keys && Key in input.PrevKeys
}

// ModifierDown reports whether any key mapped to `Mod` is held.
ModifierDown :: proc(Mod: Modifier) -> bool {
	switch Mod {
	case .Shift: return KeyDown(.LeftShift) || KeyDown(.RightShift)
	case .Ctrl:  return KeyDown(.LeftCtrl)  || KeyDown(.RightCtrl)
	case .Alt:   return KeyDown(.LeftAlt)   || KeyDown(.RightAlt)
	case .Super: return KeyDown(.LeftSuper) || KeyDown(.RightSuper)
	}
	return false
}

// TextInput returns the text typed this frame, valid until the end of the frame.
TextInput :: proc() -> string {
	if len(input.Text) == 0 do return ""
	return string(input.Text[:len(input.Text) - 1])
}

// GetClipboard returns the system clipboard contents, using the callback bound with
// BindClipboard, or an empty string when no callback is bound.
GetClipboard :: proc() -> string {
	if input.ClipboardGet == nil do return ""
	return input.ClipboardGet(input.ClipboardUser)
}

// SetClipboard copies `Text` to the system clipboard, using the callback bound with
// BindClipboard. Does nothing when no callback is bound.
SetClipboard :: proc(Text: string) {
	if input.ClipboardSet != nil {
		input.ClipboardSet(Text, input.ClipboardUser)
	}
}

// AddMousePos feeds the pointer position, in screen units. Call it once per frame, or once per
// pointer-move event.
AddMousePos :: proc(Pos: Vec2) { input.Pos = Pos / state.screen.ui }

// AddMouseButton feeds a mouse button transition. Call it on every press and release.
AddMouseButton :: proc(Button: MouseButton, Down: bool) { input.Buttons[Button] = Down }

// AddMouseWheel feeds a wheel delta. Multiple calls in a frame accumulate.
AddMouseWheel :: proc(Delta: Vec2) { input.Wheel += Delta }

// AddKey feeds a key transition, or the held state of a key the backend polls. The engine builds
// key repeat from the held state and the frame delta, so a backend reports what the system gives
// it and never repeats a key itself.
AddKey :: proc(Key: Key, Down: bool) {
	if Down {
		if Key not_in input.Keys do input.RepeatWait[Key] = input.RepeatDelay
		input.Keys += {Key}
	} else {
		input.Keys -= {Key}
		input.RepeatWait[Key] = 0
	}
}

// AddTypedText feeds text typed this frame. The backend must pass it already decoded to UTF-8.
AddTypedText :: proc(Text: string) {
	if len(Text) == 0 do return
	drop_terminator()
	append(&input.Text, Text)
	append(&input.Text, 0)
}

// AddTypedRune feeds a single typed character, for backends that report input as code points.
AddTypedRune :: proc(R: rune) {
	drop_terminator()
	buf, n := utf8.encode_rune(R)
	append(&input.Text, ..buf[:n])
	append(&input.Text, 0)
}

// drop_terminator removes the trailing null byte so more text can be appended.
@(private)
drop_terminator :: proc() {
	if len(input.Text) > 0 && input.Text[len(input.Text)-1] == 0 {
		resize(&input.Text, len(input.Text)-1)
	}
}

// BindClipboard registers the backend callbacks used by GetClipboard and SetClipboard, so
// clipboard access stays backend-independent.
BindClipboard :: proc(
	Get: proc(User: rawptr) -> string,
	Set: proc(Text: string, User: rawptr),
	User: rawptr = nil,
) {
	input.ClipboardGet  = Get
	input.ClipboardSet  = Set
	input.ClipboardUser = User
}

// Time holds the timing the backend feeds: the delta of the last frame and the total elapsed.
@(private)
Time :: struct {
	Delta: f32,
	Total: f32,
}

@(private)
time: Time

// DeltaTime returns the time elapsed since the previous frame, in seconds.
DeltaTime :: proc() -> f32 {
	return time.Delta
}

// ElapsedTime returns the total time elapsed since the first frame, in seconds.
ElapsedTime :: proc() -> f32 {
	return time.Total
}

// AddDeltaTime feeds the time elapsed since the previous frame, in seconds. Call it once per
// frame, before Begin.
AddDeltaTime :: proc(Delta: f32) {
	time.Delta = Delta
	time.Total += Delta
}
