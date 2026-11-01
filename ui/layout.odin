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

Node :: struct {
	config:      LayoutConfig,
	style:       Style,
	direction:   Direction,
	base:        Vec2,
	rect:        Rect,
	clip:        Rect,
	content:     Content,
	id:          Id,
	subtree_end: u32,
	draw:        DrawProc,
}

TextContent :: struct {
	text:   cstring,
	font:   Font,
	config: TextConfig
}

ImageContent :: struct {
	handle: rawptr,
	config: ImageConfig
}

Content :: union {
	TextContent,
	ImageContent,
}

// Begin starts a new frame: clears the node array and opens an implicit root
// node sized to the viewport, which becomes the parent of every top-level
// element. Must be paired with End.
Begin :: proc() {
	interaction_begin()
	scrollbar_update()
	scroll_update()
	clear(&state.nodes)
	clear(&state.scopes)
	when CHECKS {
		clear(&seen_ids)
	}
	append(&state.scopes, Scope{id = ROOT_SEED, node = NO_NODE})
	Open({Width = Fixed(state.root_size.x), Height = Fixed(state.root_size.y)}, {}, .Column)
}

// End finishes the frame: closes the implicit root, computes layout and
// generates the draw commands. Must be paired with Begin. Each node keeps the rect
// and the clip of the frame that drew it, so widgets declared during the frame can
// query the geometry of the previous one.
End :: proc() {
	if len(state.scopes) != 2 || state.scopes[1].node == NO_NODE {
		report("ui: unbalanced Open/Close, or an open PushId, at End")
	}
	Close()
	draw_begin_frame()
	layout()
	draw_build()
	input_end_frame()
}

// Open opens a new node and makes it the parent of everything declared until the
// matching Close. The node gets an id derived automatically from its parent and
// position. Returns the id. Prefer Row/Column for the common cases.
Open :: proc(Config: LayoutConfig = {}, Style: Style = {}, Direction: Direction = .Row) -> Id {
	parent := &state.scopes[len(state.scopes)-1]
	node_id := id_mix(parent.id, parent.count)
	parent.count += 1

	idx := u32(len(state.nodes))
	append(&state.nodes, Node{id = node_id, config = Config, style = Style, direction = Direction})
	append(&state.scopes, Scope{id = node_id, node = idx})
	return node_id
}

// Close pops the current node, finalizing its subtree. Calls must be in strict
// LIFO (Open/Close) order.
Close :: proc() #no_bounds_check {
	if len(state.scopes) <= 1 {
		report("ui: Close without a matching Open")
		return
	}
	scope := pop(&state.scopes)
	if scope.node == NO_NODE {
		report("ui: Close called while a PushId is open")
		return
	}
	state.nodes[scope.node].subtree_end = u32(len(state.nodes))
}

// PushId opens a new id scope, so the elements declared inside it derive their
// ids from a fresh seed instead of the enclosing element. It must be closed
// explicitly with PopId.
PushId :: proc() {
	parent := &state.scopes[len(state.scopes)-1]
	append(&state.scopes, Scope{id = id_mix(parent.id, parent.count), node = NO_NODE})
	parent.count += 1
}

// PopId closes the scope opened by PushId.
PopId :: proc() {
	if len(state.scopes) <= 1 || state.scopes[len(state.scopes) - 1].node != NO_NODE {
		report("ui: PopId without a matching PushId")
		return
	}
	pop(&state.scopes)
}

// Row opens a node that lays its children out left to right. Returns true so it
// can be used as `if Row(...) { ... }`; the node closes automatically at the end
// of the block.
@(require_results, deferred_none = Close)
Row :: proc(Config: LayoutConfig = {}, Style: Style = {}) -> bool {
	Open(Config, Style, .Row)
	return true
}

// Column opens a node that lays its children out top to bottom. Returns true so
// it can be used as `if Column(...) { ... }`; the node closes automatically at
// the end of the block.
@(require_results, deferred_none = Close)
Column :: proc(Config: LayoutConfig = {}, Style: Style = {}) -> bool {
	Open(Config, Style, .Column)
	return true
}

