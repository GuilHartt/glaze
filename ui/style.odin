package ui

// Justify spreads the children along the container's main axis.
Justify :: enum u8 {
	Start,
	Center,
	End,
	SpaceBetween,
}

// Align places the children along the container's cross axis.
Align :: enum u8 {
	Start,
	Center,
	End,
	Stretch,
}

// Padding holds the space inside a box, on each side.
Padding :: struct {Left, Right, Top, Bottom: f32}

// SizeKind is how a sizing treats its `Basis`.
SizeKind :: enum u8 { Fit, Fixed }

// Sizing is one axis of an element's size: a base from `Kind` and `Basis`, how it
// takes a share of the parent's leftover space, and its bounds.
Sizing :: struct {
	Kind:   SizeKind,
	Basis:  f32,
	Grow:   f32,
	Shrink: f32,
	Min:    f32,
	Max:    f32,
}

// CornerRadius holds the radius of each corner, so one rectangle can round its
// corners independently.
CornerRadius :: struct {
	TopLeft, TopRight, BottomRight, BottomLeft: f32,
}

// Border is the outline of a box.
Border :: struct {
	Color: Color,
	Width: f32,
}

// Style is how a box paints itself. Only containers carry one.
Style :: struct {
	Background:   Color,
	CornerRadius: CornerRadius,
	Border:       Border,
	ScrollBar:    bool,
}

// ScrollAxis is one axis a box can scroll along.
ScrollAxis :: enum u8 { Horizontal, Vertical }

// Scroll is the set of axes a box scrolls along. A scrolling axis is clipped and
// its content can move inside the box.
Scroll :: bit_set[ScrollAxis]

// LayoutConfig is how an element is sized and how it places its children. A
// container with `Hit` claims every hit inside its rect, including the padding
// and the parts its children paint over.
LayoutConfig :: struct {
	Width:   Sizing,
	Height:  Sizing,
	Pad:     Padding,
	Gap:     f32,
	Justify: Justify,
	Align:   Align,
	Clip:    bool,
	Scroll:  Scroll,
	Hit:     bool,
}

// TextConfig is how a text leaf paints.
TextConfig :: struct {
	Color: Color,
	Size:  f32,
}

// ImageConfig is how an image leaf paints.
ImageConfig :: struct {
	Size: Vec2,
	Tint: Color,
}

// Corners returns a corner radius with `All` on every corner.
Corners :: #force_inline proc "contextless" (All: f32) -> CornerRadius {
	return {TopLeft = All, TopRight = All, BottomRight = All, BottomLeft = All}
}

// Pad builds a Padding: Pad(All) puts `All` on every side, Pad(X, Y) puts `X` on
// the left and right and `Y` on the top and bottom.
Pad :: proc{pad_all, pad_xy}

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
