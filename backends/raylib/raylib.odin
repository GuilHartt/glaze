// Package raylib_backend adapts raylib to Glaze. It owns no window and no loop:
// Setup binds raylib's font and clipboard to the engine, Update feeds per-frame
// state, and Render draws the command list the engine produced.
package raylib_backend

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import ui "../../ui"

// Setup binds raylib's default font and clipboard to the engine. Call it once,
// after the window exists and before the first frame.
Setup :: proc() {
	when ODIN_DEBUG {
		for key in ui.Key {
			assert(KEY_MAP[key] != .KEY_NULL, "raylib_backend: every ui.Key needs an entry in KEY_MAP")
		}
	}
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
		ui.AddTypedRune(ch)
	}
}

@(private="file")
atlas: rl.Texture2D

// sync_atlas uploads the glyph atlas whenever the engine changed it. The atlas is
// one byte of coverage per texel, so it goes up as opaque white with that coverage
// as alpha, which is what the default shader multiplies by the vertex color.
@(private="file")
sync_atlas :: proc() {
	pixels, width, height := ui.FontAtlas()
	if width == 0 || height == 0 do return

	changed := ui.TakeAtlasUpdate()
	resized := atlas.id == 0 || int(atlas.width) != width || int(atlas.height) != height
	if !changed && !resized do return

	rgba := make([]u8, width * height * 4)
	defer delete(rgba)
	for i in 0 ..< width * height {
		rgba[i * 4 + 0] = 255
		rgba[i * 4 + 1] = 255
		rgba[i * 4 + 2] = 255
		rgba[i * 4 + 3] = pixels[i]
	}

	image := rl.Image{
		data    = raw_data(rgba),
		width   = i32(width),
		height  = i32(height),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}

	if resized {
		if atlas.id != 0 do rl.UnloadTexture(atlas)
		atlas = rl.LoadTextureFromImage(image)
		ui.SetAtlasTexture(ui.Texture(&atlas))
	} else {
		rl.UpdateTexture(atlas, raw_data(rgba))
	}
}

// Render draws the commands produced by the last frame. Call it once per frame,
// after ui.End.
Render :: proc() {
	sync_atlas()
	
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()

	frame := ui.DrawData()
	for cmd in frame.Commands {
		rlgl.SetTexture(texture_id(cmd.Texture))
		rlgl.Begin(rlgl.TRIANGLES)
		for i in cmd.Offset ..< cmd.Offset + cmd.Count {
			v := frame.Vertices[frame.Indices[i]]
			rlgl.Color4ub(v.Color.r, v.Color.g, v.Color.b, v.Color.a)
			rlgl.TexCoord2f(v.UV.x, v.UV.y)
			rlgl.Vertex2f(v.Pos.x, v.Pos.y)
		}
		rlgl.End()
	}

	// The batch must be flushed while culling is still off: the engine's winding
	// is the opposite of raylib's, so flushing after the restore would drop all of
	// it.
	rlgl.DrawRenderBatchActive()
	rlgl.SetTexture(u32(rlgl.GetTextureIdDefault()))
	rlgl.EnableBackfaceCulling()
}

// texture_id turns an engine texture handle into the GL id rlgl expects. A zero
// handle gets raylib's 1x1 white texture, because texture 0 samples nothing and
// comes back black.
@(private="file")
texture_id :: #force_inline proc "contextless" (T: ui.Texture) -> u32 {
	if T == nil do return u32(rlgl.GetTextureIdDefault())
	return (^rl.Texture2D)(rawptr(T)).id
}

@(private="file")
clipboard_get :: proc(User: rawptr) -> cstring {
	return rl.GetClipboardText()
}

@(private="file")
clipboard_set :: proc(Text: cstring, User: rawptr) {
	rl.SetClipboardText(Text)
}

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
