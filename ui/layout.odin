package ui

import "core:fmt"

Vec2      :: [2]f32
Rect      :: struct{ x, y, w, h: f32 }

Direction :: enum u8 { Row, Column }

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

// Edge builds an Edges: Edge(All) puts `All` on every side, Edge(X, Y) puts `X` on the left
// and right and `Y` on the top and bottom. A bare `Edges` literal names the sides.
Edge :: proc{edge_all, edge_xy}

// edge_all returns the edges with `All` on every side.
@(private="file")
edge_all :: #force_inline proc "contextless" (All: f32) -> Edges {
	return {Left = All, Right = All, Top = All, Bottom = All}
}

// edge_xy returns the edges with `X` on the left and right and `Y` on the top and bottom.
@(private="file")
edge_xy :: #force_inline proc "contextless" (X, Y: f32) -> Edges {
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

// RectContains reports whether the point lies inside the rect.
RectContains :: #force_inline proc "contextless" (Rect: Rect, Point: Vec2) -> bool {
	return Point.x >= Rect.x && Point.x <= Rect.x + Rect.w &&
		   Point.y >= Rect.y && Point.y <= Rect.y + Rect.h
}

// RectIntersect returns the overlap of the two rects, or an empty rect when they
// do not touch.
RectIntersect :: #force_inline proc "contextless" (A, B: Rect) -> Rect {
	x := max(A.x, B.x)
	y := max(A.y, B.y)
	return {x, y, max(0, min(A.x + A.w, B.x + B.w) - x), max(0, min(A.y + A.h, B.y + B.h) - y)}
}

// RectOverlaps reports whether the two rects share any area. Touching edges do not
// count, since nothing is painted there.
RectOverlaps :: #force_inline proc "contextless" (A, B: Rect) -> bool {
	return A.x < B.x + B.w && B.x < A.x + A.w &&
	       A.y < B.y + B.h && B.y < A.y + A.h
}

// Placement is where the last finished layout left one element: its id, its parent node, its
// rect, and the frame it was placed in, at the index the node had.
@(private)
Placement :: struct {
	id:     ElementId,
	parent: u32,
	rect:   Rect,
	frame:  u32,
}

// prev_at returns the entry for node `i`, or zero before any layout has finished.
@(private)
prev_at :: proc(i: u32) -> Placement #no_bounds_check {
	if int(i) >= len(state.prev) do return {}
	return state.prev[i]
}

@(private)
Node :: struct {
	config:       ContainerConfig,
	style:        BoxStyle,
	direction:    Direction,
	floating:     bool,
	base:         Vec2,
	content_size: Vec2,
	strips:       bit_set[ScrollAxis],
	rect:         Rect,
	clip:         Rect,
	content:      Content,
	id:           ElementId,
	subtree_end:  u32,
}

// TextContent is a leaf that paints `text` in `font`, at `size` layout units, tinted by `color`.
// `wrap` says how it breaks, `max_lines` where it stops, and `align`/`valign` where it sits.
@(private)
TextContent :: struct {
	text:      string,
	font:      Font,
	color:     Color,
	size:      f32,
	wrap:      WrapMode,
	max_lines: u16,
	ellipsis:  bool,
	align:     TextAlign,
	valign:    VerticalAlign,
	lines:     []Line,
}

// ImageContent is a leaf that paints `handle` over its rect, multiplied by `tint`. The host owns
// the texture and keeps it alive while the handle is in use.
@(private)
ImageContent :: struct {
	handle: Texture,
	tint:   Color,
	fit:    ImageFit,
}

// CustomProc is the leaf whose look comes from the host: a callback run once the rect is known.
// `User` points at the copy of the value the leaf declared, or is nil when it declared none.
CustomProc :: #type proc(Rect: Rect, Element: ElementId, User: rawptr)

// CustomContent is a CustomProc and where its user value sits in the frame buffer. The leaf copies
// the value, so it outlives the call that declared it, and the size is whatever the value needs.
@(private)
CustomContent :: struct {
	Fn:     CustomProc,
	Offset: u32,
	Size:   u32,
}

@(private)
Content :: union {
	TextContent,
	ImageContent,
	CustomContent,
}

