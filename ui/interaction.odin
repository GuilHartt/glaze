package ui

// target_id resolves the target of an interaction query: `id` when given, or the last element
// declared, leaf or container, when 0.
@(private)
target_id :: #force_inline proc(id: Id) -> Id {
	if id != 0 do return id
	return state.nodes[len(state.nodes) - 1].id
}

// Hovered reports whether `Id` is under the pointer, either itself or through one of its
// children, as it was drawn last tick. An `Id` of 0 targets the last element declared.
Hovered :: proc(Id: Id = 0) -> bool {
	Target := target_id(Id)
	for id in state.hover_ids {
		if id == Target do return true
	}
	return false
}

// Pressed reports whether `Id` took the press and has not been released, even when the pointer
// has moved away. An `Id` of 0 targets the last element declared.
Pressed :: proc(Id: Id = 0) -> bool {
	return state.press_id != 0 && target_id(Id) == state.press_id
}

// Clicked reports whether `Id` was pressed and released in the same place this tick. An `Id`
// of 0 targets the last element declared.
Clicked :: proc(Id: Id = 0) -> bool {
	return state.click_id != 0 && target_id(Id) == state.click_id
}

// pointer_on reports whether the pointer is over `N`: inside its rect and inside the clip it
// was drawn with.
@(private)
pointer_on :: #force_inline proc "contextless" (N: ^Node, Pos: Vec2) -> bool {
	return RectContains(N.rect, Pos) && RectContains(N.clip, Pos)
}

// hit_target returns the topmost node under `Pos`, skipping every `Ignore` subtree, or NO_NODE
// when the pointer is over nothing.
@(private)
hit_target :: proc(Pos: Vec2) -> u32 #no_bounds_check {
	skip: u32
	target := NO_NODE
	for &n, i in state.nodes {
		if u32(i) < skip do continue
		if n.config.Hit == .Ignore {
			skip = n.subtree_end
			continue
		}
		if pointer_on(&n, Pos) do target = u32(i)
	}
	return target
}

// resolve_hover fills `state.hover_ids` with the target and its ancestors, topmost first, and
// returns the element that owns the press: the nearest `Stop` on that chain, or the nearest
// element that is not `Pass`.
@(private)
resolve_hover :: proc(Target: u32) -> Id #no_bounds_check {
	clear(&state.hover_ids)
	if Target == NO_NODE do return 0

	stop, weak: Id
	n := &state.nodes[Target]
	append(&state.hover_ids, n.id)
	if n.config.Hit == .Stop do stop = n.id
	if n.config.Hit != .Pass do weak = n.id

	#reverse for &a in state.nodes[:Target] {
		if a.subtree_end <= Target do continue
		append(&state.hover_ids, a.id)
		if stop == 0 && a.config.Hit == .Stop do stop = a.id
		if weak == 0 && a.config.Hit != .Pass do weak = a.id
	}

	return stop if stop != 0 else weak
}

// set_hover points the chain at one element, which is what the scroll bar does when it takes
// the pointer from the content underneath.
@(private)
set_hover :: proc(i: u32) #no_bounds_check {
	clear(&state.hover_ids)
	append(&state.hover_ids, state.nodes[i].id)
}

// interaction_begin turns the pointer and the button edges into the hover chain and the press
// owner. The chain is the element under the pointer and its ancestors, so a container knows the
// pointer is inside it; the owner is the one element that answers for a press.
@(private)
interaction_begin :: proc() #no_bounds_check {
	owner := resolve_hover(hit_target(MousePos()))

	if MousePressed(.Left) {
		state.press_id = owner
	}

	state.click_id = 0
	if MouseReleased(.Left) {
		pressed := state.press_id
		if pressed != 0 && pressed == owner {
			state.click_id = pressed
		}
		state.press_id = 0
	}
}

