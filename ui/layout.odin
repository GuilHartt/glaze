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
	draw:         DrawProc,
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
	label_purge()
	state.frame += 1
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
	Wrap:  WrapMode = .None,
	Align: TextAlign = .Left,
) -> Id #no_bounds_check {
	node_id := Open()
	state.nodes[len(state.nodes)-1].content = TextContent{
		text = Text,
		font = Font,
		config = TextConfig{Color = Color, Size = Size, Wrap = Wrap, Align = Align},
	}
	Close()
	return node_id
}

// Image adds an image leaf and returns its id. `Width` and `Height` size the leaf,
// defaulting to the texture size, and `Fit` is how the texture fills the rect.
Image :: proc(
	Handle: Texture,
	Width:  Sizing = {},
	Height: Sizing = {},
	Tint:   Color = {255, 255, 255, 255},
	Fit:    ImageFit = .Stretch,
) -> Id #no_bounds_check {
	node_id := Open({Width = Width, Height = Height})
	state.nodes[len(state.nodes)-1].content = ImageContent{
		handle = Handle,
		config = ImageConfig{Tint = Tint, Fit = Fit},
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

// scroll_mode returns how `Axis` scrolls.
@(private)
scroll_mode :: #force_inline proc "contextless" (n: ^Node, Axis: ScrollAxis) -> ScrollMode {
	return n.config.Scroll.Vertical if Axis == .Vertical else n.config.Scroll.Horizontal
}

// scrolls reports whether `Axis` moves at all, which every mode but Disabled does.
@(private)
scrolls :: #force_inline proc "contextless" (n: ^Node, Axis: ScrollAxis) -> bool {
	return scroll_mode(n, Axis) != .Disabled
}

// shows_bar reports whether the bar of `Axis` is drawn. Auto and Reserve measure the
// content against the box the node was given, which the arrangement has already set.
@(private)
shows_bar :: proc(n: ^Node, Axis: ScrollAxis, content: Vec2) -> bool {
	p  := n.config.Pad
	bw := n.style.Border.Width * 2

	#partial switch scroll_mode(n, Axis) {
	case .Always:
		return true
	case .Auto, .Reserve:
		if Axis == .Vertical {
			return content.y > max(n.rect.h - p.Top - p.Bottom - bw, 0)
		}
		return content.x > max(n.rect.w - p.Left - p.Right - bw, 0)
	}
	return false
}

// strips returns the axes whose strip is taken from the content. Reserve keeps it
// even while the bar is hidden, so the content never moves.
@(private)
strips :: proc(n: ^Node, content: Vec2) -> bit_set[ScrollAxis] {
	out: bit_set[ScrollAxis]

	if scroll_mode(n, .Vertical) == .Reserve || shows_bar(n, .Vertical, content) {
		out += {.Vertical}
	}
	if scroll_mode(n, .Horizontal) == .Reserve || shows_bar(n, .Horizontal, content) {
		out += {.Horizontal}
	}
	return out
}

// strip_reserved reports whether the strip of `Axis` is out of the content for this
// frame. Always and Reserve answer without looking at the content, so only Auto reads
// the answer the arrangement stored in the frame that just ended.
@(private)
strip_reserved :: proc(n: ^Node, Axis: ScrollAxis) -> bool {
	#partial switch scroll_mode(n, Axis) {
	case .Always, .Reserve:
		return true
	case .Auto:
		return Axis in Storage(n.id, bit_set[ScrollAxis])^
	}
	return false
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
// recording each one's base size along `A` and its flexibility there.
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
// smaller than zero. The padding already carries the strips of the bars it draws.
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

// justify returns the leading offset and the extra gap between children that
// spread the leftover `free` space along the main axis.
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

// children_space returns the length the children share along `A`. A node that scrolls
// that axis hands them its content length, so the overflow is real instead of squeezed.
@(private="file")
children_space :: proc(n: ^Node, A: ScrollAxis, inner: f32) -> f32 {
	if scrolls(n, A) do return along(n.content_size, A)
	return inner
}

// cross_size resolves a child's size along an axis its parent does not lay out. The
// child fills the space when it grows there, or when the parent stretches a child that
// fits its content, and a wrapping text never runs past the space it was given.
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

// measure_width gives every node its intrinsic width, bottom up, before any width is
// known. A text leaf measures unwrapped, so its width is its longest line, and a
// container adds its children up along a Row and takes the widest one in a Column.
@(private="file")
measure_width :: proc(i: u32) #no_bounds_check {
	n := &state.nodes[i]
	n.strips = {}
	if strip_reserved(n, .Vertical) do n.strips += {.Vertical}
	if strip_reserved(n, .Horizontal) do n.strips += {.Horizontal}

	switch &content in n.content {
	case TextContent:
		n.content_size, content.lines = label_measure(content, 0)
	case ImageContent:
		n.content_size = {content.handle.Width, content.handle.Height}
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

// layout_width fixes the width of node i to the one its parent gave it, then shares the
// inner width among its children: a Row splits it along X by flex, a Column gives each
// child its cross size. Each child's width is final before its own children are placed,
// so a text can wrap against it later.
@(private="file")
layout_width :: proc(i: u32, Width: f32) #no_bounds_check {
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
		layout_width(c, state.nodes[c].rect.w)
	}
}

// measure_height gives every node its intrinsic height, bottom up, once every width is
// final. A wrapping text breaks its lines against the width it was given, so its height
// is the height of those lines. A container stacks its children along a Column and takes
// the tallest one in a Row.
@(private="file")
measure_height :: proc(i: u32) #no_bounds_check {
	n := &state.nodes[i]
	switch &content in n.content {
	case TextContent:
		if content.config.Wrap != .None {
			n.content_size, content.lines = label_measure(content, max(n.rect.w - inset(n).x, 0))
		}
	case ImageContent:
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
// parent, so this pass resolves the heights along a Column, places each child, and writes
// the scroll bar state the next frame's Auto answers come from.
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

	// The node is rebuilt every frame, so the answer Auto needs before measuring the
	// next one has to survive outside it.
	Storage(n.id, bit_set[ScrollAxis])^ = strips(n, n.content_size)
	arrange_children(i, inner_rect(i, n.rect))
}

// arrange_children sizes the children of node i along its main axis, where a Column
// resolves heights by flex, and along its cross axis, where a Row resolves heights.
// Then it places each child and arranges its subtree. The widths of a Row and the cross
// widths of a Column were already fixed by layout_width.
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
@(private="file")
layout :: proc() {
	measure_width(0)
	layout_width(0, state.root_size.x)
	measure_height(0)
	state.nodes[0].rect = Rect{0, 0, state.root_size.x, state.root_size.y}
	arrange(0)
}