// A layout axis is a ScrollAxis: Horizontal is X and Vertical is Y. A Row lays its
// children out along X and a Column along Y, and the other axis is the cross axis.

@(private="file")
sizing_of :: #force_inline proc(c: ContainerConfig, A: ScrollAxis) -> Sizing {
	return c.Width if A == .Horizontal else c.Height
}

@(private="file")
along :: #force_inline proc(v: Vec2, A: ScrollAxis) -> f32 {
	return v.x if A == .Horizontal else v.y
}

@(private="file")
size_along :: #force_inline proc(r: Rect, A: ScrollAxis) -> f32 {
	return r.w if A == .Horizontal else r.h
}

// next_sibling returns the index just past the current node's subtree, which is
// the next sibling in the flat, DFS pre-order node array.
@(private)
next_sibling :: #force_inline proc(i: u32) -> u32 #no_bounds_check {
	return state.nodes[i].subtree_end
}

// node_of returns the node with `ElementId`, or NO_NODE when the frame has no such element.
@(private)
node_of :: proc(id: ElementId) -> u32 #no_bounds_check {
	#reverse for &n, i in state.nodes {
		if n.id == id do return u32(i)
	}
	return NO_NODE
}

@(private="file")
resolve_axis :: proc(s: Sizing, content: f32) -> f32 {
	v := content
	if s.Kind == .Fixed do v = s.Basis
	if s.Min != 0 do v = max(v, s.Min)
	if s.Max != 0 do v = min(v, s.Max)
	return v
}

// padding returns the node's padding with the strip of a scroll bar added to the
// trailing edge of the axes in `bar`.
@(private)
padding :: proc(n: ^Node, bar: bit_set[ScrollAxis]) -> Edges {
	p := n.config.Pad
	if .Vertical in bar   do p.Right  += SCROLLBAR_THICKNESS + SCROLLBAR_GAP
	if .Horizontal in bar do p.Bottom += SCROLLBAR_THICKNESS + SCROLLBAR_GAP
	return p
}

// inset returns the space padding and border take around a node's content, along
// each axis, with the strips it keeps.
@(private="file")
inset :: proc(n: ^Node) -> Vec2 {
	p := padding(n, n.strips)
	b := n.style.BorderWidth
	return {p.Left + p.Right + b.Left + b.Right, p.Top + p.Bottom + b.Top + b.Bottom}
}

// Flex is a child's record during main-axis distribution: its base size, its flexibility and
// range, and the size resolved for it.
@(private)
Flex :: struct {
	node:   u32,
	base:   f32,
	grow:   f32,
	shrink: f32,
	min:    f32,
	max:    f32,
	size:   f32,
	frozen: bool,
}

// collect_flex gathers the direct children of node i into the reused scratch, recording each
// one's base size along `A` and its flexibility there.
@(private="file")
collect_flex :: proc(i: u32, A: ScrollAxis) -> []Flex #no_bounds_check {
	n := &state.nodes[i]
	clear(&state.flexes)
	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		child := &state.nodes[c]
		if child.floating do continue
		s := sizing_of(child.config, A)
		append(&state.flexes, Flex{
			node   = c,
			base   = along(child.base, A),
			grow   = s.Grow,
			shrink = s.Shrink,
			min    = s.Min,
			max    = s.Max,
		})
	}
	return state.flexes[:]
}

// flex_weight is an item's claim on the free space: its grow on a surplus, its shrink scaled
// by its base on a deficit.
@(private="file")
flex_weight :: #force_inline proc(it: Flex, free: f32) -> f32 {
	return it.grow if free > 0 else it.shrink * it.base
}

// resolve_flex distributes the leftover `free` main-axis space among the items. An item that
// reaches its min or max is frozen at that bound and the rest is re-shared.
@(private="file")
resolve_flex :: proc(items: []Flex, free: f32) {
	for &it in items {
		it.size   = it.base
		it.frozen = false
	}
	remaining := free
	if remaining == 0 do return

	for {
		total: f32
		for it in items {
			if !it.frozen do total += flex_weight(it, remaining)
		}
		if total == 0 do break

		froze := false
		for &it in items {
			if it.frozen do continue
			target := it.base + remaining * flex_weight(it, remaining) / total
			if it.min != 0 && target < it.min {
				it.size = it.min
			} else if it.max != 0 && target > it.max {
				it.size = it.max
			} else {
				it.size = target
				continue
			}
			remaining -= it.size - it.base
			it.frozen = true
			froze = true
		}
		if !froze do break
	}
}

