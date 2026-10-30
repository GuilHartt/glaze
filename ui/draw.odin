package ui

import "core:math"
import "vendor:fontstash"

// Vertex is one point of the frame's mesh: position in pixels, atlas coordinate
// and flat color. Color per vertex is what lets any shape carry a gradient.
Vertex :: struct #packed {
	Pos:   Vec2,
	UV:    Vec2,
	Color: Color,
}

// Texture is an opaque handle owned by the backend. The zero value means no
// texture, which is what the list starts a frame with.
Texture :: distinct rawptr

// DrawCommand is one draw call: a slice of the index buffer, drawn with one
// texture, clipped to one rect.
DrawCommand :: struct {
	Clip:    Rect,
	Texture: Texture,
	Offset:  u32,
	Count:   u32,
}

// PathPoint is one point of the path being built: where it is and the color it
// carries, which is what lets any shape fade from one color to another.
@(private="file")
PathPoint :: struct {
	pos: Vec2,
	col: Color,
}

// DrawList is the shape buffer of one frame. Shapes append in call order, so later
// calls paint over earlier ones.
DrawList :: struct {
	vertices:   [dynamic]Vertex,
	indices:    [dynamic]u32,
	commands:   [dynamic]DrawCommand,
	path:       [dynamic]PathPoint,
	clip_stack: [dynamic]Rect,
	clip:       Rect,
	texture:    Texture,
}

// DrawProc runs during the build pass, once the element's rect is known. It must
// only emit into `List`, never declare elements.
DrawProc :: #type proc(Rect: Rect, List: ^DrawList, User: rawptr)

// Frame is what a backend needs in order to draw one frame.
Frame :: struct {
	Vertices: []Vertex,
	Indices:  []u32,
	Commands: []DrawCommand,
}

@(private="file")
list: DrawList

// DrawData returns the mesh and draw commands of the last completed frame. The
// slices are only valid until the next call to Begin.
DrawData :: proc() -> Frame {
	return {list.vertices[:], list.indices[:], list.commands[:]}
}

// AddRectFilled appends one filled rectangle, rounding each corner by its own
// radius.
AddRectFilled :: proc(List: ^DrawList, Rect: Rect, Tint: Color, CornerRadius: CornerRadius = {}) {
	path_rect(List, Rect, CornerRadius, Tint)
	path_fill_convex(List)
}

// AddRect appends the outline of a rectangle, `Thickness` pixels wide.
AddRect :: proc(List: ^DrawList, Rect: Rect, Tint: Color, Thickness: f32 = 1, CornerRadius: CornerRadius = {}) {
	path_rect(List, Rect, CornerRadius, Tint)
	path_stroke(List, Tint, Thickness)
}

// AddRectGradient appends a rectangle fading between its four corner colors,
// rounding each corner by its own radius.
AddRectGradient :: proc(
	List: ^DrawList,
	Rect: Rect,
	TopLeft, TopRight, BottomRight, BottomLeft: Color,
	CornerRadius: CornerRadius = {},
) {
	path_rect(List, Rect, CornerRadius, TopLeft)
	for &p in List.path {
		p.col = gradient_at(p.pos, Rect, TopLeft, TopRight, BottomRight, BottomLeft)
	}
	path_fill_convex(List)
}

// AddCircleFilled appends a filled circle.
AddCircleFilled :: proc(List: ^DrawList, Center: Vec2, Radius: f32, Tint: Color, Segments: int = 0) {
	path_arc_to(List, Center, Radius, 0, 2 * math.PI, Tint, Segments)
	path_fill_convex(List)
}

// AddCircle appends a circle outline.
AddCircle :: proc(List: ^DrawList, Center: Vec2, Radius: f32, Tint: Color, Thickness: f32 = 1, Segments: int = 0) {
	path_arc_to(List, Center, Radius, 0, 2 * math.PI, Tint, Segments)
	path_stroke(List, Tint, Thickness)
}

