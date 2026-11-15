package ui

// target_id resolves the target of an interaction query: `id` when given, or the last element
// declared, leaf or container, when 0.
@(private)
target_id :: #force_inline proc(id: Id) -> Id {
	if id != 0 do return id
	return LastId()
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

// topmost_in returns the last node in `Lo`..`Hi` under `Pos`, skipping `Ignore` subtrees and
// nested floating layers, or NO_NODE when nothing there contains the pointer.
@(private)
topmost_in :: proc(Lo, Hi: u32, Pos: Vec2) -> u32 #no_bounds_check {
	skip := Lo
	target := NO_NODE
	for i := Lo; i < Hi; i += 1 {
		if i < skip do continue
		n := &state.nodes[i]
		if n.floating || n.config.Hit == .Ignore {
			skip = n.subtree_end
			continue
		}
		if pointer_on(n, Pos) do target = i
	}
	return target
}

// hit_target returns the topmost node under `Pos`. A floating layer that contains the pointer
// is tested first, in reverse declaration order, and the flow tree is the fallback.
@(private)
hit_target :: proc(Pos: Vec2) -> u32 #no_bounds_check {
	#reverse for &f in state.floats {
		n := &state.nodes[f.node]
		if n.config.Hit == .Ignore do continue
		if !pointer_on(n, Pos) do continue
		if target := topmost_in(f.node + 1, n.subtree_end, Pos); target != NO_NODE {
			return target
		}
		return f.node
	}
	return topmost_in(0, u32(len(state.nodes)), Pos)
}

// resolve_hover fills `state.hover_ids` with the target and its ancestors, topmost first, and
// returns the owner: the nearest `Stop` on that chain, or the nearest node that is not `Pass`.
// A floating layer roots its own chain, so the flow it was declared in stays out.
@(private)
resolve_hover :: proc(Target: u32) -> Id #no_bounds_check {
	clear(&state.hover_ids)
	if Target == NO_NODE do return 0

	stop, weak: Id
	n := &state.nodes[Target]
	append(&state.hover_ids, n.id)
	if n.config.Hit == .Stop do stop = n.id
	if n.config.Hit != .Pass do weak = n.id

	if !n.floating {
		#reverse for &a in state.nodes[:Target] {
			if a.subtree_end <= Target do continue
			append(&state.hover_ids, a.id)
			if stop == 0 && a.config.Hit == .Stop do stop = a.id
			if weak == 0 && a.config.Hit != .Pass do weak = a.id
			if a.floating do break
		}
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