// inner_rect returns the rect left inside `n` after its padding, its border and the strips of the
// bars in `strips`, never smaller than zero.
@(private)
inner_rect :: proc(n: ^Node, rect: Rect, strips: bit_set[ScrollAxis]) -> Rect {
	p := padding(n, strips)
	b := n.style.BorderWidth
	return {
		rect.x + p.Left + b.Left,
		rect.y + p.Top + b.Top,
		max(rect.w - p.Left - p.Right - b.Left - b.Right, 0),
		max(rect.h - p.Top - p.Bottom - b.Top - b.Bottom, 0),
	}
}

// padding_origin returns the top left of node `i` inside its border, the point a floating node
// measures its offset from.
@(private)
padding_origin :: proc(i: u32) -> Vec2 #no_bounds_check {
	b := state.nodes[i].style.BorderWidth
	return {state.nodes[i].rect.x + b.Left, state.nodes[i].rect.y + b.Top}
}

// justify returns the leading offset and the extra gap between children that spread the
// leftover `free` space along the main axis.
@(private="file")
justify :: proc(j: Justify, free: f32, count: int) -> (offset, gap: f32) {
	#partial switch j {
	case .Center:       offset = free / 2
	case .End:          offset = free
	case .SpaceBetween: if count > 1 do gap = free / f32(count - 1)
	}
	return
}

// gaps returns the space the gaps between `count` children take along the main axis.
@(private="file")
gaps :: #force_inline proc(n: ^Node, count: int) -> f32 {
	return n.config.Gap * f32(max(count - 1, 0))
}

// children_space returns the length the children share along `A`. A node that scrolls that
// axis hands them its content length, so the overflow is real instead of squeezed.
@(private="file")
children_space :: proc(n: ^Node, A: ScrollAxis, inner: f32) -> f32 {
	if scrolls(n, A) do return along(n.content_size, A)
	return inner
}

// cross_size resolves a child's size along an axis its parent does not lay out. The child
// fills the space when it grows there, or when the parent stretches a child that fits its
// content, and a wrapping text never runs past the space it was given.
@(private="file")
cross_size :: proc(n: ^Node, child: ^Node, space: f32, A: ScrollAxis) -> f32 {
	s := sizing_of(child.config, A)
	size := along(child.base, A)
	if s.Grow > 0 || (n.config.Align == .Stretch && s.Kind == .Fit) {
		size = space
	} else if text, ok := &child.content.(TextContent); ok && text.wrap != .None && s.Kind == .Fit {
		size = min(size, space)
	}
	if s.Min != 0 do size = max(size, s.Min)
	if s.Max != 0 do size = min(size, s.Max)
	return size
}

// measure_width gives every node its intrinsic width, bottom up. A text leaf measures
// unwrapped, so its width is its longest line; a container adds its children up along a Row
// and takes the widest one in a Column. Walking the flat array backwards visits each node
// after its whole subtree, which is the order the answer needs.
@(private="file")
measure_width :: proc() #no_bounds_check {
	#reverse for &n, i in state.nodes {
		n.strips = {}
		if strip_reserved(&n, .Vertical) do n.strips += {.Vertical}
		if strip_reserved(&n, .Horizontal) do n.strips += {.Horizontal}

		switch &content in n.content {
		case TextContent:
			n.content_size, content.lines = label_measure(content, 0)
		case CustomContent:
		case ImageContent: {
			n.content_size = {
				content.handle.Width  / state.screen.dpi,
				content.handle.Height / state.screen.dpi,
			}
		}
		case: {
			sum, widest: f32
			count := 0
			for c := u32(i) + 1; c < n.subtree_end; c = next_sibling(c) {
				if state.nodes[c].floating do continue
				w := state.nodes[c].base.x
				sum += w
				widest = max(widest, w)
				count += 1
			}
			n.content_size.x = sum + gaps(&n, count) if n.direction == .Row else widest
		}
		}
		n.base.x = resolve_axis(n.config.Width, n.content_size.x + inset(&n).x)
		if n.floating do n.rect.w = n.base.x
	}
}

