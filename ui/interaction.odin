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

// pointer_owner returns the node that owns the hit at `Pos`: the innermost node
// that declares `Hit` and is an ancestor of the deepest node under the pointer, or
// the deepest node itself when no ancestor declares it. A node contains `deepest`
// when its subtree ends past it, so the backwards walk meets the ancestors in
// order, from the innermost outwards.
@(private)
pointer_owner :: proc(Pos: Vec2) -> u32 #no_bounds_check {
	deepest, owner := NO_NODE, NO_NODE

	#reverse for &n, i in state.nodes {
		if deepest == NO_NODE {
			if !pointer_on(&n, Pos) do continue
			deepest = u32(i)
		}
		if n.config.Hit && n.subtree_end > deepest {
			owner = u32(i)
			break
		}
	}

	if owner == NO_NODE do return deepest
	return owner
}

// interaction_begin turns the pointer and the button edges into the hovered,
// pressed and clicked ids. The target is the element that owns the hit, so a
// container that declares `Hit` wins over the leaves it draws on top of.
@(private)
interaction_begin :: proc() #no_bounds_check {
	owner := pointer_owner(MousePos())

	state.hover_id = 0
	if owner != NO_NODE {
		state.hover_id = state.nodes[owner].id
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


// Scrollbar is the geometry of one axis of a scroll bar: the track the thumb travels
// inside, the thumb itself, and the two lengths that turn a pointer position into an
// offset.
@(private)
Scrollbar :: struct {
	track:  Rect,
	thumb:  Rect,
	span:   f32,
	window: f32,
}

// scrollbar computes the bar of node `i` on `Axis`. It returns false when that axis
// has no bar. When the content fits the thumb fills the track, since the bar reserved
// its strip and should look like one.
@(private)
scrollbar :: proc(i: u32, Axis: ScrollAxis) -> (bar: Scrollbar, ok: bool) #no_bounds_check {
	n := &state.nodes[i]
	if Axis not_in n.config.Scroll || !n.style.ScrollBar do return

	vertical := Axis == .Vertical
	view := inner_rect(n, n.rect)
	content := intrinsic_size(i)
	bar.span = content.y if vertical else content.x
	bar.window = view.h if vertical else view.w
	if bar.span <= 0 || bar.window <= 0 do return

	length := min(max(bar.window * bar.window / bar.span, SCROLLBAR_THICKNESS * 2), bar.window)
	start := f32(0)
	if bar.span > bar.window {
		offset := ScrollOffset(n.id)
		reach := bar.span - bar.window
		start = clamp((bar.window - length) * (offset.y if vertical else offset.x) / reach, 0, bar.window - length)
	}

	if vertical {
		bar.track = {view.x + view.w + SCROLLBAR_GAP, view.y, SCROLLBAR_THICKNESS, view.h}
		bar.thumb = {bar.track.x, bar.track.y + start, SCROLLBAR_THICKNESS, length}
	} else {
		bar.track = {view.x, view.y + view.h + SCROLLBAR_GAP, view.w, SCROLLBAR_THICKNESS}
		bar.thumb = {bar.track.x + start, bar.track.y, length, SCROLLBAR_THICKNESS}
	}
	return bar, true
}

// scrollbar_update turns a press on a thumb into a drag and moves the offset while
// the button stays down. The bar is drawn over the content, so a press on it claims
// the hit, and the grab offset is kept so the thumb does not jump to the pointer.
@(private)
scrollbar_update :: proc() {
	pos := MousePos()

	if MousePressed(.Left) {
		state.drag = {}
		#reverse for &n, i in state.nodes {
			if n.config.Scroll == {} do continue

			for axis in ScrollAxis {
				bar, ok := scrollbar(u32(i), axis)
				if !ok || !RectContains(bar.thumb, pos) do continue

				state.drag = {
					id   = n.id,
					axis = axis,
					grab = (pos.y - bar.thumb.y) if axis == .Vertical else (pos.x - bar.thumb.x),
				}
				state.hover_id = n.id
				state.press_id = n.id
				return
			}
		}
		return
	}

	if state.drag.id == 0 do return

	if MouseReleased(.Left) {
		state.drag = {}
		return
	}

	state.hover_id = state.drag.id

	#reverse for &n, i in state.nodes {
		if n.id != state.drag.id do continue

		bar, ok := scrollbar(u32(i), state.drag.axis)
		if !ok do return

		vertical := state.drag.axis == .Vertical
		travel := (bar.track.h - bar.thumb.h) if vertical else (bar.track.w - bar.thumb.w)
		reach := bar.span - bar.window
		if travel <= 0 || reach <= 0 do return

		at := clamp(
			(pos.y - bar.track.y - state.drag.grab) if vertical else (pos.x - bar.track.x - state.drag.grab),
			0,
			travel,
		)

		offset := ScrollOffset(state.drag.id)
		if vertical {
			offset.y = at / travel * reach
		} else {
			offset.x = at / travel * reach
		}
		SetScroll(offset, state.drag.id)
		return
	}
}

// scroll_update turns the wheel into scroll for the innermost container under the
// pointer. It reads the rects of the previous frame, walking the nodes backwards so
// the last match is the deepest one.
@(private)
scroll_update :: proc() {
	wheel := MouseWheel()
	if wheel == 0 || state.drag.id != 0 do return

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

