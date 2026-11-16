package ui

// Begin starts a new frame: it feeds the input, clears the node array and opens an implicit
// root node sized to the viewport. Must be paired with End.
Begin :: proc() {
	interaction_begin()
	scrollbar_update()
	focus_begin()
	scroll_update()
	clear(&state.nodes)
	clear(&state.scopes)
	clear(&state.floats)
	label_purge()
	state.tick += 1
	state.cursor = .Arrow
	when CHECKS {
		clear(&seen_ids)
	}
	append(&state.scopes, Scope{id = ROOT_SEED, node = NO_NODE})
	size := viewport_size()
	Open({Width = Fixed(size.x), Height = Fixed(size.y), Hit = .Pass}, {}, .Column)
}

// End finishes the frame: closes the implicit root, lays the tree out and builds the draw
// list. Each node keeps the rect and the clip it was drawn with, so widgets declared in this
// frame can query the geometry of it. Must be paired with Begin.
End :: proc() {
	if len(state.scopes) != 2 || state.scopes[1].node == NO_NODE {
		report("ui: unbalanced Open/Close, or an open PushId, at End")
	}
	Close()
	draw_begin_frame()
	layout()
	draw_build()
	drag_drop_end()
	input_end_frame()
}

// Open opens a new node and makes it the parent of everything declared until the matching
// Close, with an id derived from its parent and position. Prefer Row/Column for the common
// cases.
Open :: proc(Config: LayoutConfig = {}, Style: Style = {}, Direction: Direction = .Row) -> Id {
	parent := &state.scopes[len(state.scopes)-1]
	node_id := id_mix(parent.id, parent.count)
	parent.count += 1

	idx := u32(len(state.nodes))
	append(&state.nodes, Node{id = node_id, config = Config, style = Style, direction = Direction})
	append(&state.scopes, Scope{id = node_id, node = idx})
	return node_id
}

// Close pops the current node, finalizing its subtree. Calls must nest in strict LIFO order.
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

// LastId returns the id of the last element declared, leaf or container. The interaction
// queries take it when no id is passed.
LastId :: proc() -> Id #no_bounds_check {
	return state.nodes[len(state.nodes) - 1].id
}

// SetStyle replaces the style of the element `Id`, which must have been declared this frame.
// Widgets use it to pick the visual of an interaction state after opening the element.
SetStyle :: proc(Id: Id, Style: Style) {
	if i := node_of(Id); i != NO_NODE {
		state.nodes[i].style = Style
	} else {
		report("ui: SetStyle without a matching element")
	}
}

// Bounds returns the rect the element was laid out with, as of the last End. An `Id` of 0
// targets the last element declared.
Bounds :: proc(Id: Id = 0) -> Rect {
	if i := node_of(target_id(Id)); i != NO_NODE {
		return state.nodes[i].rect
	}
	return {}
}

// PushId opens a new id scope, so the elements inside derive their ids from a fresh seed
// instead of the enclosing element. Close it with PopId.
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

// Row opens a node that lays its children out left to right, as `if Row(...) { ... }`. The
// node closes at the end of the block.
@(require_results, deferred_none = Close)
Row :: proc(Config: LayoutConfig = {}, Style: Style = {}) -> bool {
	Open(Config, Style, .Row)
	return true
}

// Column opens a node that lays its children out top to bottom, as `if Column(...) { ... }`.
// The node closes at the end of the block.
@(require_results, deferred_none = Close)
Column :: proc(Config: LayoutConfig = {}, Style: Style = {}) -> bool {
	Open(Config, Style, .Column)
	return true
}

// AnchorKind is an anchor that carries no element id: the element the floating node was
// declared in, the viewport, or the pointer.
AnchorKind :: enum u8 {
	Parent,
	Root,
	Pointer,
}

// Anchor is what a floating node is placed against: an element id, or an `AnchorKind` for the
// element it was declared in, the viewport, or the pointer.
Anchor :: union {
	Id,
	AnchorKind,
}

