package ui

import "core:fmt"

// NO_NODE marks a scope that carries no node, which is what PushId opens.
@(private) NO_NODE :: max(u32)

// Scope is one level of the id stack: the seed new ids derive from, how many
// elements have already been opened inside it, and the node it belongs to, which
// is NO_NODE for a PushId scope.
@(private)
Scope :: struct {
	id:    Id,
	count: u32,
	node:  u32,
}

// StorageKey identifies one stored value: the id it belongs to and its type. One
// element can keep several values at once, as long as their types differ.
@(private="file")
StorageKey :: struct {
	id:   Id,
	type: typeid,
}

// ERRORS_ASSERT makes a misuse of the library trap instead of only reporting it.
// Turn it off with -define:glaze_errors_assert=false.
@(private="file")
ERRORS_ASSERT :: #config(glaze_errors_assert, true)

// CHECKS enables the structural checks that cost time, such as the duplicate id
// scan. Turn it off with -define:glaze_checks=false.
@(private)
CHECKS :: #config(glaze_checks, true)

// seen_ids catches two elements landing on the same id, which a 32 bit hash can
// produce. It only exists when CHECKS is on.
when CHECKS {
	@(private) seen_ids: map[Id]u32
}

// ErrorProc receives a message when the library detects a misuse it can recover
// from, such as an unbalanced PushId or a duplicate element id.
ErrorProc :: #type proc(Message: cstring, User: rawptr)

@(private="file")
error_proc: ErrorProc

@(private="file")
error_user: rawptr

// BindError installs the callback that receives those messages. With none bound
// and ERRORS_ASSERT off, the library writes them to stderr.
BindError :: proc(Fn: ErrorProc, User: rawptr = nil) {
	error_proc = Fn
	error_user = User
}

// report sends one misuse message to the callback and, when ERRORS_ASSERT is on,
// traps so the mistake is not lost in a log nobody reads.
@(private)
report :: proc(Message: cstring) {
	if error_proc != nil {
		error_proc(Message, error_user)
	}

	when ERRORS_ASSERT {
		assert(false, string(Message))
	} else {
		if error_proc == nil do report_stderr(Message)
	}
}

// report_stderr writes a misuse message to stderr when no callback is bound.
@(private="file")
report_stderr :: proc(Message: cstring) {
	fmt.eprintln("ui:", Message)
}

// ScrollDrag remembers a thumb held by the pointer, so the drag survives the pointer
// leaving the thumb and the wheel stands down until the release.
@(private)
ScrollDrag :: struct {
	id:   Id,
	axis: ScrollAxis,
	grab: f32,
}

// Screen holds the framebuffer and the two scales a frame maps through: `framebuffer`
// is in physical pixels, `dpi` is the platform scale, and `ui` is the app zoom.
@(private)
Screen :: struct {
	framebuffer: Vec2,
	dpi:         f32,
	ui:          f32,
}

State :: struct {
	screen:   Screen,
	frame:    u32,
	hover_id: Id,
	press_id: Id,
	click_id: Id,
	drag:     ScrollDrag,
	storage:  map[StorageKey]rawptr,
	nodes:    [dynamic]Node,
	scopes:   [dynamic]Scope,
	flexes:   [dynamic]Flex,
}

@(private)
state: State = {screen = {dpi = 1, ui = 1}}

// effective_scale returns the physical pixels per layout unit.
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

// AddDpiScale feeds the physical pixels per layout unit of the platform. Call it once
// per frame, before Begin.
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

// Storage returns the `T` stored under `Id`, allocating a zero value the first
// time that id asks for that type. Widgets keep their state here, keyed by their own
// id, and one element may hold as many types as it needs.
Storage :: proc(Id: Id, $T: typeid) -> ^T {
	key := StorageKey{id = Id, type = T}
	if ptr, ok := state.storage[key]; ok do return (^T)(ptr)

	ptr := new(T)
	state.storage[key] = ptr
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