// AddArc appends an arc outline from `A0` to `A1` radians.
AddArc :: proc(List: ^DrawList, Center: Vec2, Radius: f32, A0, A1: f32, Tint: Color, Thickness: f32 = 1, Segments: int = 0) {
	path_arc_to(List, Center, Radius, A0, A1, Tint, Segments)
	path_stroke(List, Tint, Thickness, Closed = false)
}

// AddTriangleFilled appends a filled triangle.
AddTriangleFilled :: proc(List: ^DrawList, A, B, C: Vec2, Tint: Color) {
	path_line_to(List, A, Tint)
	path_line_to(List, B, Tint)
	path_line_to(List, C, Tint)
	path_fill_convex(List)
}

// AddLine appends a line segment `Thickness` wide.
AddLine :: proc(List: ^DrawList, A, B: Vec2, Tint: Color, Thickness: f32 = 1) {
	path_line_to(List, A, Tint)
	path_line_to(List, B, Tint)
	path_stroke(List, Tint, Thickness, Closed = false)
}

// AddPolygon appends the outline of a polygon through `Points`, `Thickness` wide.
// Pass `Closed = false` to trace an open polyline instead.
AddPolygon :: proc(List: ^DrawList, Points: []Vec2, Tint: Color, Thickness: f32 = 1, Closed: bool = true) {
	for p in Points do path_line_to(List, p, Tint)
	path_stroke(List, Tint, Thickness, Closed)
}

// AddPolygonFilled appends a filled convex polygon.
AddPolygonFilled :: proc(List: ^DrawList, Points: []Vec2, Tint: Color) {
	for p in Points do path_line_to(List, p, Tint)
	path_fill_convex(List)
}

// AddText appends `Text` with its top left corner at `Pos`.
AddText :: proc(List: ^DrawList, Pos: Vec2, Text: cstring, Tint: Color, Font: Font = 0, Size: f32 = 16) {
	if Text == nil || len(font_ctx.fonts) == 0 || Size <= 0 do return

	fontstash.SetFont(&font_ctx, int(Font))
	fontstash.SetSize(&font_ctx, Size)
	fontstash.SetAV(&font_ctx, .TOP)
	fontstash.SetAH(&font_ctx, .LEFT)

	previous := List.texture
	List.texture = atlas_texture

	iter := fontstash.TextIterInit(&font_ctx, Pos.x, Pos.y, string(Text))
	quad: fontstash.Quad
	for fontstash.TextIterNext(&font_ctx, &iter, &quad) {
		append_quad(List, quad.x0, quad.y0, quad.x1, quad.y1, {quad.s0, quad.t0}, {quad.s1, quad.t1}, Tint)
	}

	List.texture = previous
}

// PushClipRect narrows the visible area to `Rect` for everything appended after
// it. The new clip is the overlap with the current one, so nesting only ever
// shrinks it.
PushClipRect :: proc(List: ^DrawList, Rect: Rect) {
	append(&List.clip_stack, List.clip)
	List.clip = RectIntersect(List.clip, Rect)
}

// PopClipRect restores the clip saved by the matching PushClipRect.
PopClipRect :: proc(List: ^DrawList) {
	assert(len(List.clip_stack) > 0, "PopClipRect without a matching PushClipRect")
	List.clip = pop(&List.clip_stack)
}

// path_clear drops the points accumulated so far.
@(private="file")
path_clear :: proc(List: ^DrawList) {
	clear(&List.path)
}

// path_line_to appends `P` to the path, carrying `Tint`.
@(private="file")
path_line_to :: proc(List: ^DrawList, P: Vec2, Tint: Color) {
	append(&List.path, PathPoint{pos = P, col = Tint})
}

