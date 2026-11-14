package ui

// Begin starts a new frame: it feeds the input, clears the node array and opens an implicit
// root node sized to the viewport. Must be paired with End.
Begin :: proc() {
	interaction_begin()
	scrollbar_update()
	scroll_update()
	clear(&state.nodes)
	clear(&state.scopes)
	label_purge()
	state.tick += 1
	when CHECKS {
		clear(&seen_ids)
	}
	append(&state.scopes, Scope{id = ROOT_SEED, node = NO_NODE})
	size := viewport_size()
	Open({Width = Fixed(size.x), Height = Fixed(size.y)}, {}, .Column)
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

// Label adds a text leaf to the open node and returns its id, so it can be the target of
// Hovered/Clicked.
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

// Image adds an image leaf and returns its id. `Width` and `Height` size the leaf, defaulting
// to the texture size, and `Fit` is how the texture fills the rect.
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

// Paint adds a sized leaf whose drawing is `Draw` and returns its id, so it needs no Row or
// Column around it. The callback draws inside the rect and emits only shapes.
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
