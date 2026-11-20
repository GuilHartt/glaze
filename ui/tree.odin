package ui

import "base:runtime"
import "core:fmt"

// ElementId is the stable key an element is declared under. In the queries, 0 targets the last
// element declared.
ElementId :: distinct u32

// ElementConfig is how an element is sized and painted into its box, and how it answers the
// pointer and the keyboard. `Hit` decides whether the element is seen, observes or owns the
// press; `Focusable` lets Tab and a click give it the focus.
ElementConfig :: struct {
	Width:     Sizing,
	Height:    Sizing,
	Pad:       Edges,
	Clip:      bool,
	Hit:       HitMode,
	Focusable: bool,
}

// ContainerConfig is how a container places its children: the element config it shares with
// every leaf, plus the gap between children, their alignment and the scrolling.
ContainerConfig :: struct {
	using base: ElementConfig,
	Gap:        f32,
	Justify:    Justify,
	Align:      Align,
	Scroll:     Scroll,
}

// NO_NODE marks a scope that carries no node, which is what PushId opens.
@(private) NO_NODE :: max(u32)

// Scope is one level of the id stack: the seed new ids derive from, how many elements have
// already been opened inside it, and the node it belongs to, which is NO_NODE for a PushId.
@(private)
Scope :: struct {
	id:    ElementId,
	count: u32,
	node:  u32,
}

// StorageKey identifies one stored value: the id it belongs to and its type. One element can
// keep several values at once, as long as their types differ.
@(private="file")
StorageKey :: struct {
	id:   ElementId,
	type: typeid,
}

// ErrorProc receives a message when the library detects a misuse it can recover from, such as
// an unbalanced PushId or a duplicate element id.
ErrorProc :: #type proc(Message: string, User: rawptr)

@(private="file")
error_proc: ErrorProc

@(private="file")
error_user: rawptr

// BindError installs the callback that receives those messages. A build with asserts keeps the
// debugger trap, and a build without them writes to stderr when no callback is bound.
BindError :: proc(Fn: ErrorProc, User: rawptr = nil) {
	error_proc = Fn
	error_user = User
}

// report sends one misuse message to the callback. A build with asserts traps, so the mistake
// is not lost in a log nobody reads; a build without them only reports.
@(private)
report :: proc(Message: string) {
	if error_proc != nil {
		error_proc(Message, error_user)
	}

	when ODIN_DISABLE_ASSERT {
		if error_proc == nil do report_stderr(Message)
	} else {
		assert(false, string(Message))
	}
}

// report_stderr writes a misuse message to stderr when no callback is bound.
@(private="file")
report_stderr :: proc(Message: string) {
	fmt.eprintln("ui:", Message)
}

// Screen holds the framebuffer and the scales a frame maps through: `framebuffer`
// is in physical pixels, `dpi` is the platform scale, and `ui` is the app zoom.
@(private)
Screen :: struct {
	framebuffer: Vec2,
	dpi:         f32,
	ui:          f32,
}

@(private)
State :: struct {
	screen:      Screen,
	frame:       u32,
	clicks:      [MouseButton]Click,
	hover_ids:   [dynamic]ElementId,
	hover_owner: ElementId,
	press_ids:   [MouseButton]ElementId,
	press_pos:   [MouseButton]Vec2,
	click_ids:   [MouseButton]ElementId,
	focus_id:    ElementId,
	drag:        ScrollDrag,
	drag_drop:   DragDrop,
	cursor:      CursorIcon,
	storage:     map[StorageKey]rawptr,
	prev:        [dynamic]Placement,
	published:   u32,
	nodes:       [dynamic]Node,
	scopes:      [dynamic]Scope,
	floats:      [dynamic]Float,
	flexes:      [dynamic]Flex,
	user_data:   [dynamic]u8,
}

@(private)
state: State = {screen = {dpi = 1, ui = 1}}

// effective_scale returns the framebuffer pixels per layout unit.
@(private)
effective_scale :: #force_inline proc "contextless" () -> f32 {
	return state.screen.dpi * state.screen.ui
}

// viewport_size returns the surface the UI lays out into, in layout units.
@(private)
viewport_size :: #force_inline proc "contextless" () -> Vec2 {
	return state.screen.framebuffer / effective_scale()
}

// AddFramebufferSize feeds the size of the framebuffer, in physical pixels. Call it
// once per frame, before Begin.
AddFramebufferSize :: proc(Size: Vec2) {
	state.screen.framebuffer = Size
}

// AddDpiScale feeds the platform scale, in physical pixels per screen pixel. Call it
// once per frame, before Begin.
AddDpiScale :: proc(Scale: f32) {
	if Scale <= 0 {
		report("ui: DPI scale must be positive")
		return
	}
	state.screen.dpi = Scale
}

// SetUiScale sets the zoom of the whole UI, where 1 is the platform size.
SetUiScale :: proc(Scale: f32) {
	if Scale <= 0 {
		report("ui: UI scale must be positive")
		return
	}
	state.screen.ui = Scale
}

// ViewportSize returns the surface the UI is laid out into, in layout units.
ViewportSize :: proc() -> Vec2 {
	return viewport_size()
}

// FrameCount returns how many frames have started since the program launched.
FrameCount :: proc() -> u32 {
	return state.frame
}

// Storage returns the `T` stored under `Element`, allocating a zero value the first time that id
// asks for that type. Widgets keep their state here, keyed by their own id, and one element
// may hold as many types as it needs.
Storage :: proc(Element: ElementId, $T: typeid) -> ^T {
	key := StorageKey{id = Element, type = T}
	if ptr, ok := state.storage[key]; ok do return (^T)(ptr)

	ptr := new(T)
	state.storage[key] = ptr
	return ptr
}


// Begin starts a new frame: it feeds the input, clears the node array and opens an implicit
// root node sized to the viewport. Must be paired with End.
Begin :: proc() {
	event_begin()
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
Label :: proc(Text: string, Config: ElementConfig = {}, Style: LabelStyle = {}) -> ElementId #no_bounds_check {
	node_id := Open({base = Config}, Style.Box)
	state.nodes[len(state.nodes)-1].content = TextContent{
		text      = Text,
		font      = Style.Font,
		color     = Style.Color.? or_else {255, 255, 255, 255},
		size      = Style.Size.? or_else 16,
		wrap      = Style.Wrap,
		max_lines = Style.MaxLines,
		ellipsis  = Style.Ellipsis,
		align     = Style.TextAlign,
		valign    = Style.VerticalAlign,
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
