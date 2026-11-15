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

// Edges is one length per side of a box. It serves as padding and as the thickness of a
// border, since both measure the four sides the same way.
Edges :: struct {Left, Right, Top, Bottom: f32}

// SizeKind is how a sizing treats its `Basis`.
SizeKind :: enum u8 { Fit, Fixed }

// Sizing is one axis of an element's size: a base from `Kind` and `Basis`, how it takes a
// share of the parent's leftover space, and its bounds.
Sizing :: struct {
	Kind:   SizeKind,
	Basis:  f32,
	Grow:   f32,
	Shrink: f32,
	Min:    f32,
	Max:    f32,
}

// CornerRadius holds the radius of each corner, so one rectangle rounds them independently.
CornerRadius :: struct {
	TopLeft, TopRight, BottomRight, BottomLeft: f32,
}

// Gradient holds four corner colors: top left, top right, bottom right, bottom left.
Gradient :: [4]Color

// Background is how a box fills its rect: one flat color, or a gradient. Any corner radius
// survives, since the gradient samples the position inside the rect, not the corners.
Background :: union {
	Color,
	Gradient,
}

// Style is how a box paints itself. Any element carries one, leaf or container. Equal border
// sides keep the corner radius; sides that differ are painted as plain edges.
Style :: struct {
	Background:   Background,
	CornerRadius: CornerRadius,
	BorderColor:  Color,
	BorderWidth:  Edges,
}

// HitMode is how an element answers the pointer. `Ignore` hides it and its subtree, `Pass`
// observes but never owns, `Stop` owns the whole box, and `Auto` owns when no `Stop` is above.
HitMode :: enum u8 {
	Auto,
	Stop,
	Pass,
	Ignore,
}

// LayoutConfig is how an element is sized, how it places its children and how it answers the
// pointer. `Hit` decides whether the element is seen, observes or owns the press.
LayoutConfig :: struct {
	Width:   Sizing,
	Height:  Sizing,
	Pad:     Edges,
	Gap:     f32,
	Justify: Justify,
	Align:   Align,
	Clip:    bool,
	Scroll:  Scroll,
	Hit:     HitMode,
}

// WrapMode is how a label breaks its text. Both modes break at the newlines the text has;
// `Word` also breaks between words when a line does not fit the width it was given.
WrapMode :: enum u8 { None, Word }

// TextAlign places each line inside the width the label ended up with.
TextAlign :: enum u8 { Left, Center, Right }

// ImageFit is how an image fills the rect it was given.
ImageFit :: enum u8 {
	Stretch,
	Contain,
	Cover,
}

// ImageConfig is how an image leaf paints. `Tint` multiplies the texture and `Fit` is how
// it fills the rect.
ImageConfig :: struct {
	Tint: Color,
	Fit:  ImageFit,
}

// Corners returns a corner radius with `All` on every corner.
Corners :: #force_inline proc "contextless" (All: f32) -> CornerRadius {
	return {TopLeft = All, TopRight = All, BottomRight = All, BottomLeft = All}
}

// Edge builds an Edges: Edge(All) puts `All` on every side, Edge(X, Y) puts `X` on the left
// and right and `Y` on the top and bottom. A bare `Edges` literal names the sides.
Edge :: proc{edge_all, edge_xy}

// edge_all returns the edges with `All` on every side.
@(private="file")
edge_all :: #force_inline proc(All: f32) -> Edges {
	return {Left = All, Right = All, Top = All, Bottom = All}
}

// edge_xy returns the edges with `X` on the left and right and `Y` on the top and bottom.
@(private="file")
edge_xy :: #force_inline proc(X, Y: f32) -> Edges {
	return {Left = X, Right = X, Top = Y, Bottom = Y}
}

// Grow returns a sizing whose base is the content size, expanding to take a
// `Weight`-proportional share of the parent's leftover space.
Grow :: #force_inline proc "contextless" (Weight: f32 = 1, Shrink: f32 = 1) -> Sizing {
	return {Kind = .Fit, Grow = Weight, Shrink = Shrink}
}

// Fill returns a sizing whose base is zero and that divides the parent's space by `Weight`,
// ignoring content. Use it for equal-sized children.
Fill :: #force_inline proc "contextless" (Weight: f32 = 1, Shrink: f32 = 1) -> Sizing {
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
