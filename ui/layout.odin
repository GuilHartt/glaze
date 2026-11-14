package ui

import "core:fmt"

Vec2 :: [2]f32
Rect :: struct{ x, y, w, h: f32 }
Id   :: distinct u32

Direction :: enum u8 { Row, Column }

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

Node :: struct {
	config:       LayoutConfig,
	style:        Style,
	direction:    Direction,
	base:         Vec2,
	content_size: Vec2,
	strips:       bit_set[ScrollAxis],
	rect:         Rect,
	clip:         Rect,
	content:      Content,
	id:           Id,
	subtree_end:  u32,
}

TextContent :: struct {
	text:   cstring,
	font:   Font,
	config: TextConfig,
	lines:  []Line,
}

// ImageContent is a leaf that paints `handle` over its rect, tinted by `config`. The
// host owns the texture and keeps it alive while the handle is in use.
ImageContent :: struct {
	handle: Texture,
	config: ImageConfig
}

// PaintProc is the custom draw leaf: a callback the host supplies, run once the rect is
// known. It is the content variant a widget uses when text and image do not fit.
PaintProc :: #type proc(Rect: Rect, List: ^DrawList, Id: Id)

Content :: union {
	TextContent,
	ImageContent,
	PaintProc,
}

// A layout axis is a ScrollAxis: Horizontal is X and Vertical is Y. A Row lays its
// children out along X and a Column along Y, and the other axis is the cross axis.

@(private="file")
sizing_of :: #force_inline proc(c: LayoutConfig, A: ScrollAxis) -> Sizing {
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
padding :: proc(n: ^Node, bar: bit_set[ScrollAxis]) -> Padding {
	p := n.config.Pad
	if .Vertical in bar   do p.Right  += SCROLLBAR_THICKNESS + SCROLLBAR_GAP
	if .Horizontal in bar do p.Bottom += SCROLLBAR_THICKNESS + SCROLLBAR_GAP
	return p
}

// inset returns the space padding and border take around a node's content, along
// each axis, with the strips it keeps.
@(private="file")
inset :: proc(n: ^Node) -> Vec2 {
	p  := padding(n, n.strips)
	bw := n.style.Border.Width * 2
	return {p.Left + p.Right + bw, p.Top + p.Bottom + bw}
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

// inner_rect returns the rect left inside a node after its padding and border, never smaller
// than zero. The padding already carries the strips of the bars it draws.
@(private)
inner_rect :: proc(i: u32, rect: Rect) -> Rect #no_bounds_check {
	n  := &state.nodes[i]
	p  := padding(n, n.strips)
	bw := n.style.Border.Width
	return {
		rect.x + p.Left + bw,
		rect.y + p.Top + bw,
		max(rect.w - p.Left - p.Right - bw*2, 0),
		max(rect.h - p.Top - p.Bottom - bw*2, 0),
	}
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
	} else if text, ok := &child.content.(TextContent); ok && text.config.Wrap != .None && s.Kind == .Fit {
		size = min(size, space)
	}
	if s.Min != 0 do size = max(size, s.Min)
	if s.Max != 0 do size = min(size, s.Max)
	return size
}

// measure_width gives every node its intrinsic width, bottom up, before any width is known.
// A text leaf measures unwrapped, so its width is its longest line; a container adds its
// children up along a Row and takes the widest one in a Column.
@(private="file")
measure_width :: proc(i: u32) #no_bounds_check {
	n := &state.nodes[i]
	n.strips = {}
	if strip_reserved(n, .Vertical) do n.strips += {.Vertical}
	if strip_reserved(n, .Horizontal) do n.strips += {.Horizontal}

	switch &content in n.content {
	case TextContent:
		n.content_size, content.lines = label_measure(content, 0)
	case PaintProc:
	case ImageContent:
		n.content_size = {
			content.handle.Width  / state.screen.dpi,
			content.handle.Height / state.screen.dpi,
		}
	case:
		sum, widest: f32
		count := 0
		for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
			measure_width(c)
			w := state.nodes[c].base.x
			sum += w
			widest = max(widest, w)
			count += 1
		}
		n.content_size.x = sum + gaps(n, count) if n.direction == .Row else widest
	}
	n.base.x = resolve_axis(n.config.Width, n.content_size.x + inset(n).x)
}

