package ui

import "core:math"
import "vendor:fontstash"

// Vertex is one point of the frame's mesh: position in layout units, atlas coordinate and
// flat color. Color per vertex is what lets any shape carry a gradient.
Vertex :: struct #packed {
	Pos:   Vec2,
	UV:    Vec2,
	Color: Color,
}

// Texture is a backend texture and its pixel size. The backend owns the texture; the
// engine only copies the value, and the zero value means no texture.
Texture :: struct {
	Handle: rawptr,
	Width:  f32,
	Height: f32,
}

// DrawCommand is one draw call: a slice of the index buffer, drawn with one texture,
// clipped to one rect.
DrawCommand :: struct {
	Clip:    Rect,
	Texture: Texture,
	Offset:  u32,
	Count:   u32,
}

// PathPoint is one point of the path being built: where it is and the color it carries,
// which is what lets any shape fade.
@(private)
PathPoint :: struct {
	pos: Vec2,
	col: Color,
}

// DrawList is the shape buffer of one frame. Shapes append in call order, so later calls
// paint over earlier ones. `fringe` is one pixel in layout units, cached once per frame, and
// `antialias` says whether shapes pay for the transparent edge that blends them.
@(private)
DrawList :: struct {
	vertices:   [dynamic]Vertex,
	indices:    [dynamic]u32,
	commands:   [dynamic]DrawCommand,
	path:       [dynamic]PathPoint,
	offsets:    [dynamic]Vec2,
	clip_stack: [dynamic]Rect,
	aa_stack:   [dynamic]bool,
	clip:       Rect,
	texture:    Texture,
	antialias:  bool,
	fringe:     f32,
}

// Frame is what a backend needs in order to draw one frame.
Frame :: struct {
	Vertices: []Vertex,
	Indices:  []u32,
	Commands: []DrawCommand,
	Scale:    f32,
}

@(private)
list: DrawList = {antialias = true}

// SetAntialias turns the blended edge of every shape on or off. It keeps its value across frames,
// and a shape drawn without it is cheaper and keeps hard pixel edges.
SetAntialias :: proc(Enabled: bool = true) {
	list.antialias = Enabled
}

// DrawData returns the mesh and draw commands of the last completed frame. The slices are
// only valid until the next call to Begin.
DrawData :: proc() -> Frame {
	return {list.vertices[:], list.indices[:], list.commands[:], effective_scale()}
}

// PushClipRect narrows the visible area to `Rect` for everything appended after it. The
// new clip is the overlap with the current one, so nesting only shrinks it.
PushClipRect :: proc(Rect: Rect) {
	append(&list.clip_stack, list.clip)
	list.clip = RectIntersect(list.clip, Rect)
}

// PopClipRect restores the clip saved by the matching PushClipRect.
PopClipRect :: proc() {
	assert(len(list.clip_stack) > 0, "PopClipRect without a matching PushClipRect")
	list.clip = pop(&list.clip_stack)
}

// PushAntialias sets whether the shapes appended after it blend their edges, until the matching
// PopAntialias. It restores the previous value, so it nests.
PushAntialias :: proc(Enabled: bool) {
	append(&list.aa_stack, list.antialias)
	list.antialias = Enabled
}

// PopAntialias restores the antialias setting saved by the matching PushAntialias.
PopAntialias :: proc() {
	assert(len(list.aa_stack) > 0, "PopAntialias without a matching PushAntialias")
	list.antialias = pop(&list.aa_stack)
}

// mesh_command grows the last draw command when it still matches, or opens a new one
// covering the indices just written.
@(private)
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

// AddText appends `Text` with its top left corner at `Pos`. `Pos` and `Size` are in layout
// units. It takes a slice, so a prefix of a longer string draws without a copy; a `cstring`
// converts with `string(c)`.
AddText :: proc(Pos: Vec2, Text: string, Tint: Color, Font: Font = 0, Size: f32 = 16) {
	add_text_run(&list, Pos, Text, Tint, Font, Size)
}