// Float is one element out of the flow: the node it opened and where it is placed.
@(private)
Float :: struct {
	node:   u32,
	anchor: Anchor,
	offset: Vec2,
	pivot:  Vec2,
}

// Floating opens a node out of the flow at `Offset` from `Anchor`, painted and hit above the
// tree. `Pivot` picks the point of the float that lands on the anchor, and the rect is clamped
// to the viewport. The block is its scope, and `LastId` is its id.
@(require_results, deferred_none = Close)
Floating :: proc(
	Anchor:    Anchor = AnchorKind.Parent,
	Offset:    Vec2 = {},
	Pivot:     Vec2 = {},
	Config:    LayoutConfig = {},
	Style:     Style = {},
	Direction: Direction = .Column,
) -> bool #no_bounds_check {
	Open(Config, Style, Direction)
	state.nodes[len(state.nodes) - 1].floating = true
	append(&state.floats, Float{
		node   = u32(len(state.nodes) - 1),
		anchor = Anchor,
		offset = Offset,
		pivot  = Pivot,
	})
	return true
}

// Label adds a text leaf and returns its id, so it can be the target of Hovered/Clicked. `Color`
// and `Size` stay loose since a zero color is a real value; `Width`, `Height` and `Hit` describe
// the box, and the rest paints it.
Label :: proc(
	Text:   cstring,
	Width:  Sizing = {},
	Height: Sizing = {},
	Hit:    HitMode = .Auto,
	Color:  Color = {255, 255, 255, 255},
	Size:   f32 = 16,
	Font:   Font = 0,
	Wrap:   WrapMode = .None,
	Align:  TextAlign = .Left,
	Style:  Style = {},
) -> Id #no_bounds_check {
	node_id := Open({Width = Width, Height = Height, Hit = Hit}, Style)
	state.nodes[len(state.nodes)-1].content = TextContent{
		text  = Text,
		font  = Font,
		color = Color,
		size  = Size,
		wrap  = Wrap,
		align = Align,
	}
	Close()
	return node_id
}

// Image adds an image leaf and returns its id. `Width` and `Height` default to the texture
// size, `Hit` is how the leaf answers the pointer, `Fit` how the texture fills the rect, and
// `Style` paints the box.
Image :: proc(
	Handle: Texture,
	Width:  Sizing = {},
	Height: Sizing = {},
	Hit:    HitMode = .Auto,
	Tint:   Color = {255, 255, 255, 255},
	Fit:    ImageFit = .Stretch,
	Style:  Style = {},
) -> Id #no_bounds_check {
	node_id := Open({Width = Width, Height = Height, Hit = Hit}, Style)
	state.nodes[len(state.nodes)-1].content = ImageContent{
		handle = Handle,
		config = ImageConfig{Tint = Tint, Fit = Fit},
	}
	Close()
	return node_id
}

// Paint adds a sized leaf whose painting is `Fn` and returns its id, so it needs no Row or
// Column around it. `Hit` is how it answers the pointer, and the callback draws inside the rect
// and emits only shapes.
Paint :: proc(
	Fn:     PaintProc,
	Width:  Sizing = {Kind = .Fixed, Grow = 1},
	Height: Sizing = {Kind = .Fixed, Grow = 1},
	Hit:    HitMode = .Auto,
	Style:  Style = {},
) -> Id #no_bounds_check {
	node_id := Open({Width = Width, Height = Height, Hit = Hit}, Style)
	state.nodes[len(state.nodes) - 1].content = Fn
	Close()
	return node_id
}

// The root of every frame's id tree; ids derive from it down the hierarchy.
@(private="file")
ROOT_SEED :: Id(0x9e3779b9)

// id_mix folds `n` into `seed` to derive a child's id. It is a 32-bit avalanche hash, so
// neighbouring positions land far apart, and never returns 0 (0 means the last element).
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