// Label adds a text leaf to the currently open node and returns its id, so it
// can be the target of Hovered/Clicked.
Label :: proc(
	Text:  cstring,
	Color: Color = {255, 255, 255, 255},
	Size:  f32 = 16,
	Font:  Font = 0,
) -> Id #no_bounds_check {
	node_id := Open()
	state.nodes[len(state.nodes)-1].content = TextContent{
		text = Text, font = Font, config = TextConfig{Color = Color, Size = Size},
	}
	Close()
	return node_id
}


// Image adds an image leaf to the currently open node and returns its id, so it
// can be the target of Hovered/Clicked.
Image :: proc(Handle: rawptr, Size: Vec2, Tint: Color = {255, 255, 255, 255}) -> Id #no_bounds_check {
	node_id := Open()
	state.nodes[len(state.nodes)-1].content = ImageContent{
		handle = Handle,
		config = ImageConfig{Size = Size, Tint = Tint},
	}
	Close()
	return node_id
}

// Paint adds a leaf whose drawing is `Draw` and returns its id. It is sized like any
// other element, so it needs no Row or Column around it. The callback must only emit
// shapes, never declare elements.
Paint :: proc(
	Draw:   DrawProc,
	Width:  Sizing = {Kind = .Fixed, Grow = 1},
	Height: Sizing = {Kind = .Fixed, Grow = 1},
) -> Id #no_bounds_check {
	node_id := Open({Width = Width, Height = Height})
	state.nodes[len(state.nodes) - 1].draw = Draw
	Close()
	return node_id
}

// The root of every frame's id tree; ids derive from it down the hierarchy.
@(private="file")
ROOT_SEED :: Id(0x9e3779b9)

// id_mix folds `n` into `seed` to derive a child's id. It is a 32-bit avalanche
// hash, so neighbouring positions land far apart, and never returns 0 (0 is
// reserved for "the last element").
@(private="file")
id_mix :: #force_inline proc(seed: Id, n: u32) -> Id {
	h := u32(seed) ~ n
	h ~= h >> 16
	h *= 0x7feb352d
	h ~= h >> 15
	h *= 0x846ca68b
	h ~= h >> 16
	if h == 0 do h = 1
	return Id(h)
}

// In a Row the main axis is horizontal and the cross axis is vertical; in a
// Column they are swapped. These helpers move a value between the two frames,
// so the layout passes below never mention a direction directly.
@(private="file")
main_of :: #force_inline proc(d: Direction, v: Vec2) -> f32 {
	return v.x if d == .Row else v.y
}

@(private="file")
cross_of :: #force_inline proc(d: Direction, v: Vec2) -> f32 {
	return v.y if d == .Row else v.x
}

@(private="file")
from_main :: #force_inline proc(d: Direction, main, cross: f32) -> Vec2 {
	return {main, cross} if d == .Row else {cross, main}
}

@(private="file")
main_sizing :: #force_inline proc(d: Direction, c: LayoutConfig) -> Sizing {
	return c.Width if d == .Row else c.Height
}

@(private="file")
cross_sizing :: #force_inline proc(d: Direction, c: LayoutConfig) -> Sizing {
	return c.Height if d == .Row else c.Width
}

// The layout passes index `state.nodes` only through indices known to be inside
// it: a node's children precede its `subtree_end`, which never exceeds
// len(nodes), and Open appends before any access. That invariant lets the passes
// below drop bounds checks; a broken invariant turns into memory access rather
// than a panic, so keep it.

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

// measure_pass computes every node's base size, bottom-up. A node's children
// always come after it in the DFS pre-order array, so iterating backwards
// measures children before their parent.
@(private="file")
measure_pass :: proc() #no_bounds_check {
	for i := len(state.nodes) - 1; i >= 0; i -= 1 {
		n := &state.nodes[i]
		n.base = box_size(n, intrinsic_size(u32(i)))
	}
}