// add_text_run appends a run that needs no terminator, so a wrapped line is drawn as the
// slice of the source it already is. `Extra` is the space a justified line adds after each
// space, in layout units.
@(private)
add_text_run :: proc(List: ^DrawList, Pos: Vec2, Run: string, Tint: Color, Font: Font, Size: f32, Extra: f32 = 0) {
	if len(Run) == 0 || len(font_ctx.fonts) == 0 || Size <= 0 do return

	scale := effective_scale()
	fontstash.SetFont(&font_ctx, int(Font))
	fontstash.SetSize(&font_ctx, Size * scale)
	fontstash.SetAV(&font_ctx, .TOP)
	fontstash.SetAH(&font_ctx, .LEFT)

	previous := List.texture
	List.texture = atlas_texture

	iter := fontstash.TextIterInit(&font_ctx, Pos.x * scale, Pos.y * scale, Run)
	quad: fontstash.Quad
	pen: f32
	for fontstash.TextIterNext(&font_ctx, &iter, &quad) {
		append_quad(
			List,
			quad.x0 / scale + pen, quad.y0 / scale, quad.x1 / scale + pen, quad.y1 / scale,
			{quad.s0, quad.t0}, {quad.s1, quad.t1}, Tint,
		)
		if Extra != 0 && iter.codepoint == ' ' do pen += Extra
	}

	List.texture = previous
}

// draw_begin_frame clears the list and resets its clip and texture.
@(private)
draw_begin_frame :: proc() {
	clear(&list.vertices)
	clear(&list.indices)
	clear(&list.commands)
	clear(&list.path)
	clear(&list.offsets)
	clear(&list.clip_stack)
	clear(&list.aa_stack)
	size := viewport_size()
	list.clip = {0, 0, size.x, size.y}
	list.texture = {}
	list.fringe = 1 / effective_scale()
}

// AddRectFilled appends a filled rectangle, rounding each corner by its own radius.
AddRectFilled :: proc(Rect: Rect, Tint: Color, CornerRadius: CornerRadius = {}) {
	path_rect(&list, Rect, CornerRadius, Tint)
	path_fill_convex(&list)
}

// AddRectStroke appends the outline of a rectangle, `Thickness` pixels wide.
AddRectStroke :: proc(Rect: Rect, Tint: Color, Thickness: f32 = 1, CornerRadius: CornerRadius = {}) {
	path_rect(&list, Rect, CornerRadius, Tint)
	path_stroke(&list, Tint, Thickness)
}

// AddRectGradient appends a rectangle fading across its four corner colors.
AddRectGradient :: proc(Rect: Rect, Colors: Gradient, CornerRadius: CornerRadius = {}) {
	path_rect(&list, Rect, CornerRadius, Colors[0])
	path_gradient(&list, Rect, Colors)
	path_fill_convex(&list)
}

// AddCircleGradient appends a filled circle fading across `Colors`, sampled over the box
// that encloses it.
AddCircleGradient :: proc(Center: Vec2, Radius: f32, Colors: Gradient, Segments: int = 0) {
	path_arc_to(&list, Center, Radius, 0, math.TAU, Colors[0], Segments)
	path_gradient(&list, {Center.x - Radius, Center.y - Radius, Radius * 2, Radius * 2}, Colors)
	path_fill_convex(&list)
}

// AddTriangleGradient appends a filled triangle fading across `Colors`, sampled over the box
// that encloses its three points.
AddTriangleGradient :: proc(A, B, C: Vec2, Colors: Gradient) {
	path_line_to(&list, A, Colors[0])
	path_line_to(&list, B, Colors[0])
	path_line_to(&list, C, Colors[0])
	points := [3]Vec2{A, B, C}
	path_gradient(&list, points_box(points[:]), Colors)
	path_fill_convex(&list)
}

// AddPolygonGradient appends a filled convex polygon fading across `Colors`, sampled over the
// box that encloses its points.
AddPolygonGradient :: proc(Points: []Vec2, Colors: Gradient) {
	for p in Points do path_line_to(&list, p, Colors[0])
	path_gradient(&list, points_box(Points), Colors)
	path_fill_convex(&list)
}

// AddRegularPolygonGradient appends a filled regular polygon with `Sides` sides, fading across
// `Colors` over the box that encloses it.
AddRegularPolygonGradient :: proc(Center: Vec2, Sides: int, Radius: f32, Colors: Gradient, Start: f32 = 0) {
	points: [MAX_POLYGON_SIDES]Vec2
	p := regular_polygon(points[:], Sides, Center, Radius, Start)
	if len(p) == 0 do return
	AddPolygonGradient(p, Colors)
}

// AddCircleFilled appends a filled circle.
AddCircleFilled :: proc(Center: Vec2, Radius: f32, Tint: Color, Segments: int = 0) {
	path_arc_to(&list, Center, Radius, 0, math.TAU, Tint, Segments)
	path_fill_convex(&list)
}

// AddCircleStroke appends a circle outline, `Thickness` pixels wide.
AddCircleStroke :: proc(Center: Vec2, Radius: f32, Tint: Color, Thickness: f32 = 1, Segments: int = 0) {
	path_arc_to(&list, Center, Radius, 0, math.TAU, Tint, Segments)
	path_stroke(&list, Tint, Thickness)
}

