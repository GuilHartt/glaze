package ui

import "core:unicode/utf8"

// MouseButton identifies one of the three mouse buttons.
MouseButton :: enum u8 {Left, Right, Middle}

// Modifier identifies a keyboard modifier, independent of its left/right key.
Modifier :: enum u8 {Shift, Ctrl, Alt, Super}

// Key identifies a physical key. Letters, digits and symbols map to the US
// layout; the backend should report the physical key, not the produced text.
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

// Input holds the input state for the current frame. The backend fills it
// through the Add* procedures and widgets read it through the query
// procedures; widgets never touch a backend directly.
Input :: struct {
	Pos:         Vec2,
	PrevPos:     Vec2,
	Wheel:       Vec2,
	Buttons:     [MouseButton]bool,
	PrevButtons: [MouseButton]bool,
	Keys:        bit_set[Key],
	PrevKeys:    bit_set[Key],
	Text:        [dynamic]u8,

	ClipboardGet:  proc(User: rawptr) -> cstring,
	ClipboardSet:  proc(Text: cstring, User: rawptr),
	ClipboardUser: rawptr,
}

@(private)
input: Input

// input_end_frame snapshots the current state for the next frame's edge
// queries and clears the per-frame accumulators. Called by End.
@(private)
input_end_frame :: proc() {
	input.PrevPos = input.Pos
	input.PrevButtons = input.Buttons
	input.PrevKeys = input.Keys
	input.Wheel = 0
	clear(&input.Text)
	append(&input.Text, 0)
}

// MousePos returns the pointer position for the current frame.
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

// KeyDown reports whether `Key` is currently held.
KeyDown :: proc(Key: Key) -> bool {
	return Key in input.Keys
}

// KeyPressed reports whether `Key` went down this frame.
KeyPressed :: proc(Key: Key) -> bool {
	return Key in input.Keys && Key not_in input.PrevKeys
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

// TextInput returns the text typed this frame as a null-terminated string. The
// returned pointer is only valid until the end of the frame.
TextInput :: proc() -> cstring {
	return cstring(raw_data(input.Text))
}

// GetClipboard returns the system clipboard contents, using the callback bound
// with BindClipboard. Returns nil when no callback is bound.
GetClipboard :: proc() -> cstring {
	if input.ClipboardGet == nil do return nil
	return input.ClipboardGet(input.ClipboardUser)
}

// SetClipboard copies `Text` to the system clipboard, using the callback bound
// with BindClipboard. Does nothing when no callback is bound.
SetClipboard :: proc(Text: cstring) {
	if input.ClipboardSet != nil {
		input.ClipboardSet(Text, input.ClipboardUser)
	}
}

// AddMousePos feeds the current pointer position. Call it once per frame, or
// once per pointer-move event.
AddMousePos :: proc(Pos: Vec2) { input.Pos = Pos }

// AddMouseButton feeds a mouse button transition. `Down` is the new held state.
// Call it on every press and release.
AddMouseButton :: proc(Button: MouseButton, Down: bool) { input.Buttons[Button] = Down }

// AddMouseWheel feeds a wheel delta. Multiple calls in a frame accumulate.
AddMouseWheel :: proc(Delta: Vec2) { input.Wheel += Delta }

// AddKey feeds a key transition. `Down` is the new held state. Call it on every
// press and release.
AddKey :: proc(Key: Key, Down: bool) {
	if Down {
		input.Keys += {Key}
	} else {
		input.Keys -= {Key}
	}
}

// AddTypedText feeds text typed this frame. Append per character/commit event;
// the backend must pass it already decoded to UTF-8.
AddTypedText :: proc(Text: cstring) {
	if Text == nil do return
	drop_terminator()
	append(&input.Text, ..(transmute([^]u8)Text)[0:len(Text)])
	append(&input.Text, 0)
}

// AddTypedRune feeds a single typed character. Use it when the backend reports
// input as Unicode code points (e.g. raylib's GetCharPressed).
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

// BindClipboard registers the backend callbacks used by GetClipboard and
// SetClipboard, so clipboard access stays backend-independent. `User` is passed
// back to both callbacks.
BindClipboard :: proc(
	Get: proc(User: rawptr) -> cstring,
	Set: proc(Text: cstring, User: rawptr),
	User: rawptr = nil,
) {
	input.ClipboardGet  = Get
	input.ClipboardSet  = Set
	input.ClipboardUser = User
}

// Time holds the per-frame timing that the backend feeds, alongside Input.
Time :: struct {
	Delta: f32,
}

@(private)
time: Time

// DeltaTime returns the time elapsed since the previous frame, in seconds. Use
// it to drive animation and any time-based widget.
DeltaTime :: proc() -> f32 {
	return time.Delta
}

// AddDeltaTime feeds the time elapsed since the previous frame, in seconds. Call
// it once per frame, before Begin.
AddDeltaTime :: proc(Delta: f32) {
	time.Delta = Delta
}