// intrinsic_size returns the natural size of a node's content, before padding,
// border and sizing are applied. For a leaf it is the measured text or the image
// size; for a container, the sum of its children along the main axis (plus gaps)
// and the largest of them along the cross axis.
@(private)
intrinsic_size :: proc(i: u32) -> Vec2 #no_bounds_check {
	n := &state.nodes[i]
	#partial switch content in n.content {
		case TextContent:
			return MeasureText(content.text, content.font, content.config.Size)
		case ImageContent:
			return content.config.Size
	}

	d := n.direction
	main, cross: f32
	count := 0
	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		base := state.nodes[c].base
		main += main_of(d, base)
		cross = max(cross, cross_of(d, base))
		count += 1
	}
	if count > 1 do main += n.config.Gap * f32(count - 1)
	return from_main(d, main, cross)
}

// padding returns the node's padding with the scroll bar strip added to the trailing
// edge of the axes that show one, so the strip is measured and laid out exactly like
// padding.
@(private)
padding :: proc(n: ^Node) -> Padding {
	p := n.config.Pad
	if n.style.ScrollBar {
		if .Vertical in n.config.Scroll do p.Right += SCROLLBAR_THICKNESS + SCROLLBAR_GAP
		if .Horizontal in n.config.Scroll do p.Bottom += SCROLLBAR_THICKNESS + SCROLLBAR_GAP
	}
	return p
}

// box_size applies the box model to a content size: padding and border sit
// inside the box, then the axis sizing (fixed and min/max) resolves each axis.
@(private="file")
box_size :: proc(n: ^Node, content: Vec2) -> Vec2 {
	p  := padding(n)
	bw := n.style.Border.Width * 2
	return {
		resolve_axis(n.config.Width,  content.x + p.Left + p.Right + bw),
		resolve_axis(n.config.Height, content.y + p.Top  + p.Bottom + bw),
	}
}

// Flex is a child's record during main-axis distribution: its base size, its
// flexibility and range, and the size resolved for it.
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

// collect_flex gathers the direct children of node i into the reused scratch,
// recording each one's base main size and flexibility.
@(private="file")
collect_flex :: proc(i: u32) -> []Flex #no_bounds_check {
	n := &state.nodes[i]
	clear(&state.flexes)
	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		child := &state.nodes[c]
		s := main_sizing(n.direction, child.config)
		append(&state.flexes, Flex{
			node   = c,
			base   = main_of(n.direction, child.base),
			grow   = s.Grow,
			shrink = s.Shrink,
			min    = s.Min,
			max    = s.Max,
		})
	}
	return state.flexes[:]
}

// flex_weight is an item's claim on the free space: its grow on a surplus, its
// shrink scaled by its base on a deficit.
@(private="file")
flex_weight :: #force_inline proc(it: Flex, free: f32) -> f32 {
	return it.grow if free > 0 else it.shrink * it.base
}

// resolve_flex distributes the leftover `free` main-axis space among the items.
// An item that reaches its min or max is frozen at that bound and the rest is
// re-shared, until nothing clamps.
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

// inner_rect returns the rect left inside a node after its padding and border, never
// smaller than zero. The padding it uses already carries the scroll bar strip.
@(private)
inner_rect :: proc(n: ^Node, rect: Rect) -> Rect {
	p  := padding(n)
	bw := n.style.Border.Width
	return {
		rect.x + p.Left + bw,
		rect.y + p.Top + bw,
		max(rect.w - p.Left - p.Right - bw*2, 0),
		max(rect.h - p.Top - p.Bottom - bw*2, 0),
	}
}

// justify returns the leading offset and the extra gap between children that
// spread the leftover `free` space along the main axis.
@(private="file")
justify :: proc(j: Justify, free: f32, count: int) -> (offset, gap: f32) {
	#partial switch j {
		case .Center: offset = free / 2
		case .End:    offset = free
		case .SpaceBetween: if count > 1 do gap = free / f32(count - 1)
	}
	return
}

