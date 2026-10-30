package ui

Vec2  :: [2]f32
Rect  :: struct{ x, y, w, h: f32 }
Id    :: distinct u32
Color :: [4]u8

Direction :: enum u8 { Row, Column }

Justify :: enum u8 {
	Start,
	Center,
	End,
	SpaceBetween,
}

Align :: enum u8 {
	Start,
	Center,
	End,
	Stretch,
}

Padding :: struct {Left, Right, Top, Bottom: f32}

SizeKind :: enum u8 { Fit, Fixed }

Sizing :: struct {
	Kind:   SizeKind,
	Basis:  f32,
	Grow:   f32,
	Shrink: f32,
	Min:    f32,
	Max:    f32,
}

Border :: struct {
	Color: Color,
	Width: f32,
}

Style :: struct {
	Background: Color,
	Radius:     f32,
	Border:     Border,
	ScrollBar:  bool,
}

ScrollAxis :: enum u8 { Horizontal, Vertical }
Scroll :: bit_set[ScrollAxis]

LayoutConfig :: struct {
	Width:   Sizing,
	Height:  Sizing,
	Pad:     Padding,
	Gap:     f32,
	Justify: Justify,
	Align:   Align,
	Clip:    bool,
	Scroll:  Scroll,
}

TextConfig :: struct {
	Color: Color,
	Size:  f32,
}

ImageConfig :: struct {
	Size: Vec2,
	Tint: Color,
}

Node :: struct {
	config:      LayoutConfig,
	style:       Style,
	direction:   Direction,
	base:        Vec2,
	rect:        Rect,
	content:     Content,
	id:          Id,
	subtree_end: u32,
	draw:        DrawProc,
	draw_user:   rawptr,
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

// Scope is one level of the id stack: the seed new ids derive from, and how many
// elements have already been opened inside it.
@(private="file")
Scope :: struct {
	id:    Id,
	count: u32,
}

// Entry is one stored value: its bytes live on the heap, so the pointer stays
// valid across frames and across growth of the map.
@(private="file")
Entry :: struct {
	ptr:  rawptr,
	type: typeid,
}

State :: struct {
	nodes:  [dynamic]Node,
	stack:  [dynamic]u32,
	scopes: [dynamic]Scope,
	flexes: [dynamic]Flex,

	root_size: Vec2,

	rects:   map[Id]Rect,
	storage: map[Id]Entry,
}

@(private)
state: State

// AddViewportSize feeds the size of the surface the UI is laid out into, in
// pixels. Call it once per frame, before Begin.
AddViewportSize :: proc(Size: Vec2) {
	state.root_size = Size
}

// ViewportSize returns the size of the surface the UI is laid out into, in pixels.
ViewportSize :: proc() -> Vec2 {
	return state.root_size
}

// Storage returns the `T` stored under `Id`, allocating a zero value the first
// time the id is seen. Widgets keep their state here, keyed by their own id.
Storage :: proc(Id: Id, $T: typeid) -> ^T {
	if entry, ok := state.storage[Id]; ok {
		assert(entry.type == T, "Storage: same id used with two types")
		return (^T)(entry.ptr)
	}
	ptr := new(T)
	state.storage[Id] = {ptr = ptr, type = T}
	return ptr
}

// ScrollOffset returns the scroll offset stored for `Id`, in pixels. When `Id` is
// 0 it targets the last element declared.
ScrollOffset :: proc(Id: Id = 0) -> Vec2 {
	return Storage(target_id(Id), Vec2)^
}

// SetScroll stores the scroll offset for `Id`, in pixels. When `Id` is 0 it
// targets the last element declared.
SetScroll :: proc(Offset: Vec2, Id: Id = 0) {
	Storage(target_id(Id), Vec2)^ = Offset
}

// Begin starts a new frame: clears the node array and opens an implicit root
// node sized to the viewport, which becomes the parent of every top-level
// element. Must be paired with End.
Begin :: proc() {
	clear(&state.nodes)
	clear(&state.stack)
	clear(&state.scopes)
	append(&state.scopes, Scope{id = ROOT_SEED})
	Open({Width = Fixed(state.root_size.x), Height = Fixed(state.root_size.y)}, {}, .Column)
}

// End finishes the frame: closes the implicit root, computes layout and
// generates the draw commands. Must be paired with Begin. The hit-test rects of
// the previous frame stay readable until here, so widgets declared during the
// frame can query them.
End :: proc() {
	assert(len(state.stack) == 1, "unbalanced Open/Close: only the root should remain open at End()")
	Close()
	scroll_update()
	clear(&state.rects)
	draw_begin_frame()
	layout()
	draw_build()
	input_end_frame()
}

// Open pushes a new node onto the open stack and makes it the parent of
// everything declared until the matching Close. The node gets an id derived
// automatically from its parent and position. Returns the id. Prefer Row/Column
// for the common cases.
Open :: proc(Config: LayoutConfig = {}, Style: Style = {}, Direction: Direction = .Row) -> Id {
	parent := &state.scopes[len(state.scopes)-1]
	node_id := id_mix(parent.id, parent.count)
	parent.count += 1

	idx := u32(len(state.nodes))
	append(&state.nodes, Node{id = node_id, config = Config, style = Style, direction = Direction})
	append(&state.stack, idx)
	append(&state.scopes, Scope{id = node_id})
	return node_id
}

// Close pops the current node, finalizing its subtree. Calls must be in strict
// LIFO (Open/Close) order.
Close :: proc() #no_bounds_check {
	when ODIN_DEBUG {
		assert(len(state.stack) > 0, "Close without a matching Open")
		assert(
			state.scopes[len(state.scopes) - 1].id == state.nodes[len(state.nodes) - 1].id,
			"Close while a PushId is open",
		)
	}
	idx := pop(&state.stack)
	state.nodes[idx].subtree_end = u32(len(state.nodes))
	pop(&state.scopes)
}