// AddArc appends an arc outline from `A0` to `A1` radians.
AddArc :: proc(Center: Vec2, Radius: f32, A0, A1: f32, Tint: Color, Thickness: f32 = 1, Segments: int = 0) {
	path_arc_to(&list, Center, Radius, A0, A1, Tint, Segments)
	path_stroke(&list, Tint, Thickness, Closed = false)
}

// AddTriangleFilled appends a filled triangle.
AddTriangleFilled :: proc(A, B, C: Vec2, Tint: Color) {
	path_line_to(&list, A, Tint)
	path_line_to(&list, B, Tint)
	path_line_to(&list, C, Tint)
	path_fill_convex(&list)
}

// AddTriangleStroke appends the outline of a triangle, `Thickness` pixels wide.
AddTriangleStroke :: proc(A, B, C: Vec2, Tint: Color, Thickness: f32 = 1) {
	path_line_to(&list, A, Tint)
	path_line_to(&list, B, Tint)
	path_line_to(&list, C, Tint)
	path_stroke(&list, Tint, Thickness)
}

// AddLine appends a line segment `Thickness` wide.
AddLine :: proc(A, B: Vec2, Tint: Color, Thickness: f32 = 1) {
	path_line_to(&list, A, Tint)
	path_line_to(&list, B, Tint)
	path_stroke(&list, Tint, Thickness, Closed = false)
}

// AddPolygonFilled appends a filled convex polygon.
AddPolygonFilled :: proc(Points: []Vec2, Tint: Color) {
	for p in Points do path_line_to(&list, p, Tint)
	path_fill_convex(&list)
}

// AddPolygonStroke appends the outline of a polygon through `Points`. Pass
// `Closed = false` to trace an open polyline instead.
AddPolygonStroke :: proc(Points: []Vec2, Tint: Color, Thickness: f32 = 1, Closed: bool = true) {
	for p in Points do path_line_to(&list, p, Tint)
	path_stroke(&list, Tint, Thickness, Closed)
}

// AddRegularPolygonFilled appends a filled regular polygon with `Sides` sides, starting
// at angle `Start` radians.
AddRegularPolygonFilled :: proc(Center: Vec2, Sides: int, Radius: f32, Tint: Color, Start: f32 = 0) {
	points: [MAX_POLYGON_SIDES]Vec2
	p := regular_polygon(points[:], Sides, Center, Radius, Start)
	if len(p) == 0 do return
	AddPolygonFilled(p, Tint)
}

// AddRegularPolygonStroke appends the outline of a regular polygon with `Sides` sides,
// `Thickness` pixels wide.
AddRegularPolygonStroke :: proc(
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
	AddPolygonStroke(p, Tint, Thickness)
}

// AddImage appends a quad that samples the `UV0`..`UV1` region of `Texture` over `Rect`,
// tinted by `Tint`.
AddImage :: proc(
	Rect:    Rect,
	Texture: Texture,
	Tint:    Color,
	UV0:     Vec2 = {0, 0},
	UV1:     Vec2 = {1, 1},
) {
	previous := list.texture
	list.texture = Texture
	append_quad(&list, Rect.x, Rect.y, Rect.x + Rect.w, Rect.y + Rect.h, UV0, UV1, Tint)
	list.texture = previous
}

