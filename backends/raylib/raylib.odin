// Package raylib_backend adapts raylib to Glaze. It owns no window and no loop:
// Setup binds raylib's font and clipboard to the engine, Update feeds per-frame
// state, and Render draws the command list the engine produced.
package raylib_backend

import ui "../../ui"
import rl "vendor:raylib"

// Setup binds raylib's default font and clipboard to the engine. Call it once,
// after the window exists and before the first frame.
Setup :: proc() {
	when ODIN_DEBUG {
		for key in ui.Key {
			assert(KEY_MAP[key] != .KEY_NULL, "raylib_backend: every ui.Key needs an entry in KEY_MAP")
		}
	}
	font = rl.GetFontDefault()
	ui.SetMeasureText(measure_text)
	ui.BindClipboard(clipboard_get, clipboard_set)
}

// Update feeds the current raylib state into the engine. Call it once per frame,
// before ui.Begin.
Update :: proc() {
	ui.AddDeltaTime(rl.GetFrameTime())
	ui.AddViewport({f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})

	pos := rl.GetMousePosition()
	ui.AddMousePos({pos.x, pos.y})
	ui.AddMouseButton(.Left,   rl.IsMouseButtonDown(.LEFT))
	ui.AddMouseButton(.Right,  rl.IsMouseButtonDown(.RIGHT))
	ui.AddMouseButton(.Middle, rl.IsMouseButtonDown(.MIDDLE))
	wheel := rl.GetMouseWheelMoveV()
	ui.AddMouseWheel({wheel.x, wheel.y})

	for key in ui.Key {
		ui.AddKey(key, rl.IsKeyDown(KEY_MAP[key]))
	}
	for ch := rl.GetCharPressed(); ch != 0; ch = rl.GetCharPressed() {
		ui.AddTextRune(ch)
	}
}

// Render draws the commands produced by the last frame. Call it once per frame,
// after ui.End.
Render :: proc() {
	for cmd in ui.DrawData() {
		switch c in cmd {
		case ui.CommandRect:
			bounds := to_rect(c.Bounds)
			round := roundness(c.Radius, c.Bounds)
			if c.Color.a != 0 {
				rl.DrawRectangleRounded(bounds, round, ROUND_SEGMENTS, rl.Color(c.Color))
			}
			if c.Border.Width > 0 {
				rl.DrawRectangleRoundedLinesEx(bounds, round, ROUND_SEGMENTS, c.Border.Width, rl.Color(c.Border.Color))
			}
		case ui.CommandText:
			size := c.Size
			if size <= 0 do size = f32(font.baseSize)
			rl.DrawTextEx(font, c.Text, {c.Bounds.x, c.Bounds.y}, size, size * LETTER_SPACING, rl.Color(c.Color))
		case ui.CommandImage:
			texture := (^rl.Texture2D)(c.Handle)^
			source := rl.Rectangle{0, 0, f32(texture.width), f32(texture.height)}
			rl.DrawTexturePro(texture, source, to_rect(c.Bounds), {}, 0, rl.Color(c.Tint))
		}
	}
}

// to_rect converts an engine rect into a raylib rectangle.
@(private="file")
to_rect :: #force_inline proc "contextless" (R: ui.Rect) -> rl.Rectangle {
	return {R.x, R.y, R.w, R.h}
}

// roundness converts a corner radius into raylib's 0..1 roundness, measured
// against the shortest side of the rect.
@(private="file")
roundness :: #force_inline proc "contextless" (Radius: f32, R: ui.Rect) -> f32 {
	half := min(R.w, R.h) / 2
	if half <= 0 do return 0
	return clamp(Radius / half, 0, 1)
}

@(private="file")
measure_text :: proc(Text: cstring, Config: ui.TextConfig, User: rawptr) -> ui.Vec2 {
	size := Config.Size
	if size <= 0 do size = f32(font.baseSize)
	measured := rl.MeasureTextEx(font, Text, size, size * LETTER_SPACING)
	return {measured.x, measured.y}
}