// PushId opens a new id scope, so the elements declared inside it derive their
// ids from a fresh seed instead of the enclosing element. It must be closed
// explicitly with PopId.
PushId :: proc() {
	parent := &state.scopes[len(state.scopes)-1]
	append(&state.scopes, Scope{id = id_mix(parent.id, parent.count)})
	parent.count += 1
}

// PopId closes the scope opened by PushId.
PopId :: proc() {
	assert(len(state.scopes) > len(state.stack) + 1, "PopId without a matching PushId")
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

// Paint adds a leaf whose drawing is `Draw` and returns its id. `Config` sizes it
// like any other element, so it needs no Row or Column around it. The callback must
// only emit shapes, never declare elements.
Paint :: proc(Config: LayoutConfig = {}, Draw: DrawProc, User: rawptr = nil) -> Id #no_bounds_check {
	node_id := Open(Config)
	node := &state.nodes[len(state.nodes) - 1]
	node.draw = Draw
	node.draw_user = User
	Close()
	return node_id
}

// target_id resolves the target of an interaction query: `id` when given, or the
// last element declared, leaf or container, when 0.
@(private="file")
target_id :: #force_inline proc(id: Id) -> Id {
	if id != 0 do return id
	return state.nodes[len(state.nodes) - 1].id
}

// Hovered reports whether the pointer is inside `Id`, using the geometry from
// the previous frame. When `Id` is 0 it targets the last element declared.
Hovered :: proc(Id: Id = 0) -> bool {
	r, ok := state.rects[target_id(Id)]
	return ok && RectContains(r, MousePos())
}

// Active reports whether `Id` is being held down under the pointer. When `Id` is
// 0 it targets the last element declared.
Active :: proc(Id: Id = 0) -> bool {
	return Hovered(Id) && MouseDown(.Left)
}

// Clicked reports whether `Id` was clicked this frame: the button went up while
// the pointer was over it. It is the release edge, not the press. When `Id` is 0
// it targets the last element declared.
Clicked :: proc(Id: Id = 0) -> bool {
	return Hovered(Id) && MouseReleased(.Left)
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

// box_size applies the box model to a content size: padding and border sit
// inside the box, then the axis sizing (fixed and min/max) resolves each axis.
@(private="file")
box_size :: proc(n: ^Node, content: Vec2) -> Vec2 {
	p  := n.config.Pad
	bw := n.style.Border.Width * 2
	return {
		resolve_axis(n.config.Width,  content.x + p.Left + p.Right + bw),
		resolve_axis(n.config.Height, content.y + p.Top  + p.Bottom + bw),
	}
}

// Flex is a child's record during main-axis distribution: its base size, its
// flexibility and range, and the size resolved for it.
@(private="file")
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

// inner_rect returns the rect left inside a node after its padding and border,
// never smaller than zero.
@(private)
inner_rect :: proc(n: ^Node, rect: Rect) -> Rect {
	p  := n.config.Pad
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
	when ODIN_DEBUG {
		assert(n.id not_in state.rects, "duplicate element id")
	}
	state.rects[n.id] = rect
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

// scroll_update turns the wheel into scroll for the innermost container under the
// pointer. It reads the rects of the previous frame, walking the nodes backwards so
// the last match is the deepest one.
@(private="file")
scroll_update :: proc() {
	wheel := MouseWheel()
	if wheel == 0 do return

	// One wheel notch scrolls this many pixels.
	STEP :: 40

	pos := MousePos()
	for i := len(state.nodes) - 1; i >= 0; i -= 1 {
		n := &state.nodes[i]
		if n.config.Scroll == {} do continue
		r, ok := state.rects[n.id]
		if !ok || !RectContains(r, pos) do continue

		s := ScrollOffset(n.id)
		if .Vertical   in n.config.Scroll do s.y -= wheel.y * STEP
		if .Horizontal in n.config.Scroll do s.x -= wheel.x * STEP
		SetScroll(s, n.id)
		break
	}
}

@(private="file")
layout :: proc() {
	measure_pass()
	arrange(0, Rect{0, 0, state.root_size.x, state.root_size.y})
}
