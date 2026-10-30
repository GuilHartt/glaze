package ui

import "core:math"

// Pad builds a Padding: Pad(All) puts `All` on every side, Pad(X, Y) puts `X` on
// the left and right and `Y` on the top and bottom.
Pad :: proc{pad_all, pad_xy}

// Rounding holds the radius of each corner, so one rectangle can round its corners
// independently.
Rounding :: struct {
	TopLeft, TopRight, BottomRight, BottomLeft: f32,
}

// Round returns a rounding with `All` on every corner.
Round :: #force_inline proc "contextless" (All: f32) -> Rounding {
	return {TopLeft = All, TopRight = All, BottomRight = All, BottomLeft = All}
}

// pad_all returns the padding with `All` on every side.
@(private="file")
pad_all :: #force_inline proc(All: f32) -> Padding {
	return {Left = All, Right = All, Top = All, Bottom = All}
}

// pad_xy returns the padding with `X` on the left and right and `Y` on the top
// and bottom.
@(private="file")
pad_xy :: #force_inline proc(X, Y: f32) -> Padding {
	return {Left = X, Right = X, Top = Y, Bottom = Y}
}

// Grow returns a sizing whose base is the content size, expanding to take a
// `Weight`-proportional share of the parent's leftover space.
Grow :: #force_inline proc "contextless" (Weight: f32 = 1, Shrink: f32 = 0) -> Sizing {
	return {Kind = .Fit, Grow = Weight, Shrink = Shrink}
}

// Fill returns a sizing whose base is zero and that divides the parent's space
// by `Weight` (ignoring content). Use it for equal-sized children.
Fill :: #force_inline proc "contextless" (Weight: f32 = 1, Shrink: f32 = 0) -> Sizing {
	return {Kind = .Fixed, Grow = Weight, Shrink = Shrink}
}

// Fit returns a sizing that hugs the content and never grows or shrinks.
Fit :: #force_inline proc "contextless" () -> Sizing {
	return {Kind = .Fit}
}

// Fixed returns a sizing of exactly `Px` that never grows or shrinks.
Fixed :: #force_inline proc "contextless" (Px: f32) -> Sizing {
	return {Kind = .Fixed, Basis = Px}
}

// RectContains reports whether the point lies inside the rect.
RectContains :: proc(Rect: Rect, Point: Vec2) -> bool {
	return Point.x >= Rect.x && Point.x <= Rect.x + Rect.w &&
		   Point.y >= Rect.y && Point.y <= Rect.y + Rect.h
}

// RectIntersect returns the overlap of the two rects, or an empty rect when they
// do not touch.
RectIntersect :: proc(A, B: Rect) -> Rect {
	x := max(A.x, B.x)
	y := max(A.y, B.y)
	return {x, y, max(0, min(A.x + A.w, B.x + B.w) - x), max(0, min(A.y + A.h, B.y + B.h) - y)}
}

// Hex returns the color of the 0xRRGGBB value `Rgb`, with `Alpha` as its alpha
// channel.
Hex :: #force_inline proc(Rgb: u32, Alpha: u8 = 255) -> Color {
	return {u8(Rgb >> 16), u8(Rgb >> 8), u8(Rgb), Alpha}
}

// HexA returns the color of the 0xRRGGBBAA value `Rgba`.
HexA :: #force_inline proc(Rgba: u32) -> Color {
	return {u8(Rgba >> 24), u8(Rgba >> 16), u8(Rgba >> 8), u8(Rgba)}
}

// Rgb returns the color of the `R`, `G` and `B` channels, with `Alpha` as its
// alpha channel.
Rgb :: #force_inline proc(R, G, B: u8, Alpha: u8 = 255) -> Color {
	return {R, G, B, Alpha}
}

// Hsv returns the color of `H` (hue in degrees), `S` (saturation) and `V`
// (value), with `Alpha` as its alpha channel. The hue wraps into 0..360 and the
// saturation and value clamp to 0..1.
Hsv :: proc(H, S, V: f32, Alpha: u8 = 255) -> Color {
	hue := H - 360 * math.floor(H / 360)
	sat := clamp(S, 0, 1)
	val := clamp(V, 0, 1)

	return {
		to_channel(hsv_channel(hue, sat, val, 5)),
		to_channel(hsv_channel(hue, sat, val, 3)),
		to_channel(hsv_channel(hue, sat, val, 1)),
		Alpha,
	}
}

// hsv_channel returns one channel of the HSV color: `N` picks both the channel
// (5 red, 3 green, 1 blue) and its position around the color wheel. This is the
// CSS Color 4 formulation, which needs no per-sector table.
@(private="file")
hsv_channel :: #force_inline proc(H, S, V, N: f32) -> f32 {
	k := math.mod(H / 60 + N, 6)
	return V - V * S * clamp(min(k, 4 - k), 0, 1)
}

// to_channel converts a 0..1 channel value to a byte, rounding to nearest.
@(private="file")
to_channel :: #force_inline proc(X: f32) -> u8 {
	return u8(clamp(X, 0, 1) * 255 + 0.5)
}
