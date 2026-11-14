package ui

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
// paint over earlier ones.
DrawList :: struct {
	vertices:   [dynamic]Vertex,
	indices:    [dynamic]u32,
	commands:   [dynamic]DrawCommand,
	path:       [dynamic]PathPoint,
	clip_stack: [dynamic]Rect,
	clip:       Rect,
	texture:    Texture,
}

// Frame is what a backend needs in order to draw one frame.
Frame :: struct {
	Vertices: []Vertex,
	Indices:  []u32,
	Commands: []DrawCommand,
	Scale:    f32,
}

@(private="file")
list: DrawList

// DrawData returns the mesh and draw commands of the last completed frame. The slices are
// only valid until the next call to Begin.
DrawData :: proc() -> Frame {
	return {list.vertices[:], list.indices[:], list.commands[:], effective_scale()}
}

// PushClipRect narrows the visible area to `Rect` for everything appended after it. The
// new clip is the overlap with the current one, so nesting only shrinks it.
PushClipRect :: proc(List: ^DrawList, Rect: Rect) {
	append(&List.clip_stack, List.clip)
	List.clip = RectIntersect(List.clip, Rect)
}

// PopClipRect restores the clip saved by the matching PushClipRect.
PopClipRect :: proc(List: ^DrawList) {
	assert(len(List.clip_stack) > 0, "PopClipRect without a matching PushClipRect")
	List.clip = pop(&List.clip_stack)
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
// units.
AddText :: proc(List: ^DrawList, Pos: Vec2, Text: cstring, Tint: Color, Font: Font = 0, Size: f32 = 16) {
	if Text == nil do return
	add_text_run(List, Pos, string(Text), Tint, Font, Size)
}

// add_text_run appends a run that needs no terminator, so a wrapped line is drawn as the
// slice of the source it already is.
@(private="file")
add_text_run :: proc(List: ^DrawList, Pos: Vec2, Run: string, Tint: Color, Font: Font, Size: f32) {
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
	for fontstash.TextIterNext(&font_ctx, &iter, &quad) {
		append_quad(
			List,
			quad.x0 / scale, quad.y0 / scale, quad.x1 / scale, quad.y1 / scale,
			{quad.s0, quad.t0}, {quad.s1, quad.t1}, Tint,
		)
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
	clear(&list.clip_stack)
	size := viewport_size()
	list.clip = {0, 0, size.x, size.y}
	list.texture = {}
}

// draw_build walks the tree in paint order, starting from the implicit root.
@(private)
draw_build :: proc() {
	draw_node(0)
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
		case .Contain:
			scales := size / Source
			drawn = Source * min(scales.x, scales.y)
		case .Cover:
			scales := size / Source
			visible := size / max(scales.x, scales.y)
			uv0 = (Source - visible) / 2 / Source
			uv1 = uv0 + visible / Source
		}
	}

	at := Vec2{Target.x, Target.y} + (size - drawn) / 2
	return {at.x, at.y, drawn.x, drawn.y}, uv0, uv1
}

// draw_node emits node i and then its subtree. A node that clips pushes its inner rect
// before its content and children, so everything inside is cut to it.
@(private="file")
draw_node :: proc(i: u32) #no_bounds_check {
	n := &state.nodes[i]

	// One test decides whether the element paints at all. The border is centered on the
	// edge, so half of it sits outside the rect.
	bw := n.style.Border.Width / 2
	visible := RectOverlaps({n.rect.x - bw, n.rect.y - bw, n.rect.w + bw * 2, n.rect.h + bw * 2}, list.clip)
	corners := n.style.CornerRadius

	if visible {
		if n.style.Background.a != 0 {
			AddRectFilled(&list, n.rect, n.style.Background, corners)
		}
		if n.style.Border.Width > 0 {
			AddRectStroke(&list, n.rect, n.style.Border.Color, n.style.Border.Width, corners)
		}
	}

	n.clip = list.clip

	clip := n.config.Clip || scrolls(n, .Vertical) || scrolls(n, .Horizontal)
	if clip do PushClipRect(&list, inner_rect(i, n.rect))

	switch content in n.content {
	case TextContent:
		text_lines := content.lines
		if len(text_lines) == 0 do break

		inner := inner_rect(i, n.rect)
		painted := Rect{inner.x, inner.y, max(inner.w, n.content_size.x), max(inner.h, n.content_size.y)}
		if !RectOverlaps(painted, list.clip) do break

		line_height := n.content_size.y / f32(len(text_lines))
		for line, index in text_lines {
			x := inner.x
			#partial switch content.config.Align {
			case .Center: x += max((inner.w - line.Width) / 2, 0)
			case .Right:  x += max(inner.w - line.Width, 0)
			}
			add_text_run(
				&list,
				{x, inner.y + line_height * f32(index)},
				string(content.text)[line.Start:line.End],
				content.config.Color,
				content.font,
				content.config.Size,
			)
		}
	case ImageContent:
		inner := inner_rect(i, n.rect)
		if !RectOverlaps(inner, list.clip) do break

		rect, uv0, uv1 := fit_image(inner, {content.handle.Width, content.handle.Height}, content.config.Fit)
		AddImage(&list, rect, content.handle, content.config.Tint, uv0, uv1)
	case PaintProc:
		if visible do content(n.rect, &list, n.id)
	}

	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		draw_node(c)
	}

	if clip do PopClipRect(&list)
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
		AddRectFilled(&list, bar.track, TRACK, ends)
		AddRectFilled(&list, bar.thumb, THUMB, ends)
	}
}
