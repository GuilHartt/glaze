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

// Entry is one stored value: its bytes live on the heap, so the pointer stays
// valid across frames and across growth of the map.
@(private="file")
Entry :: struct {
	ptr:  rawptr,
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
		if error_proc == nil do fmt.eprintln("ui:", Message)
	}
}

State :: struct {
	root_size: Vec2,
	hover_id:  Id,
	press_id:  Id,
	click_id:  Id,
	nodes:     [dynamic]Node,
	scopes:    [dynamic]Scope,
	flexes:    [dynamic]Flex,
	storage:   map[Id]Entry,
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
		if entry.type != T {
			report("ui: the same id was stored with two different types")
		}
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

