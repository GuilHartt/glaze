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

// AddRectGradient appends a rectangle fading across its four corner colors.
AddRectGradient :: proc(
	List: ^DrawList,
	Rect: Rect,
	Colors: Gradient,
	CornerRadius: CornerRadius = {},
) {
	path_rect(List, Rect, CornerRadius, Colors[0])
	path_gradient(List, Rect, Colors)
	path_fill_convex(List)
}

// AddCircleGradient appends a filled circle fading across `Colors`, sampled over the box
// that encloses it.
AddCircleGradient :: proc(
	List: ^DrawList,
	Center: Vec2,
	Radius: f32,
	Colors: Gradient,
	Segments: int = 0,
) {
	path_arc_to(List, Center, Radius, 0, math.TAU, Colors[0], Segments)
	path_gradient(List, {Center.x - Radius, Center.y - Radius, Radius * 2, Radius * 2}, Colors)
	path_fill_convex(List)
}

// AddTriangleGradient appends a filled triangle fading across `Colors`, sampled over the box
// that encloses its three points.
AddTriangleGradient :: proc(List: ^DrawList, A, B, C: Vec2, Colors: Gradient) {
	path_line_to(List, A, Colors[0])
	path_line_to(List, B, Colors[0])
	path_line_to(List, C, Colors[0])
	points := [3]Vec2{A, B, C}
	path_gradient(List, points_box(points[:]), Colors)
	path_fill_convex(List)
}

// AddPolygonGradient appends a filled convex polygon fading across `Colors`, sampled over the
// box that encloses its points.
AddPolygonGradient :: proc(List: ^DrawList, Points: []Vec2, Colors: Gradient) {
	for p in Points do path_line_to(List, p, Colors[0])
	path_gradient(List, points_box(Points), Colors)
	path_fill_convex(List)
}

