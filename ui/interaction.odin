package ui

// target_id resolves the target of an interaction query: `id` when given, or the
// last element declared, leaf or container, when 0.
@(private)
target_id :: #force_inline proc(id: Id) -> Id {
	if id != 0 do return id
	return state.nodes[len(state.nodes) - 1].id
}

// Hovered reports whether `Id` is the element under the pointer, as it was drawn
// last frame. When `Id` is 0 it targets the last element declared.
Hovered :: proc(Id: Id = 0) -> bool {
	return state.hover_id != 0 && target_id(Id) == state.hover_id
}

// Pressed reports whether `Id` took the press and has not been released, even when
// the pointer has moved away. When `Id` is 0 it targets the last element declared.
Pressed :: proc(Id: Id = 0) -> bool {
	return state.press_id != 0 && target_id(Id) == state.press_id
}

// Clicked reports whether `Id` was pressed and released in the same place this
// frame. When `Id` is 0 it targets the last element declared.
Clicked :: proc(Id: Id = 0) -> bool {
	return state.click_id != 0 && target_id(Id) == state.click_id
}

// pointer_on reports whether the pointer is over `N`, which means inside its rect
// and inside the clip it was drawn with.
@(private)
pointer_on :: #force_inline proc "contextless" (N: ^Node, Pos: Vec2) -> bool {
	return RectContains(N.rect, Pos) && RectContains(N.clip, Pos)
}

// interaction_begin picks the element under the pointer and turns the button edges
// into the pressed and clicked ids. It walks the nodes backwards, which is the draw
// order inverted, so the last element drawn wins, and it requires the pointer to be
// inside the clip that element was drawn with.
@(private)
interaction_begin :: proc() #no_bounds_check {
	pos := MousePos()

	state.hover_id = 0
	#reverse for &n in state.nodes {
		if pointer_on(&n, pos) {
			state.hover_id = n.id
			break
		}
	}

	if MousePressed(.Left) {
		state.press_id = state.hover_id
	}

	state.click_id = 0
	if MouseReleased(.Left) {
		pressed := state.press_id
		if pressed != 0 && pressed == state.hover_id {
			state.click_id = pressed
		}
		state.press_id = 0
	}
}


// scroll_update turns the wheel into scroll for the innermost container under the
// pointer. It reads the rects of the previous frame, walking the nodes backwards so
// the last match is the deepest one.
@(private)
scroll_update :: proc() {
	wheel := MouseWheel()
	if wheel == 0 do return

	// One wheel notch scrolls this many pixels.
	STEP :: 40

	pos := MousePos()
	#reverse for &n in state.nodes {
		if n.config.Scroll == {} do continue
		if !pointer_on(&n, pos) do continue

		s := ScrollOffset(n.id)
		if .Vertical   in n.config.Scroll do s.y -= wheel.y * STEP
		if .Horizontal in n.config.Scroll do s.x -= wheel.x * STEP
		SetScroll(s, n.id)
		break
	}
}

