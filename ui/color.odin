package ui

import "core:math"

// Color is one RGBA color, one byte per channel.
Color :: [4]u8

// Hex returns the color of the 0xRRGGBB value `Rgb`, with `Alpha` as its alpha channel.
Hex :: #force_inline proc(Rgb: u32, Alpha: u8 = 255) -> Color {
	return {u8(Rgb >> 16), u8(Rgb >> 8), u8(Rgb), Alpha}
}

// HexA returns the color of the 0xRRGGBBAA value `Rgba`.
HexA :: #force_inline proc(Rgba: u32) -> Color {
	return {u8(Rgba >> 24), u8(Rgba >> 16), u8(Rgba >> 8), u8(Rgba)}
}

// Rgb returns the color of the `R`, `G` and `B` channels, with `Alpha` as its alpha channel.
Rgb :: #force_inline proc(R, G, B: u8, Alpha: u8 = 255) -> Color {
	return {R, G, B, Alpha}
}

// Hsv returns the color of `H` (hue in degrees), `S` (saturation) and `V` (value). The hue
// wraps into 0..360 and the saturation and value clamp to 0..1.
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

// blend returns the mix of `A` and `B` at `T`, where 0 is `A` and 1 is `B`.
@(private)
blend :: #force_inline proc(A, B: Color, T: f32) -> Color {
	t := clamp(T, 0, 1)
	return {
		u8(f32(A.r) + (f32(B.r) - f32(A.r)) * t),
		u8(f32(A.g) + (f32(B.g) - f32(A.g)) * t),
		u8(f32(A.b) + (f32(B.b) - f32(A.b)) * t),
		u8(f32(A.a) + (f32(B.a) - f32(A.a)) * t),
	}
}

// gradient_at returns the bilinear mix of the four corner colors at `P` inside `Rect`.
@(private)
gradient_at :: proc(P: Vec2, Rect: Rect, TopLeft, TopRight, BottomRight, BottomLeft: Color) -> Color {
	u: f32 = 0
	v: f32 = 0
	if Rect.w != 0 do u = (P.x - Rect.x) / Rect.w
	if Rect.h != 0 do v = (P.y - Rect.y) / Rect.h

	return blend(blend(TopLeft, TopRight, u), blend(BottomLeft, BottomRight, u), v)
}

// hsv_channel returns one channel of the HSV color: `N` picks both the channel (5 red, 3
// green, 1 blue) and its position around the color wheel. This is the CSS Color 4
// formulation, which needs no per-sector table.
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