// AddImageGradient appends a quad that samples the `UV0`..`UV1` region of `Texture` over
// `Rect`, fading across `Colors`.
AddImageGradient :: proc(
	Rect:    Rect,
	Texture: Texture,
	Colors:  Gradient,
	UV0:     Vec2 = {0, 0},
	UV1:     Vec2 = {1, 1},
) {
	previous := list.texture
	list.texture = Texture
	append_quad_gradient(&list, Rect, UV0, UV1, Colors)
	list.texture = previous
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

// path_line_to appends `P` to the path, carrying `Tint`.
@(private="file")
path_line_to :: proc(List: ^DrawList, P: Vec2, Tint: Color) {
	append(&List.path, PathPoint{pos = P, col = Tint})
}

// path_arc_to appends the points of an arc around `Center`, from `A0` to `A1` radians.
// `Segments` of zero picks the fewest points that hold the arc within ARC_ERROR pixels.
@(private="file")
path_arc_to :: proc(List: ^DrawList, Center: Vec2, Radius: f32, A0, A1: f32, Tint: Color, Segments: int = 0) {
	if Radius <= 0 do return

	n := Segments
	if n <= 0 {
		// A chord leaves a sagitta of radius * (1 - cos(step / 2)), so the step that keeps it at
		// the error is 2 * acos(1 - error / radius).
		pixels := Radius / max(List.fringe, 0.0001)
		n = 2
		if pixels > ARC_ERROR {
			step := 2 * math.acos(1 - ARC_ERROR / pixels)
			n = clamp(int(math.ceil(abs(A1 - A0) / step)), 2, ARC_SEGMENT_MAX)
		}
	}

	// Step by rotating the radius vector, so the whole arc costs two sines and two cosines.
	step := (A1 - A0) / f32(n)
	c, s := math.cos(step), math.sin(step)
	x, y := math.cos(A0) * Radius, math.sin(A0) * Radius

	// A full turn ends where it starts, so its last point would duplicate the first and leave the
	// seam between two normals. The path closes implicitly instead, as every closed path does.
	count := n + 1
	if abs(A1 - A0) >= math.TAU do count = n

	reserve(&List.path, len(List.path) + count)
	for _ in 0 ..< count {
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
		clear(&List.path)
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
	clear(&List.path)
}

// path_stroke traces the path as a band `Thickness` wide, then clears it. Each point carries its
// own vertices, so a join is a miter and the edges share them instead of repeating a bevelled
// quad per segment.
@(private="file")
path_stroke :: proc(List: ^DrawList, Tint: Color, Thickness: f32 = 1, Closed: bool = true) {
	n := len(List.path)
	if n < 2 || Thickness <= 0 {
		clear(&List.path)
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
	clear(&List.path)
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

// draw_build walks the flow tree in paint order, then the floating layer in declaration order,
// so a floating node paints over everything and the last one sits on top.
@(private)
draw_build :: proc() {
	draw_node(0)
	for &f in state.floats do draw_node(f.node)
}

// fit_image returns the rect and the UV range an image draws with inside `Target`. Stretch
// uses the whole target, Contain centers the source inside it, and Cover crops the source
// to the target's aspect ratio.
@(private="file")
fit_image :: proc(Target: Rect, Source: Vec2, Fit: ImageFit) -> (rect: Rect, uv0, uv1: Vec2) {
	size := Vec2{Target.w, Target.h}
	drawn := size
	uv1 = {1, 1}

	if Source.x > 0 && Source.y > 0 {
		#partial switch Fit {
		case .Contain: {
			scales := size / Source
			drawn = Source * min(scales.x, scales.y)
		}
		case .Cover: {
			scales := size / Source
			visible := size / max(scales.x, scales.y)
			uv0 = (Source - visible) / 2 / Source
			uv1 = uv0 + visible / Source
		}
		}
	}

	at := Vec2{Target.x, Target.y} + (size - drawn) / 2
	return {at.x, at.y, drawn.x, drawn.y}, uv0, uv1
}

// draw_background paints `Value` over `Rect`, skipping it when fully transparent. A gradient
// goes top left, top right, bottom right, bottom left, as `Gradient` documents.
@(private="file")
draw_background :: proc(Rect: Rect, Value: Background, CornerRadius: CornerRadius) {
	switch f in Value {
	case Color:
		if f.a != 0 do AddRectFilled(Rect, f, CornerRadius)
	case Gradient: {
		if f[0].a != 0 || f[1].a != 0 || f[2].a != 0 || f[3].a != 0 {
			AddRectGradient(Rect, f, CornerRadius)
		}
	}
	}
}

// draw_border outlines `Rect` with `Width` in `Color`, and returns when every side is zero.
// Equal sides keep the corner radius through one stroke; sides that differ are painted as
// plain edges, which is what a divider or a single-sided underline needs.
@(private="file")
draw_border :: proc(Rect: Rect, Color: Color, Width: Edges, CornerRadius: CornerRadius) {
	w := Width

	if w.Left == w.Right && w.Top == w.Bottom && w.Left == w.Top {
		if w.Left > 0 do AddRectStroke(Rect, Color, w.Left, CornerRadius)
		return
	}

	// Each side is drawn inward from the edge, so no side reaches past the rect.
	if w.Top > 0 {
		AddRectFilled({Rect.x, Rect.y, Rect.w, w.Top}, Color)
	}
	if w.Bottom > 0 {
		AddRectFilled({Rect.x, Rect.y + Rect.h - w.Bottom, Rect.w, w.Bottom}, Color)
	}
	if w.Left > 0 {
		AddRectFilled({Rect.x, Rect.y + w.Top, w.Left, max(Rect.h - w.Top - w.Bottom, 0)}, Color)
	}
	if w.Right > 0 {
		AddRectFilled({Rect.x + Rect.w - w.Right, Rect.y + w.Top, w.Right, max(Rect.h - w.Top - w.Bottom, 0)}, Color)
	}
}

// draw_node emits node i and then its subtree. A node that clips pushes its inner rect
// before its content and children, so everything inside is cut to it.
@(private="file")
draw_node :: proc(i: u32) #no_bounds_check {
	n := &state.nodes[i]

	// One test decides whether the element paints at all. The border is centered on the
	// edge, so half of the widest side sits outside the rect.
	b := n.style.BorderWidth
	bw := max(b.Left, b.Right, b.Top, b.Bottom) / 2
	visible := RectOverlaps({n.rect.x - bw, n.rect.y - bw, n.rect.w + bw * 2, n.rect.h + bw * 2}, list.clip)
	corners := n.style.CornerRadius

	if visible {
		draw_background(n.rect, n.style.Background, corners)
		draw_border(n.rect, n.style.BorderColor, n.style.BorderWidth, corners)
	}

	n.clip = list.clip

	clip := n.config.Clip || scrolls(n, .Vertical) || scrolls(n, .Horizontal)
	if clip do PushClipRect(inner_rect(n, n.rect, n.strips))

	switch &content in n.content {
	case TextContent: {
		text_lines := content.lines
		if len(text_lines) == 0 do break

		inner := inner_rect(n, n.rect, n.strips)
		painted := Rect{inner.x, inner.y, max(inner.w, n.content_size.x), max(inner.h, n.content_size.y)}
		if !RectOverlaps(painted, list.clip) do break

		line_height := n.content_size.y / f32(len(text_lines))
		top := inner.y
		if inner.h > n.content_size.y {
			#partial switch content.valign {
			case .Center: top += (inner.h - n.content_size.y) / 2
			case .Bottom: top += inner.h - n.content_size.y
			}
		}

		for line, index in text_lines {
			x := inner.x
			extra: f32
			width := line.Width
			#partial switch content.align {
			case .Center:
				x += max((inner.w - line.Width) / 2, 0)
			case .Right:
				x += max(inner.w - line.Width, 0)
			case .Justify: {
				source := content.text
				if !line.Truncated && line.Width < inner.w && line.End < u32(len(source)) && source[line.End] != '\n' {
					spaces := 0
					for c in source[line.Start:line.End] {
						if c == ' ' do spaces += 1
					}
					if spaces > 0 {
						extra = (inner.w - line.Width) / f32(spaces)
						width = inner.w
					}
				}
			}
			}

			y := top + line_height * f32(index)
			if !RectOverlaps({x, y, width, line_height}, list.clip) do continue

			add_text_run(
				&list,
				{x, y},
				content.text[line.Start:line.End],
				content.color,
				content.font,
				content.size,
				extra,
			)

			if line.Truncated && content.ellipsis {
				tail := MeasureText(ELLIPSIS, content.font, content.size).x
				add_text_run(&list, {x + width - tail, y}, ELLIPSIS, content.color, content.font, content.size)
			}
		}
	}
	case ImageContent: {
		inner := inner_rect(n, n.rect, n.strips)
		if !RectOverlaps(inner, list.clip) do break

		rect, uv0, uv1 := fit_image(inner, {content.handle.Width, content.handle.Height}, content.fit)
		AddImage(rect, content.handle, content.tint, uv0, uv1)
	}
	case CustomContent: {
		if visible {
			user: rawptr
			if content.Size > 0 do user = rawptr(&state.user_data[content.Offset])
			content.Fn(n.rect, n.id, user)
		}
	}
	}

	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		if state.nodes[c].floating do continue
		draw_node(c)
	}

	if clip do PopClipRect()
	if n.strips != {} && visible do draw_scrollbar(i)
}

// draw_scrollbar draws the bar of node i on every axis that has one, with the same geometry
// the drag uses, and after the clip is popped so its own container never cuts it.
@(private="file")
draw_scrollbar :: proc(i: u32) #no_bounds_check {
	TRACK :: Color{255, 255, 255, 30}
	THUMB :: Color{255, 255, 255, 90}

	for axis in ScrollAxis {
		bar, ok := scrollbar(i, axis)
		if !ok do continue

		ends := Corners(min(bar.track.w, bar.track.h) / 2)
		AddRectFilled(bar.track, TRACK, ends)
		AddRectFilled(bar.thumb, THUMB, ends)

		// The bar belongs to the layout, not to the content under it, so it takes the pointer back
		// to the neutral shape a widget may have asked for.
		if RectContains(bar.track, MousePos()) do SetCursor(.Arrow)
	}
}