@(private="file")
clipboard_get :: proc(User: rawptr) -> cstring {
	return rl.GetClipboardText()
}

@(private="file")
clipboard_set :: proc(Text: cstring, User: rawptr) {
	rl.SetClipboardText(Text)
}

@(private="file")
font: rl.Font

@(private="file")
ROUND_SEGMENTS :: 8

// LETTER_SPACING is the gap between glyphs as a fraction of the font size, which
// is how raylib's DrawText spaces them.
@(private="file")
LETTER_SPACING :: 0.1

// KEY_MAP maps each engine key to the raylib key that produces it. Every ui.Key
// needs an entry: a missing one stays zero and the key goes dead.
@(private="file")
KEY_MAP := [ui.Key]rl.KeyboardKey {
	.A = .A, .B = .B, .C = .C, .D = .D, .E = .E, .F = .F,
	.G = .G, .H = .H, .I = .I, .J = .J, .K = .K, .L = .L,
	.M = .M, .N = .N, .O = .O, .P = .P, .Q = .Q, .R = .R,
	.S = .S, .T = .T, .U = .U, .V = .V, .W = .W, .X = .X,
	.Y = .Y, .Z = .Z,

	.Num0 = .ZERO, .Num1 = .ONE, .Num2 = .TWO, .Num3 = .THREE,
	.Num4 = .FOUR, .Num5 = .FIVE, .Num6 = .SIX, .Num7 = .SEVEN,
	.Num8 = .EIGHT, .Num9 = .NINE,

	.Escape = .ESCAPE, .Enter = .ENTER, .Tab = .TAB,
	.Backspace = .BACKSPACE, .Insert = .INSERT, .Delete = .DELETE,

	.Right = .RIGHT, .Left = .LEFT, .Down = .DOWN, .Up = .UP,
	.PageUp = .PAGE_UP, .PageDown = .PAGE_DOWN, .Home = .HOME, .End = .END,

	.CapsLock = .CAPS_LOCK, .ScrollLock = .SCROLL_LOCK, .NumLock = .NUM_LOCK,
	.PrintScreen = .PRINT_SCREEN, .Pause = .PAUSE,

	.F1 = .F1, .F2 = .F2, .F3 = .F3, .F4 = .F4,
	.F5 = .F5, .F6 = .F6, .F7 = .F7, .F8 = .F8,
	.F9 = .F9, .F10 = .F10, .F11 = .F11, .F12 = .F12,

	.LeftShift = .LEFT_SHIFT, .LeftCtrl = .LEFT_CONTROL,
	.LeftAlt = .LEFT_ALT, .LeftSuper = .LEFT_SUPER,
	.RightShift = .RIGHT_SHIFT, .RightCtrl = .RIGHT_CONTROL,
	.RightAlt = .RIGHT_ALT, .RightSuper = .RIGHT_SUPER,

	.Space = .SPACE,
	.Apostrophe = .APOSTROPHE, .Comma = .COMMA, .Minus = .MINUS,
	.Period = .PERIOD, .Slash = .SLASH, .Semicolon = .SEMICOLON, .Equal = .EQUAL,
	.LeftBracket = .LEFT_BRACKET, .Backslash = .BACKSLASH,
	.RightBracket = .RIGHT_BRACKET, .Grave = .GRAVE,

	.Kp0 = .KP_0, .Kp1 = .KP_1, .Kp2 = .KP_2, .Kp3 = .KP_3,
	.Kp4 = .KP_4, .Kp5 = .KP_5, .Kp6 = .KP_6, .Kp7 = .KP_7,
	.Kp8 = .KP_8, .Kp9 = .KP_9,

	.KpDecimal = .KP_DECIMAL, .KpDivide = .KP_DIVIDE,
	.KpMultiply = .KP_MULTIPLY, .KpSubtract = .KP_SUBTRACT,
	.KpAdd = .KP_ADD, .KpEnter = .KP_ENTER, .KpEqual = .KP_EQUAL,
}