// cross_axis resolves a child's size and offset along the container's cross
// axis: it fills the axis when the child grows there, or when the container
// stretches and the child did not fix its size; otherwise it is aligned.
@(private="file")
cross_axis :: proc(n: ^Node, child: ^Node, cross_inner: f32, d: Direction) -> (size, pos: f32) {
	s := cross_sizing(d, child.config)
	if s.Grow > 0 || (n.config.Align == .Stretch && s.Kind == .Fit) {
		size = cross_inner
	} else {
		size = cross_of(d, child.base)
	}
	if s.Min != 0 do size = max(size, s.Min)
	if s.Max != 0 do size = min(size, s.Max)

	#partial switch n.config.Align {
		case .Center: pos = (cross_inner - size) / 2
		case .End:    pos = cross_inner - size
	}
	return
}

// arrange assigns node i its final rect and lays out its subtree, top-down: a
// node's rect must be known before its children can be sized.
@(private="file")
arrange :: proc(i: u32, rect: Rect) #no_bounds_check {
	n := &state.nodes[i]
	n.rect = rect
	when CHECKS {
		if previous, seen := seen_ids[n.id]; seen {
			report(fmt.ctprintf("ui: duplicate element id at node %v and node %v", previous, i))
		}
		seen_ids[n.id] = i
	}
	if i + 1 >= n.subtree_end do return
	arrange_children(i, inner_rect(n, rect))
}

// arrange_children distributes the space inside `inner` among node i's children
// and recurses into each of them. It sizes every child before recursing, since
// recursing reuses the shared flex scratch.
@(private)
arrange_children :: proc(i: u32, inner: Rect) #no_bounds_check {
	n := &state.nodes[i]
	d := n.direction
	content := intrinsic_size(i)

	// An axis that scrolls hands its children the content's size instead of the
	// visible one, so nothing is squeezed to fit and the overflow is real.
	main_inner := main_of(d, {inner.w, inner.h})
	if (ScrollAxis.Vertical if d == .Column else .Horizontal) in n.config.Scroll {
		main_inner = main_of(d, content)
	}
	cross_inner := cross_of(d, {inner.w, inner.h})
	if (ScrollAxis.Horizontal if d == .Column else .Vertical) in n.config.Scroll {
		cross_inner = cross_of(d, content)
	}

	items := collect_flex(i)
	base_sum: f32
	for it in items do base_sum += it.base
	free := main_inner - base_sum - n.config.Gap * f32(max(len(items)-1, 0))
	resolve_flex(items, free)

	used := n.config.Gap * f32(max(len(items)-1, 0))
	for it in items do used += it.size
	offset, extra := justify(n.config.Justify, main_inner - used, len(items))

	// The offset moves only the axes that scroll, and never past the content.
	scroll: Vec2
	if n.config.Scroll != {} {
		scroll = ScrollOffset(n.id)
		if .Horizontal not_in n.config.Scroll do scroll.x = 0
		if .Vertical not_in n.config.Scroll do scroll.y = 0
		scroll = {
			clamp(scroll.x, 0, max(content.x - inner.w, 0)),
			clamp(scroll.y, 0, max(content.y - inner.h, 0)),
		}
		SetScroll(scroll, n.id)
	}

	cursor := offset
	for it in items {
		child := &state.nodes[it.node]
		cross_size, cross_pos := cross_axis(n, child, cross_inner, d)
		size := from_main(d, it.size, cross_size)
		pos  := from_main(d, cursor, cross_pos)
		child.rect = Rect{inner.x + pos.x - scroll.x, inner.y + pos.y - scroll.y, size.x, size.y}
		cursor += it.size + n.config.Gap + extra
	}

	for c := i + 1; c < n.subtree_end; c = next_sibling(c) {
		arrange(c, state.nodes[c].rect)
	}
}

@(private="file")
layout :: proc() {
	measure_pass()
	arrange(0, Rect{0, 0, state.root_size.x, state.root_size.y})
}