// path_arc_to appends the points of the arc around `Center`, from `A0` to `A1`
// radians. `Segments` of zero picks a count from the radius and the sweep.
@(private="file")
path_arc_to :: proc(List: ^DrawList, Center: Vec2, Radius: f32, A0, A1: f32, Tint: Color, Segments: int = 0) {
	if Radius <= 0 do return

	n := Segments
	if n <= 0 {
		full := clamp(int(Radius) + 8, 12, 96)
		n = clamp(int(f32(full) * abs(A1 - A0) / (2 * math.PI)), 2, 96)
	}

	for i in 0 ..= n {
		angle := A0 + (A1 - A0) * f32(i) / f32(n)
		path_line_to(List, {Center.x + math.cos(angle) * Radius, Center.y + math.sin(angle) * Radius}, Tint)
	}
}

// path_rect appends a rectangle, rounding each corner by its own radius.
@(private="file")
path_rect :: proc(List: ^DrawList, Rect: Rect, CornerRadius: CornerRadius, Tint: Color) {
	limit := min(Rect.w, Rect.h) / 2
	tl := clamp(CornerRadius.TopLeft, 0, limit)
	tr := clamp(CornerRadius.TopRight, 0, limit)
	br := clamp(CornerRadius.BottomRight, 0, limit)
	bl := clamp(CornerRadius.BottomLeft, 0, limit)

	x0, y0 := Rect.x, Rect.y
	x1, y1 := Rect.x + Rect.w, Rect.y + Rect.h
	half_pi: f32 = math.PI / 2

	path_corner(List, {x0 + tl, y0 + tl}, {x0, y0}, tl, half_pi * 2, half_pi * 3, Tint)
	path_corner(List, {x1 - tr, y0 + tr}, {x1, y0}, tr, half_pi * 3, half_pi * 4, Tint)
	path_corner(List, {x1 - br, y1 - br}, {x1, y1}, br, 0, half_pi, Tint)
	path_corner(List, {x0 + bl, y1 - bl}, {x0, y1}, bl, half_pi, half_pi * 2, Tint)
}

// path_fill_convex fills the path as a fan from its first point, then clears it. The
// path must be convex.
@(private="file")
path_fill_convex :: proc(List: ^DrawList) {
	n := len(List.path)
	if n >= 3 {
		uv := use_atlas(List)
		first := List.path[0]
		for i in 1 ..< n - 1 {
			append_triangle(List, first, List.path[i], List.path[i + 1], uv)
		}
	}
	path_clear(List)
}

// path_stroke traces the path as a band `Thickness` wide, then clears it.
@(private="file")
path_stroke :: proc(List: ^DrawList, Tint: Color, Thickness: f32 = 1, Closed: bool = true) {
	n := len(List.path)
	if n < 2 || Thickness <= 0 {
		path_clear(List)
		return
	}

	uv := use_atlas(List)
	half := Thickness / 2
	edges := n if Closed else n - 1

	for i in 0 ..< edges {
		a := List.path[i]
		b := List.path[(i + 1) % n]

		d := b.pos - a.pos
		length := math.sqrt(d.x * d.x + d.y * d.y)
		if length <= 0 do continue

		normal := Vec2{-d.y / length * half, d.x / length * half}
		append_triangle(List, {a.pos + normal, Tint}, {b.pos + normal, Tint}, {b.pos - normal, Tint}, uv)
		append_triangle(List, {a.pos + normal, Tint}, {b.pos - normal, Tint}, {a.pos - normal, Tint}, uv)
	}

	path_clear(List)
}

// draw_begin_frame clears the list and resets its clip and texture.
@(private)
draw_begin_frame :: proc() {
	clear(&list.vertices)
	clear(&list.indices)
	clear(&list.commands)
	clear(&list.path)
	clear(&list.clip_stack)
	list.clip = {0, 0, state.root_size.x, state.root_size.y}
	list.texture = nil
}

// draw_build walks the tree in paint order, starting from the implicit root.
@(private)
draw_build :: proc() {
	draw_node(0)
}

