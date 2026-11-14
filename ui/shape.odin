package ui

import "core:math"

// AddRectFilled appends a filled rectangle, rounding each corner by its own radius.
AddRectFilled :: proc(List: ^DrawList, Rect: Rect, Tint: Color, CornerRadius: CornerRadius = {}) {
	path_rect(List, Rect, CornerRadius, Tint)
	path_fill_convex(List)
}

// AddRectStroke appends the outline of a rectangle, `Thickness` pixels wide.
AddRectStroke :: proc(List: ^DrawList, Rect: Rect, Tint: Color, Thickness: f32 = 1, CornerRadius: CornerRadius = {}) {
	path_rect(List, Rect, CornerRadius, Tint)
	path_stroke(List, Tint, Thickness)
}

// AddRectGradient appends a rectangle fading between its four corner colors.
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
	path_arc_to(List, Center, Radius, 0, math.TAU, Tint, Segments)
	path_fill_convex(List)
}

// AddCircleStroke appends a circle outline, `Thickness` pixels wide.
AddCircleStroke :: proc(List: ^DrawList, Center: Vec2, Radius: f32, Tint: Color, Thickness: f32 = 1, Segments: int = 0) {
	path_arc_to(List, Center, Radius, 0, math.TAU, Tint, Segments)
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

// AddTriangleStroke appends the outline of a triangle, `Thickness` pixels wide.
AddTriangleStroke :: proc(List: ^DrawList, A, B, C: Vec2, Tint: Color, Thickness: f32 = 1) {
	path_line_to(List, A, Tint)
	path_line_to(List, B, Tint)
	path_line_to(List, C, Tint)
	path_stroke(List, Tint, Thickness)
}

// AddLine appends a line segment `Thickness` wide.
AddLine :: proc(List: ^DrawList, A, B: Vec2, Tint: Color, Thickness: f32 = 1) {
	path_line_to(List, A, Tint)
	path_line_to(List, B, Tint)
	path_stroke(List, Tint, Thickness, Closed = false)
}

// AddPolygonFilled appends a filled convex polygon.
AddPolygonFilled :: proc(List: ^DrawList, Points: []Vec2, Tint: Color) {
	for p in Points do path_line_to(List, p, Tint)
	path_fill_convex(List)
}

// AddPolygonStroke appends the outline of a polygon through `Points`. Pass
// `Closed = false` to trace an open polyline instead.
AddPolygonStroke :: proc(List: ^DrawList, Points: []Vec2, Tint: Color, Thickness: f32 = 1, Closed: bool = true) {
	for p in Points do path_line_to(List, p, Tint)
	path_stroke(List, Tint, Thickness, Closed)
}

// AddRegularPolygonFilled appends a filled regular polygon with `Sides` sides, starting
// at angle `Start` radians.
AddRegularPolygonFilled :: proc(List: ^DrawList, Center: Vec2, Sides: int, Radius: f32, Tint: Color, Start: f32 = 0) {
	points: [MAX_POLYGON_SIDES]Vec2
	p := regular_polygon(points[:], Sides, Center, Radius, Start)
	if len(p) == 0 do return
	AddPolygonFilled(List, p, Tint)
}

// AddRegularPolygonStroke appends the outline of a regular polygon with `Sides` sides,
// `Thickness` pixels wide.
AddRegularPolygonStroke :: proc(
	List: ^DrawList,
	Center: Vec2,
	Sides: int,
	Radius: f32,
	Tint: Color,
	Thickness: f32 = 1,
	Start: f32 = 0,
) {
	points: [MAX_POLYGON_SIDES]Vec2
	p := regular_polygon(points[:], Sides, Center, Radius, Start)
	if len(p) == 0 do return
	AddPolygonStroke(List, p, Tint, Thickness)
}

// AddImage appends a quad that samples the `UV0`..`UV1` region of `Texture` over `Rect`,
// tinted by `Tint`.
AddImage :: proc(
	List:    ^DrawList,
	Rect:    Rect,
	Texture: Texture,
	Tint:    Color,
	UV0:     Vec2 = {0, 0},
	UV1:     Vec2 = {1, 1},
) {
	previous := List.texture
	List.texture = Texture
	append_quad(List, Rect.x, Rect.y, Rect.x + Rect.w, Rect.y + Rect.h, UV0, UV1, Tint)
	List.texture = previous
}

// MAX_POLYGON_SIDES is the largest polygon the regular shape helpers build.
@(private="file")
MAX_POLYGON_SIDES :: 64

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

// path_arc_to appends the points of an arc around `Center`, from `A0` to `A1` radians.
// `Segments` of zero picks a count from the radius and the sweep.
@(private="file")
path_arc_to :: proc(List: ^DrawList, Center: Vec2, Radius: f32, A0, A1: f32, Tint: Color, Segments: int = 0) {
	if Radius <= 0 do return

	n := Segments
	if n <= 0 {
		per_turn := clamp(int(Radius) + 8, 12, 96)
		n = clamp(int(f32(per_turn) * abs(A1 - A0) / math.TAU), 2, 96)
	}

	for i in 0 ..= n {
		angle := A0 + (A1 - A0) * f32(i) / f32(n)
		path_line_to(List, {Center.x + math.cos(angle) * Radius, Center.y + math.sin(angle) * Radius}, Tint)
	}
}

// path_corner appends an arc when the corner rounds, or the corner point itself when it
// does not.
@(private="file")
path_corner :: proc(List: ^DrawList, Center, Corner: Vec2, Radius: f32, A0, A1: f32, Tint: Color) {
	if Radius > 0 {
		path_arc_to(List, Center, Radius, A0, A1, Tint)
	} else {
		path_line_to(List, Corner, Tint)
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

// path_fill_convex fills the path as a fan from its first point, then clears it. The path
// must be convex.
@(private="file")
path_fill_convex :: proc(List: ^DrawList) {
	n := len(List.path)
	if n >= 3 {
		uv := use_atlas(List)
		start := len(List.indices)
		vtx := u32(len(List.vertices))

		for p in List.path do append(&List.vertices, Vertex{Pos = p.pos, UV = uv, Color = p.col})
		for i in 1 ..< n - 1 {
			append(&List.indices, vtx)
			append(&List.indices, vtx + u32(i))
			append(&List.indices, vtx + u32(i + 1))
		}

		mesh_command(List, u32(len(List.indices) - start))
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
	start := len(List.indices)

	for i in 0 ..< edges {
		a := List.path[i]
		b := List.path[(i + 1) % n]

		d := b.pos - a.pos
		length := math.sqrt(d.x * d.x + d.y * d.y)
		if length <= 0 do continue

		if Closed || i > 0 {
			add_bevel(List, List.path[(i - 1 + n) % n], a, b, half, Tint, uv)
		}

		normal := Vec2{-d.y / length * half, d.x / length * half}
		append_band(
			List,
			{a.pos + normal, Tint},
			{b.pos + normal, Tint},
			{b.pos - normal, Tint},
			{a.pos - normal, Tint},
			uv,
		)
	}

	if count := len(List.indices) - start; count > 0 do mesh_command(List, u32(count))
	path_clear(List)
}

// add_bevel fills the wedge outside `At`, between the edges into it and out of it. It is
// the cheapest join and leaves a flat corner.
@(private="file")
add_bevel :: proc(List: ^DrawList, Prev, At, Next: PathPoint, Half: f32, Tint: Color, UV: Vec2) {
	din := At.pos - Prev.pos
	dout := Next.pos - At.pos
	din_len := math.sqrt(din.x * din.x + din.y * din.y)
	dout_len := math.sqrt(dout.x * dout.x + dout.y * dout.y)
	if din_len <= 0 || dout_len <= 0 do return

	cross := din.x * dout.y - din.y * dout.x
	if cross == 0 do return

	din_n := Vec2{-din.y, din.x} / din_len * Half
	dout_n := Vec2{-dout.y, dout.x} / dout_len * Half
	side: f32 = 1
	if cross > 0 do side = -1

	append_triangle(List, {At.pos + din_n * side, Tint}, {At.pos + dout_n * side, Tint}, {At.pos, Tint}, UV)
}

// regular_polygon fills `out` with the vertices of a regular polygon of `Sides` sides and
// returns the slice it filled, or nothing when `Sides` is below three.
@(private="file")
regular_polygon :: proc(out: []Vec2, Sides: int, Center: Vec2, Radius: f32, Start: f32) -> []Vec2 {
	if Sides < 3 do return nil
	n := min(Sides, MAX_POLYGON_SIDES)

	step := math.TAU / f32(n)
	for _, i in out[:n] {
		angle := Start + f32(i) * step
		out[i] = {Center.x + math.cos(angle) * Radius, Center.y + math.sin(angle) * Radius}
	}
	return out[:n]
}

// use_atlas points the list at the atlas and returns the coordinate of its white texel, so
// a solid fill shares the batch with the text around it.
@(private="file")
use_atlas :: #force_inline proc(List: ^DrawList) -> Vec2 {
	List.texture = atlas_texture
	return {0.5 / f32(font_ctx.width), 0.5 / f32(font_ctx.height)}
}

// append_triangle writes one colored triangle sampling the atlas white texel. The caller
// closes the command.
@(private="file")
append_triangle :: proc(List: ^DrawList, A, B, C: PathPoint, UV: Vec2) {
	vtx := u32(len(List.vertices))

	append(&List.vertices, Vertex{Pos = A.pos, UV = UV, Color = A.col})
	append(&List.vertices, Vertex{Pos = B.pos, UV = UV, Color = B.col})
	append(&List.vertices, Vertex{Pos = C.pos, UV = UV, Color = C.col})

	append(&List.indices, vtx + 0)
	append(&List.indices, vtx + 1)
	append(&List.indices, vtx + 2)
}

// append_band writes the two triangles of one quad from the four corners in order, so a
// stroke edge costs four vertices instead of six.
@(private="file")
append_band :: proc(List: ^DrawList, A, B, C, D: PathPoint, UV: Vec2) {
	vtx := u32(len(List.vertices))

	append(&List.vertices, Vertex{Pos = A.pos, UV = UV, Color = A.col})
	append(&List.vertices, Vertex{Pos = B.pos, UV = UV, Color = B.col})
	append(&List.vertices, Vertex{Pos = C.pos, UV = UV, Color = C.col})
	append(&List.vertices, Vertex{Pos = D.pos, UV = UV, Color = D.col})

	append(&List.indices, vtx + 0)
	append(&List.indices, vtx + 1)
	append(&List.indices, vtx + 2)
	append(&List.indices, vtx + 0)
	append(&List.indices, vtx + 2)
	append(&List.indices, vtx + 3)
}

// append_quad writes four vertices and six indices for a textured quad, and closes its own
// command.
@(private)
append_quad :: proc(List: ^DrawList, X0, Y0, X1, Y1: f32, UV0, UV1: Vec2, Tint: Color) {
	vtx := u32(len(List.vertices))

	append(&List.vertices, Vertex{Pos = {X0, Y0}, UV = {UV0.x, UV0.y}, Color = Tint})
	append(&List.vertices, Vertex{Pos = {X1, Y0}, UV = {UV1.x, UV0.y}, Color = Tint})
	append(&List.vertices, Vertex{Pos = {X1, Y1}, UV = {UV1.x, UV1.y}, Color = Tint})
	append(&List.vertices, Vertex{Pos = {X0, Y1}, UV = {UV0.x, UV1.y}, Color = Tint})

	append(&List.indices, vtx + 0)
	append(&List.indices, vtx + 1)
	append(&List.indices, vtx + 2)
	append(&List.indices, vtx + 0)
	append(&List.indices, vtx + 2)
	append(&List.indices, vtx + 3)

	mesh_command(List, 6)
}
