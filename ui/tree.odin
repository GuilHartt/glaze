package ui

import "base:runtime"

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
	clear(&state.user_data)
	label_purge()
	state.frame += 1
	state.cursor = .Arrow
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
Open :: proc(Config: ContainerConfig = {}, Style: BoxStyle = {}, Direction: Direction = .Row) -> ElementId {
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
LastId :: proc() -> ElementId #no_bounds_check {
	if len(state.nodes) == 0 do return 0
	return state.nodes[len(state.nodes) - 1].id
}

// SetStyle replaces the style of the element `Element`, which must have been declared this frame.
// Widgets use it to pick the visual of an interaction state after opening the element.
SetStyle :: proc(Element: ElementId, Style: BoxStyle) {
	if i := node_of(Element); i != NO_NODE {
		state.nodes[i].style = Style
	} else {
		report("ui: SetStyle without a matching element")
	}
}

// ElementRect returns the rect the element was laid out with in the last finished layout: the
// previous frame while a frame is being declared, and the frame just finished after End. An
// `Element` of 0 targets the last element declared.
ElementRect :: proc(Element: ElementId = 0) -> Rect {
	target := target_id(Element)

	// The last element declared usually shares its index with the previous layout.
	if last := len(state.nodes) - 1; last >= 0 {
		if prev := prev_at(u32(last)); prev.frame == state.published && prev.id == target {
			return prev.rect
		}
	}

	#reverse for &prev in state.prev {
		if prev.frame == state.published && prev.id == target do return prev.rect
	}
	return {}
}

// PushId opens a new id scope, so the elements inside derive their ids from a fresh seed
// instead of the enclosing element. A `Seed` of 0 derives the scope from the parent and the
// position; any other `Seed` keeps it stable when a list is reordered. Close it with PopId.
PushId :: proc(Seed: u32 = 0) {
	parent := &state.scopes[len(state.scopes)-1]
	seed := Seed if Seed != 0 else parent.count
	append(&state.scopes, Scope{id = id_mix(parent.id, seed), node = NO_NODE})
	if Seed == 0 do parent.count += 1
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
Row :: proc(Config: ContainerConfig = {}, Style: BoxStyle = {}) -> bool {
	Open(Config, Style, .Row)
	return true
}

// Column opens a node that lays its children out top to bottom, as `if Column(...) { ... }`.
// The node closes at the end of the block.
@(require_results, deferred_none = Close)
Column :: proc(Config: ContainerConfig = {}, Style: BoxStyle = {}) -> bool {
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
	ElementId,
	AnchorKind,
}

// Float is one element out of the flow: the node it opened, the node it was declared in, and
// where it is placed.
@(private)
Float :: struct {
	node:   u32,
	parent: u32,
	anchor: Anchor,
	offset: Vec2,
	pivot:  Vec2,
}

// current_parent returns the node the next element is declared in, skipping PushId scopes.
@(private="file")
current_parent :: proc() -> u32 {
	#reverse for scope in state.scopes {
		if scope.node != NO_NODE do return scope.node
	}
	return NO_NODE
}

// Floating opens a node out of the flow at `Offset` from `Anchor`, painted and hit above the
// tree. `Pivot` picks the point of the float that lands on the anchor, and the rect is clamped
// to the viewport. The block is its scope, and `LastId` is its id.
@(require_results, deferred_none = Close)
Floating :: proc(
	Anchor:    Anchor = AnchorKind.Parent,
	Offset:    Vec2 = {},
	Pivot:     Vec2 = {},
	Config:    ContainerConfig = {},
	Style:     BoxStyle = {},
	Direction: Direction = .Column,
) -> bool #no_bounds_check {
	parent := current_parent()
	Open(Config, Style, Direction)
	state.nodes[len(state.nodes) - 1].floating = true
	append(&state.floats, Float{
		node   = u32(len(state.nodes) - 1),
		parent = parent,
		anchor = Anchor,
		offset = Offset,
		pivot  = Pivot,
	})
	return true
}

// Label adds a text leaf and returns its id, so it can be the target of Hovered/Clicked. `Config`
// is the box, and `Style` paints it and the text inside.
Label :: proc(Text: cstring, Config: ElementConfig = {}, Style: LabelStyle = {}) -> ElementId #no_bounds_check {
	node_id := Open({base = Config}, Style.Box)
	state.nodes[len(state.nodes)-1].content = TextContent{
		text  = Text,
		font  = Style.Font,
		color = Style.Color.? or_else {255, 255, 255, 255},
		size  = Style.Size.? or_else 16,
		wrap  = Style.Wrap,
		align = Style.Align,
	}
	Close()
	return node_id
}

// Image adds an image leaf and returns its id. `Config` is the box, defaulting to the texture
// size, and `Style` paints the box and the texture.
Image :: proc(Handle: Texture, Config: ElementConfig = {}, Style: ImageStyle = {}) -> ElementId #no_bounds_check {
	node_id := Open({base = Config}, Style.Box)
	state.nodes[len(state.nodes)-1].content = ImageContent{
		handle = Handle,
		tint   = Style.Tint.? or_else {255, 255, 255, 255},
		fit    = Style.Fit,
	}
	Close()
	return node_id
}

// Custom adds a leaf whose look is `Fn` and returns its id, so it needs no Row or Column around
// it. `Config` is the box, defaulting to fill the parent. `User` is a value copied into the frame
// buffer, which the callback reads at draw time, so it may be a local of the declaring call.
Custom :: proc(
	Fn:     CustomProc,
	Config: ElementConfig = {Width = {Kind = .Fixed, Grow = 1}, Height = {Kind = .Fixed, Grow = 1}},
	Style:  BoxStyle = {},
	User:   any = nil,
) -> ElementId #no_bounds_check {
	// The buffer is a byte stream, so every value starts on the boundary the allocator already
	// guarantees for the buffer itself.
	ALIGN :: 16

	node_id := Open({base = Config}, Style)
	content := CustomContent{Fn = Fn}

	if User != nil {
		if size := int(runtime.type_info_base(type_info_of(User.id)).size); size > 0 {
			if rem := len(state.user_data) % ALIGN; rem != 0 {
				resize(&state.user_data, len(state.user_data) + ALIGN - rem)
			}
			content.Offset = u32(len(state.user_data))
			content.Size = u32(size)
			append(&state.user_data, ..([^]u8)(User.data)[:size])
		}
	}

	state.nodes[len(state.nodes) - 1].content = content
	Close()
	return node_id
}

// The root of every frame's id tree; ids derive from it down the hierarchy.
@(private="file")
ROOT_SEED :: ElementId(0x9e3779b9)

// id_mix folds `n` into `seed` to derive a child's id. It is a 32-bit avalanche hash, so
// neighbouring positions land far apart, and never returns 0 (0 means the last element).
@(private="file")
id_mix :: #force_inline proc(seed: ElementId, n: u32) -> ElementId {
	h := u32(seed) ~ n
	h ~= h >> 16
	h *= 0x7feb352d
	h ~= h >> 15
	h *= 0x846ca68b
	h ~= h >> 16
	if h == 0 do h = 1
	return ElementId(h)
}