// draw_node emits node i and then its subtree. A node that clips pushes its inner
// rect before its content and children, so everything inside is cut to it, nesting
// as deep as the tree asks.
@(private="file")
draw_node :: proc(i: u32) #no_bounds_check {
	n := &state.nodes[i]

	corners := n.style.CornerRadius
	if n.style.Background.a != 0 {
		AddRectFilled(&list, n.rect, n.style.Background, corners)
	}
	if n.style.Border.Width > 0 {
		AddRect(&list, n.rect, n.style.Border.Color, n.style.Border.Width, corners)
	}

	clip := n.config.Clip || n.config.Scroll != {}
	if clip do PushClipRect(&list, inner_rect(n, n.rect))

	#partial switch content in n.content {
	case TextContent:
		AddText(&list, {n.rect.x, n.rect.y}, content.text, content.config.Color, content.font, content.config.Size)
	}

	if n.draw != nil do n.draw(n.rect, &list, n.draw_user)

	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		draw_node(c)
	}

	if clip do PopClipRect(&list)
	if n.style.ScrollBar do draw_scrollbar(i)
}

// draw_scrollbar draws the bar of node i on every axis that overflows. The thumb is
// proportional to how much of the content fits, and it is drawn after the clip is
// popped so its own container never cuts it.
@(private="file")
draw_scrollbar :: proc(i: u32) #no_bounds_check {
	THICKNESS :: f32(6)
	TRACK :: Color{255, 255, 255, 30}
	THUMB :: Color{255, 255, 255, 90}

	n := &state.nodes[i]
	view := inner_rect(n, n.rect)
	content := intrinsic_size(i)
	scroll := ScrollOffset(n.id)

	if .Vertical in n.config.Scroll && content.y > view.h {
		track := Rect{view.x + view.w - THICKNESS, view.y, THICKNESS, view.h}
		length := max(track.h * view.h / content.y, THICKNESS * 2)
		at := track.y + (track.h - length) * scroll.y / (content.y - view.h)
		AddRectFilled(&list, track, TRACK, Corners(THICKNESS / 2))
		AddRectFilled(&list, {track.x, at, track.w, length}, THUMB, Corners(THICKNESS / 2))
	}
	if .Horizontal in n.config.Scroll && content.x > view.w {
		track := Rect{view.x, view.y + view.h - THICKNESS, view.w, THICKNESS}
		length := max(track.w * view.w / content.x, THICKNESS * 2)
		at := track.x + (track.w - length) * scroll.x / (content.x - view.w)
		AddRectFilled(&list, track, TRACK, Corners(THICKNESS / 2))
		AddRectFilled(&list, {at, track.y, length, track.h}, THUMB, Corners(THICKNESS / 2))
	}
}


// mesh_reserve makes room for `Vtx` vertices and `Idx` indices and returns where
// each block starts.
@(private="file")
mesh_reserve :: proc(List: ^DrawList, Vtx, Idx: int) -> (vtx, idx: u32) {
	vtx = u32(len(List.vertices))
	idx = u32(len(List.indices))
	if Vtx > 0 do resize(&List.vertices, len(List.vertices) + Vtx)
	if Idx > 0 do resize(&List.indices, len(List.indices) + Idx)
	return
}

// mesh_vertex writes one vertex at the absolute position `I`.
@(private="file")
mesh_vertex :: #force_inline proc(List: ^DrawList, I: u32, Pos, UV: Vec2, Tint: Color) {
	List.vertices[I] = {Pos = Pos, UV = UV, Color = Tint}
}

// mesh_index writes one index at the absolute position `I`.
@(private="file")
mesh_index :: #force_inline proc(List: ^DrawList, I, V: u32) {
	List.indices[I] = V
}

// mesh_command grows the last draw command when it still matches, or opens a new
// one covering the indices just written.
@(private="file")
mesh_command :: proc(List: ^DrawList, Count: u32) {
	if len(List.commands) > 0 {
		last := &List.commands[len(List.commands) - 1]
		if last.Texture == List.texture && last.Clip == List.clip {
			last.Count += Count
			return
		}
	}
	append(&List.commands, DrawCommand{
		Clip    = List.clip,
		Texture = List.texture,
		Offset  = u32(len(List.indices)) - Count,
		Count   = Count,
	})
}

