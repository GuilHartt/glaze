package ui

import "core:fmt"

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