// resolve_width fixes each node's width to the one its parent gave it, then shares the inner
// width among its children: a Row splits it along X by flex, a Column gives each child its
// cross size. Pre-order puts a parent before its children, so one forward pass replaces the
// recursion.
@(private="file")
resolve_width :: proc(Width: f32) #no_bounds_check {
	state.nodes[0].rect.w = Width
	for &n, i in state.nodes {
		if u32(i) + 1 >= n.subtree_end do continue

		space := children_space(&n, .Horizontal, max(n.rect.w - inset(&n).x, 0))
		if n.direction == .Row {
			items := collect_flex(u32(i), .Horizontal)
			base_sum: f32
			for it in items do base_sum += it.base
			resolve_flex(items, space - base_sum - gaps(&n, len(items)))
			for it in items do state.nodes[it.node].rect.w = it.size
		} else {
			for c := u32(i) + 1; c < n.subtree_end; c = next_sibling(c) {
				child := &state.nodes[c]
				if child.floating do continue
				child.rect.w = cross_size(&n, child, space, .Horizontal)
			}
		}
	}
}

// measure_height gives every node its intrinsic height, bottom up, once every width is final.
// A wrapping text breaks its lines against the width it was given. Like measure_width, it walks
// the array backwards so each child is measured before the parent that reads it.
@(private="file")
measure_height :: proc() #no_bounds_check {
	#reverse for &n, i in state.nodes {
		switch &content in n.content {
		case TextContent: {
			if content.wrap != .None || content.max_lines > 0 {
				n.content_size, content.lines = label_measure(content, max(n.rect.w - inset(&n).x, 0))
			}
		}
		case ImageContent:
		case CustomContent:
		case: {
			sum, tallest: f32
			count := 0
			for c := u32(i) + 1; c < n.subtree_end; c = next_sibling(c) {
				if state.nodes[c].floating do continue
				h := state.nodes[c].base.y
				sum += h
				tallest = max(tallest, h)
				count += 1
			}
			n.content_size.y = sum + gaps(&n, count) if n.direction == .Column else tallest
		}
		}
		n.base.y = resolve_axis(n.config.Height, n.content_size.y + inset(&n).y)
		if n.floating do n.rect.h = n.base.y
	}
}

// arrange places node i and its subtree, top-down. `parent` is the node it was declared in,
// recorded for the interaction chain and EnsureVisible; the pass also writes the scroll bar
// state the next frame's Auto answers come from.
@(private="file")
arrange :: proc(i: u32, parent: u32) #no_bounds_check {
	n := &state.nodes[i]
	state.prev[i] = Placement{id = n.id, parent = parent, rect = n.rect, frame = state.frame}
	if i + 1 >= n.subtree_end do return

	// The node is rebuilt every frame, so the answer Auto needs has to survive outside it, and
	// only Auto reads it back.
	if scroll_mode(n, .Vertical) == .Auto || scroll_mode(n, .Horizontal) == .Auto {
		Storage(n.id, bit_set[ScrollAxis])^ = strips(n, n.content_size)
	}
	arrange_children(i, inner_rect(n, n.rect, n.strips))
}

