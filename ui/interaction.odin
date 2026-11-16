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

// Pressed reports whether `Id` took `Button` and has not been released, even when the pointer
// has moved away. An `Id` of 0 targets the last element declared.
Pressed :: proc(Id: Id = 0, Button: MouseButton = .Left) -> bool {
	return state.press_ids[Button] != 0 && target_id(Id) == state.press_ids[Button]
}

// Clicked reports whether `Id` was pressed and released in the same place this tick with
// `Button`. An `Id` of 0 targets the last element declared.
Clicked :: proc(Id: Id = 0, Button: MouseButton = .Left) -> bool {
	return state.click_ids[Button] != 0 && target_id(Id) == state.click_ids[Button]
}

// DoubleClicked reports whether `Id` took two clicks in a row with `Button` this frame. An
// `Id` of 0 targets the last element declared.
DoubleClicked :: proc(Id: Id = 0, Button: MouseButton = .Left) -> bool {
	return ClickCount(Id, Button) == 2
}

// ClickCount reports how many clicks in a row `Id` took this frame, or 0 when no click landed
// there. An `Id` of 0 targets the last element declared.
ClickCount :: proc(Id: Id = 0, Button: MouseButton = .Left) -> int {
	if state.click_ids[Button] == 0 || state.click_ids[Button] != target_id(Id) do return 0
	return int(state.clicks[Button].count)
}

// Focused reports whether `Id` owns the keyboard focus. An `Id` of 0 targets the last element
// declared.
Focused :: proc(Id: Id = 0) -> bool {
	return state.focus_id != 0 && target_id(Id) == state.focus_id
}

// RequestFocus moves the keyboard focus to `Id`, or clears it when `Id` is 0. Unlike the
// queries, 0 is not the last element declared.
RequestFocus :: proc(Id: Id = 0) {
	state.focus_id = Id
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

// Click is the last click of one button: the element it hit, when, where, and how many in a
// row landed there.
@(private)
Click :: struct {
	id:    Id,
	count: u8,
	pos:   Vec2,
	time:  f32,
}

// record_click updates the click track of `Button` with a click on `Id`, counting a sequence
// when two clicks land close in time and place.
@(private)
record_click :: proc(Button: MouseButton, Id: Id) {
	// Two clicks on the same element within this time and distance are one sequence.
	TIME :: 0.30
	SLOP :: 6

	click := &state.clicks[Button]
	pos := MousePos()
	delta := pos - click.pos
	dist := delta.x * delta.x + delta.y * delta.y
	if click.id == Id && time.Total - click.time <= TIME && dist <= SLOP * SLOP {
		click.count += 1
	} else {
		click.count = 1
	}

	click.id = Id
	click.time = time.Total
	click.pos = pos
}

// interaction_begin turns the pointer and the button edges into the hover chain and the press
// owner of each button. The chain is the element under the pointer and its ancestors, so a
// container knows the pointer is inside it; the owner answers for a press.
@(private)
interaction_begin :: proc() #no_bounds_check {
	pos := MousePos()
	owner := resolve_hover(hit_target(pos))

	for button in MouseButton {
		if MousePressed(button) {
			state.press_ids[button] = owner
			state.press_pos[button] = pos
		}

		state.click_ids[button] = 0
		if MouseReleased(button) {
			pressed := state.press_ids[button]
			if pressed != 0 && pressed == owner {
				state.click_ids[button] = pressed
				record_click(button, pressed)
			}
			state.press_ids[button] = 0
		}
	}
}

// next_focus returns the next focusable element after `Current` in declaration order, or 0
// when none exists. `Back` walks the order backwards, and the walk wraps around.
@(private)
next_focus :: proc(Current: Id, Back: bool) -> Id {
	count := len(state.nodes)
	if count == 0 do return 0

	start := count - 1 if Back else 0
	for &n, i in state.nodes {
		if n.id == Current {
			start = i - 1 if Back else i + 1
			break
		}
	}

	step := -1 if Back else 1
	for _ in 0 ..< count {
		if start < 0 do start = count - 1
		if start >= count do start = 0
		n := &state.nodes[start]
		if n.config.Focusable do return n.id
		start += step
	}

	return 0
}

// focus_begin takes the focus for a left press on a focusable element, clears it on a press
// anywhere else, and moves it with Tab. Shift+Tab walks back.
@(private)
focus_begin :: proc() {
	if MousePressed(.Left) {
		if i := node_of(state.press_ids[.Left]); i != NO_NODE && state.nodes[i].config.Focusable {
			state.focus_id = state.nodes[i].id
		} else {
			state.focus_id = 0
		}
	}

	if KeyPressed(.Tab) {
		state.focus_id = next_focus(state.focus_id, ModifierDown(.Shift))
	}
}