// resolve_width fixes the width of node i to the one its parent gave it, then shares the
// inner width among its children: a Row splits it along X by flex, a Column gives each child
// its cross size. Each child's width is final before its own children are placed, so a text
// can wrap against it later.
@(private="file")
resolve_width :: proc(i: u32, Width: f32) #no_bounds_check {
	n := &state.nodes[i]
	n.rect.w = Width
	if i + 1 >= n.subtree_end do return

	space := children_space(n, .Horizontal, max(Width - inset(n).x, 0))
	if n.direction == .Row {
		items := collect_flex(i, .Horizontal)
		base_sum: f32
		for it in items do base_sum += it.base
		resolve_flex(items, space - base_sum - gaps(n, len(items)))
		for it in items do state.nodes[it.node].rect.w = it.size
	} else {
		for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
			child := &state.nodes[c]
			child.rect.w = cross_size(n, child, space, .Horizontal)
		}
	}

	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		resolve_width(c, state.nodes[c].rect.w)
	}
}

// measure_height gives every node its intrinsic height, bottom up, once every width is final.
// A wrapping text breaks its lines against the width it was given, so its height is the height
// of those lines. A container stacks its children along a Column and takes the tallest in a Row.
@(private="file")
measure_height :: proc(i: u32) #no_bounds_check {
	n := &state.nodes[i]
	switch &content in n.content {
	case TextContent:
		if content.config.Wrap != .None {
			n.content_size, content.lines = label_measure(content, max(n.rect.w - inset(n).x, 0))
		}
	case ImageContent:
	case PaintProc:
	case:
		sum, tallest: f32
		count := 0
		for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
			measure_height(c)
			h := state.nodes[c].base.y
			sum += h
			tallest = max(tallest, h)
			count += 1
		}
		n.content_size.y = sum + gaps(n, count) if n.direction == .Column else tallest
	}
	n.base.y = resolve_axis(n.config.Height, n.content_size.y + inset(n).y)
}

// arrange places node i and its subtree, top-down. Its width and position come from its
// parent, so this pass resolves the heights along a Column, places each child, and writes the
// scroll bar state the next tick's Auto answers come from.
@(private="file")
arrange :: proc(i: u32) #no_bounds_check {
	n := &state.nodes[i]
	when CHECKS {
		if previous, seen := seen_ids[n.id]; seen {
			report(fmt.ctprintf("ui: duplicate element id at node %v and node %v", previous, i))
		}
		seen_ids[n.id] = i
	}
	if i + 1 >= n.subtree_end do return

	// The node is rebuilt every tick, so the answer Auto needs has to survive outside it.
	Storage(n.id, bit_set[ScrollAxis])^ = strips(n, n.content_size)
	arrange_children(i, inner_rect(i, n.rect))
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
			child.rect.h = cross_size(n, child, space_cross, .Vertical)
		}
	}

	used: f32
	count := 0
	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		used += size_along(state.nodes[c].rect, main)
		count += 1
	}
	used += gaps(n, count)
	offset, extra := justify(n.config.Justify, space_main - used, count)

	// The offset moves only the axes that scroll, and never past the content.
	scroll: Vec2
	if scrolls(n, .Vertical) || scrolls(n, .Horizontal) {
		scroll = ScrollOffset(n.id)
		if !scrolls(n, .Horizontal) do scroll.x = 0
		if !scrolls(n, .Vertical)   do scroll.y = 0
		scroll = {
			clamp(scroll.x, 0, max(n.content_size.x - inner.w, 0)),
			clamp(scroll.y, 0, max(n.content_size.y - inner.h, 0)),
		}
		SetScroll(scroll, n.id)
	}

	cursor := offset
	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		child := &state.nodes[c]
		at: f32
		#partial switch n.config.Align {
		case .Center: at = (space_cross - size_along(child.rect, cross)) / 2
		case .End:    at = space_cross - size_along(child.rect, cross)
		}
		pos := Vec2{cursor, at} if main == .Horizontal else Vec2{at, cursor}
		child.rect.x = inner.x + pos.x - scroll.x
		child.rect.y = inner.y + pos.y - scroll.y
		cursor += size_along(child.rect, main) + n.config.Gap + extra
		arrange(c)
	}
}

// layout runs the passes that size and place the frame, in the order CSS does: intrinsic
// widths from the inside out, final widths from the outside in, heights from the inside out
// once the widths are known, and finally positions from the outside in.
@(private)
layout :: proc() {
	size := viewport_size()
	measure_width(0)
	resolve_width(0, size.x)
	measure_height(0)
	state.nodes[0].rect = Rect{0, 0, size.x, size.y}
	arrange(0)
}