// AddRegularPolygonGradient appends a filled regular polygon with `Sides` sides, fading across
// `Colors` over the box that encloses it.
AddRegularPolygonGradient :: proc(
	List: ^DrawList,
	Center: Vec2,
	Sides: int,
	Radius: f32,
	Colors: Gradient,
	Start: f32 = 0,
) {
	points: [MAX_POLYGON_SIDES]Vec2
	p := regular_polygon(points[:], Sides, Center, Radius, Start)
	if len(p) == 0 do return
	AddPolygonGradient(List, p, Colors)
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

// AddImageGradient appends a quad that samples the `UV0`..`UV1` region of `Texture` over
// `Rect`, fading across `Colors`.
AddImageGradient :: proc(
	List:    ^DrawList,
	Rect:    Rect,
	Texture: Texture,
	Colors:  Gradient,
	UV0:     Vec2 = {0, 0},
	UV1:     Vec2 = {1, 1},
) {
	previous := List.texture
	List.texture = Texture
	append_quad_gradient(List, Rect, UV0, UV1, Colors)
	List.texture = previous
}

// MAX_POLYGON_SIDES is the largest polygon the regular shape helpers build.
@(private="file")
MAX_POLYGON_SIDES :: 64

// ARC_SEGMENT_MAX caps how finely an arc is split, and ARC_ERROR is how far, in pixels, a chord
// may sit from the arc it approximates.
@(private="file")
ARC_SEGMENT_MAX :: 96

@(private="file")
ARC_ERROR :: 0.10

// path_gradient samples `Colors` at every point of the path, over `Box`.
@(private="file")
path_gradient :: proc(List: ^DrawList, Box: Rect, Colors: Gradient) {
	for &p in List.path {
		p.col = gradient_at(p.pos, Box, Colors[0], Colors[1], Colors[2], Colors[3])
	}
}

// points_box returns the smallest rect that encloses `Points`.
@(private="file")
points_box :: proc(Points: []Vec2) -> Rect {
	if len(Points) == 0 do return {}
	lo, hi := Points[0], Points[0]
	for p in Points[1:] {
		lo = {min(lo.x, p.x), min(lo.y, p.y)}
		hi = {max(hi.x, p.x), max(hi.y, p.y)}
	}
	return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
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

// arc_segments returns how many segments hold `Sweep` radians of `Radius` within ARC_ERROR
// pixels. A chord leaves a sagitta of radius * (1 - cos(step / 2)), so the step that keeps it
// at the error is 2 * acos(1 - error / radius).
@(private="file")
arc_segments :: proc(List: ^DrawList, Radius, Sweep: f32) -> int {
	pixels := Radius / max(List.fringe, 0.0001)
	if pixels <= ARC_ERROR do return 2
	step := 2 * math.acos(1 - ARC_ERROR / pixels)
	return clamp(int(math.ceil(abs(Sweep) / step)), 2, ARC_SEGMENT_MAX)
}

// path_arc_to appends the points of an arc around `Center`, from `A0` to `A1` radians.
// `Segments` of zero picks a count from the error ARC_ERROR allows.
@(private="file")
path_arc_to :: proc(List: ^DrawList, Center: Vec2, Radius: f32, A0, A1: f32, Tint: Color, Segments: int = 0) {
	if Radius <= 0 do return

	n := Segments
	if n <= 0 do n = arc_segments(List, Radius, A1 - A0)

	// Step by rotating the radius vector, so the whole arc costs two sines and two cosines.
	step := (A1 - A0) / f32(n)
	c, s := math.cos(step), math.sin(step)
	x, y := math.cos(A0) * Radius, math.sin(A0) * Radius

	reserve(&List.path, len(List.path) + n + 1)
	for _ in 0 ..= n {
		append(&List.path, PathPoint{pos = {Center.x + x, Center.y + y}, col = Tint})
		x, y = x * c - y * s, x * s + y * c
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

// MITER_LIMIT is how far a joint may stretch past its point before the corner is cut short, and
// MITER_MIN keeps the miter division finite on a doubled-back path.
@(private="file")
MITER_LIMIT :: 4

@(private="file")
MITER_MIN :: 0.0001

// edge_normal returns the outward unit normal of the edge from `A` to `B`, for a path that winds
// clockwise on a y-down screen. It is zero when the two points coincide.
@(private="file")
edge_normal :: #force_inline proc(A, B: Vec2) -> Vec2 {
	d := B - A
	length := math.sqrt(d.x * d.x + d.y * d.y)
	if length <= 0 do return {}
	return {d.y / length, -d.x / length}
}

// path_miter_normals fills `offsets` with the outward normal of every point, so a stroke edge and
// a fill rim offset the path once instead of per edge. A sharp corner clamps the miter, so it
// never spikes out of the shape.
@(private="file")
path_miter_normals :: proc(List: ^DrawList, Closed: bool) {
	n := len(List.path)
	clear(&List.offsets)
	reserve(&List.offsets, n)

	for i in 0 ..< n {
		prev := (i - 1 + n) % n
		next := (i + 1) % n

		first_edge := Closed || i > 0
		last_edge := Closed || i < n - 1

		n_in, n_out: Vec2
		if first_edge do n_in = edge_normal(List.path[prev].pos, List.path[i].pos)
		if last_edge do n_out = edge_normal(List.path[i].pos, List.path[next].pos)
		if !first_edge do n_in = n_out
		if !last_edge do n_out = n_in

		s := n_in + n_out
		d := 1 + n_in.x * n_out.x + n_in.y * n_out.y
		if d < MITER_MIN do d = MITER_MIN
		m := s / d

		length := math.sqrt(m.x * m.x + m.y * m.y)
		if length > MITER_LIMIT do m = m * (MITER_LIMIT / length)
		append(&List.offsets, m)
	}
}

// quad_indices appends the two triangles of a quad from its four corners in order.
@(private="file")
quad_indices :: #force_inline proc(List: ^DrawList, A, B, C, D: u32) {
	append(&List.indices, A, B, C, A, C, D)
}

// path_fill_convex fills the path as a fan from its first point, then clears it. The path must
// be convex. With antialiasing on, a ring of transparent vertices wraps the fill, so the edge
// blends instead of stair-stepping and neighbouring fills still meet with no seam.
@(private="file")
path_fill_convex :: proc(List: ^DrawList) {
	n := len(List.path)
	if n < 3 {
		path_clear(List)
		return
	}

	uv := use_atlas(List)
	start := len(List.indices)
	base := u32(len(List.vertices))
	feather: f32
	if List.antialias do feather = List.fringe

	if feather <= 0 {
		reserve(&List.vertices, len(List.vertices) + n)
		reserve(&List.indices, len(List.indices) + (n - 2) * 3)

		for p in List.path do append(&List.vertices, Vertex{Pos = p.pos, UV = uv, Color = p.col})
		for i in 1 ..< n - 1 {
			append(&List.indices, base, base + u32(i), base + u32(i + 1))
		}
	} else {
		path_miter_normals(List, true)
		reserve(&List.vertices, len(List.vertices) + n * 2)
		reserve(&List.indices, len(List.indices) + (n - 2) * 3 + n * 6)

		// The rim grows outward, so the fill keeps its declared size and two fills that share an
		// edge leave no background showing through the seam.
		for p in List.path {
			append(&List.vertices, Vertex{Pos = p.pos, UV = uv, Color = p.col})
		}
		for p, i in List.path {
			edge := p.col
			edge.a = 0
			append(&List.vertices, Vertex{Pos = p.pos + List.offsets[i] * feather, UV = uv, Color = edge})
		}

		outer := base + u32(n)
		for i in 1 ..< n - 1 {
			append(&List.indices, base, base + u32(i), base + u32(i + 1))
		}
		for i in 0 ..< n {
			j := u32((i + 1) % n)
			quad_indices(List, base + u32(i), outer + u32(i), outer + j, base + j)
		}
	}

	mesh_command(List, u32(len(List.indices) - start))
	path_clear(List)
}

// path_stroke traces the path as a band `Thickness` wide, then clears it. Each point carries its
// own vertices, so a join is a miter and the edges share them instead of repeating a bevelled
// quad per segment.
@(private="file")
path_stroke :: proc(List: ^DrawList, Tint: Color, Thickness: f32 = 1, Closed: bool = true) {
	n := len(List.path)
	if n < 2 || Thickness <= 0 {
		path_clear(List)
		return
	}

	uv := use_atlas(List)
	half := Thickness / 2
	feather: f32
	if List.antialias do feather = List.fringe

	// The fringe adds a pixel past the edge on each side, so the body keeps the width it was
	// declared with and the blend has a whole pixel to fall across.
	outer := half + feather

	path_miter_normals(List, Closed)

	stride := 4 if feather > 0 else 2
	start := len(List.indices)
	base := u32(len(List.vertices))
	reserve(&List.vertices, len(List.vertices) + n * stride)
	reserve(&List.indices, len(List.indices) + n * stride * 3)

	faded := Tint
	faded.a = 0

	for p, i in List.path {
		m := List.offsets[i]
		if feather > 0 {
			append(&List.vertices, Vertex{Pos = p.pos + m * outer, UV = uv, Color = faded})
		}
		append(&List.vertices, Vertex{Pos = p.pos + m * half, UV = uv, Color = Tint})
		append(&List.vertices, Vertex{Pos = p.pos - m * half, UV = uv, Color = Tint})
		if feather > 0 {
			append(&List.vertices, Vertex{Pos = p.pos - m * outer, UV = uv, Color = faded})
		}
	}

	edges := n if Closed else n - 1
	for i in 0 ..< edges {
		j := (i + 1) % n
		a := base + u32(i * stride)
		b := base + u32(j * stride)
		if feather > 0 {
			quad_indices(List, a, a + 1, b + 1, b)
			quad_indices(List, a + 1, a + 2, b + 2, b + 1)
			quad_indices(List, a + 2, a + 3, b + 3, b + 2)
		} else {
			quad_indices(List, a, a + 1, b + 1, b)
		}
	}

	if count := len(List.indices) - start; count > 0 do mesh_command(List, u32(count))
	path_clear(List)
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

// append_quad_gradient writes four vertices and six indices for a textured quad, one corner
// color each, and closes its own command.
@(private="file")
append_quad_gradient :: proc(List: ^DrawList, Rect: Rect, UV0, UV1: Vec2, Colors: Gradient) {
	vtx := u32(len(List.vertices))
	x0, y0 := Rect.x, Rect.y
	x1, y1 := Rect.x + Rect.w, Rect.y + Rect.h

	append(&List.vertices, Vertex{Pos = {x0, y0}, UV = {UV0.x, UV0.y}, Color = Colors[0]})
	append(&List.vertices, Vertex{Pos = {x1, y0}, UV = {UV1.x, UV0.y}, Color = Colors[1]})
	append(&List.vertices, Vertex{Pos = {x1, y1}, UV = {UV1.x, UV1.y}, Color = Colors[2]})
	append(&List.vertices, Vertex{Pos = {x0, y1}, UV = {UV0.x, UV1.y}, Color = Colors[3]})

	append(&List.indices, vtx + 0)
	append(&List.indices, vtx + 1)
	append(&List.indices, vtx + 2)
	append(&List.indices, vtx + 0)
	append(&List.indices, vtx + 2)
	append(&List.indices, vtx + 3)

	mesh_command(List, 6)
}