// arrange_children sizes the children of node i along its main axis, where a Column
// resolves heights by flex, and along its cross axis, where a Row resolves heights.
// Then it places each child and arranges its subtree. The widths of a Row and the cross
// widths of a Column were already fixed by resolve_width.
@(private="file")
arrange_children :: proc(i: u32, inner: Rect) #no_bounds_check {
	n := &state.nodes[i]
	main: ScrollAxis = .Horizontal if n.direction == .Row else .Vertical
	cross: ScrollAxis = .Vertical if main == .Horizontal else .Horizontal
	space_main := children_space(n, main, along({inner.w, inner.h}, main))
	space_cross := children_space(n, cross, along({inner.w, inner.h}, cross))

	if main == .Vertical {
		items := collect_flex(i, .Vertical)
		base_sum: f32
		for it in items do base_sum += it.base
		resolve_flex(items, space_main - base_sum - gaps(n, len(items)))
		for it in items do state.nodes[it.node].rect.h = it.size
	} else {
		for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
			child := &state.nodes[c]
			if child.floating do continue
			child.rect.h = cross_size(n, child, space_cross, .Vertical)
		}
	}

	used: f32
	count := 0
	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		if state.nodes[c].floating do continue
		used += size_along(state.nodes[c].rect, main)
		count += 1
	}
	used += gaps(n, count)
	offset, extra := justify(n.config.Justify, space_main - used, count)

	// The offset moves only the axes that scroll, and never past the content.
	scroll: Vec2
	if scrolls(n, .Vertical) || scrolls(n, .Horizontal) {
		scroll = ScrollOffset(n.id)
		limit := scroll_limit(n, inner)
		scroll = {
			clamp(scroll.x, 0, limit.x),
			clamp(scroll.y, 0, limit.y),
		}
		SetScroll(scroll, n.id)
	}

	cursor := offset
	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		child := &state.nodes[c]
		if child.floating do continue
		at: f32
		#partial switch n.config.Align {
		case .Center: at = (space_cross - size_along(child.rect, cross)) / 2
		case .End:    at = space_cross - size_along(child.rect, cross)
		}
		pos := Vec2{cursor, at} if main == .Horizontal else Vec2{at, cursor}
		child.rect.x = inner.x + pos.x - scroll.x
		child.rect.y = inner.y + pos.y - scroll.y
		cursor += size_along(child.rect, main) + n.config.Gap + extra
		arrange(c, i)
	}
}

// place_floats positions each floating node against its anchor and arranges its subtree, in
// declaration order, so a later float sits above an earlier one and may anchor inside it.
@(private)
place_floats :: proc() #no_bounds_check {
	viewport := viewport_size()
	for &f in state.floats {
		n := &state.nodes[f.node]

		origin: Vec2
		switch a in f.anchor {
		case ElementId: {
			if a != 0 {
				if i := node_of(a); i != NO_NODE {
					origin = padding_origin(i)
				} else {
					report(fmt.tprintf("ui: floating anchor %v not found", a))
				}
			}
		}
		case AnchorKind: {
			switch a {
			case .Parent:
				if f.parent != NO_NODE do origin = padding_origin(f.parent)
			case .Root:
				origin = {}
			case .Pointer:
				origin = MousePos()
			}
		}
		}

		extent := Vec2{n.rect.w, n.rect.h}
		at := origin + f.offset - f.pivot * extent
		n.rect.x = clamp(at.x, 0, max(viewport.x - extent.x, 0))
		n.rect.y = clamp(at.y, 0, max(viewport.y - extent.y, 0))
		arrange(f.node, f.parent)
	}
}

// layout runs the passes that size and place the frame, in the order CSS does: intrinsic
// widths from the inside out, final widths from the outside in, heights from the inside out
// once the widths are known, and finally positions from the outside in. The floating layer is
// placed last, so every anchor is already arranged.
@(private)
layout :: proc() {
	size := viewport_size()
	resize(&state.prev, len(state.nodes))

	measure_width()
	resolve_width(size.x)
	measure_height()
	state.nodes[0].rect = Rect{0, 0, size.x, size.y}
	arrange(0, NO_NODE)
	place_floats()
	state.published = state.frame

	when ODIN_DEBUG {
		check_ids()
	}
}

// check_ids reports two nodes that landed on the same id. A `-debug` diagnostic: it costs a map
// and a pass over every node, and ids are a 32-bit hash, so a collision is possible but rare.
when ODIN_DEBUG {
	@(private)
	check_ids :: proc() {
		seen: map[ElementId]u32
		defer delete(seen)

		for &n, i in state.nodes {
			if previous, ok := seen[n.id]; ok {
				report(fmt.tprintf("ui: duplicate element id at node %v and node %v", previous, i))
				return
			}
			seen[n.id] = u32(i)
		}
	}
}