// use_atlas points the list at the font atlas and returns the atlas coordinate of
// its white texel, so a solid fill lands in the same draw call as the text around
// it. The coordinate is the center of the first texel, which the atlas reserves as
// white; the texel corner would land on a filter boundary.
@(private="file")
use_atlas :: #force_inline proc(List: ^DrawList) -> Vec2 {
	List.texture = atlas_texture
	return {0.5 / f32(font_ctx.width), 0.5 / f32(font_ctx.height)}
}

// path_corner appends an arc when the corner rounds, or the corner point itself
// when it does not.
@(private="file")
path_corner :: proc(List: ^DrawList, Center, Corner: Vec2, Radius: f32, A0, A1: f32, Tint: Color) {
	if Radius > 0 {
		path_arc_to(List, Center, Radius, A0, A1, Tint)
	} else {
		path_line_to(List, Corner, Tint)
	}
}

// lerp_color mixes `A` and `B` by `T`, clamped to 0..1.
@(private="file")
lerp_color :: #force_inline proc "contextless" (A, B: Color, T: f32) -> Color {
	t := clamp(T, 0, 1)
	return {
		u8(f32(A.r) + (f32(B.r) - f32(A.r)) * t),
		u8(f32(A.g) + (f32(B.g) - f32(A.g)) * t),
		u8(f32(A.b) + (f32(B.b) - f32(A.b)) * t),
		u8(f32(A.a) + (f32(B.a) - f32(A.a)) * t),
	}
}

// gradient_at returns the bilinear mix of the four corner colors at `P` inside
// `Rect`.
@(private="file")
gradient_at :: proc(P: Vec2, Rect: Rect, TopLeft, TopRight, BottomRight, BottomLeft: Color) -> Color {
	u: f32 = 0
	v: f32 = 0
	if Rect.w != 0 do u = (P.x - Rect.x) / Rect.w
	if Rect.h != 0 do v = (P.y - Rect.y) / Rect.h

	return lerp_color(lerp_color(TopLeft, TopRight, u), lerp_color(BottomLeft, BottomRight, u), v)
}

// append_triangle writes one colored triangle sampling the atlas white texel, so it
// shares the batch with everything else.
@(private="file")
append_triangle :: proc(List: ^DrawList, A, B, C: PathPoint, UV: Vec2) {
	vtx, idx := mesh_reserve(List, 3, 3)
	mesh_vertex(List, vtx + 0, A.pos, UV, A.col)
	mesh_vertex(List, vtx + 1, B.pos, UV, B.col)
	mesh_vertex(List, vtx + 2, C.pos, UV, C.col)
	mesh_index(List, idx + 0, vtx + 0)
	mesh_index(List, idx + 1, vtx + 1)
	mesh_index(List, idx + 2, vtx + 2)
	mesh_command(List, 3)
}

// append_quad writes four vertices and six indices for a textured quad.
@(private="file")
append_quad :: proc(List: ^DrawList, X0, Y0, X1, Y1: f32, UV0, UV1: Vec2, Tint: Color) {
	vtx, idx := mesh_reserve(List, 4, 6)

	mesh_vertex(List, vtx + 0, {X0, Y0}, {UV0.x, UV0.y}, Tint)
	mesh_vertex(List, vtx + 1, {X1, Y0}, {UV1.x, UV0.y}, Tint)
	mesh_vertex(List, vtx + 2, {X1, Y1}, {UV1.x, UV1.y}, Tint)
	mesh_vertex(List, vtx + 3, {X0, Y1}, {UV0.x, UV1.y}, Tint)

	mesh_index(List, idx + 0, vtx + 0)
	mesh_index(List, idx + 1, vtx + 1)
	mesh_index(List, idx + 2, vtx + 2)
	mesh_index(List, idx + 3, vtx + 0)
	mesh_index(List, idx + 4, vtx + 2)
	mesh_index(List, idx + 5, vtx + 3)

	mesh_command(List, 6)
}
