package ui

// ScrollAxis is one axis a box can scroll along.
ScrollAxis :: enum u8 { Horizontal, Vertical }

// ScrollMode is how one axis scrolls.
ScrollMode :: enum u8 {
	Disabled,
	Auto,
	Always,
	Never,
	Reserve,
}

// Scroll is how each axis of a box scrolls. An axis that scrolls is clipped and its content
// can move inside the box; the mode decides whether a bar is drawn and whether its strip is
// taken from the content.
Scroll :: struct {
	Horizontal, Vertical: ScrollMode,
}

// SCROLLBAR_THICKNESS is the width a scroll bar takes from the content box, as padding on
// the trailing edge of the axis it runs along.
@(private)
SCROLLBAR_THICKNESS :: f32(6)

// SCROLLBAR_GAP is the space kept between the content and the bar.
@(private)
SCROLLBAR_GAP :: f32(4)

// ScrollOffset returns the scroll offset stored for `Element`, in pixels. When `Element` is 0 it
// targets the last element declared.
ScrollOffset :: proc(Element: ElementId = 0) -> Vec2 {
	return Storage(target_id(Element), Vec2)^
}

// SetScroll stores the scroll offset for `Element`, in pixels. When `Element` is 0 it targets the last
// element declared.
SetScroll :: proc(Offset: Vec2, Element: ElementId = 0) {
	Storage(target_id(Element), Vec2)^ = Offset
}

// EnsureVisible scrolls the scrolling ancestors of `Element` so its rect sits inside them in the
// next layout. Call it after End. An `Element` of 0 targets the last element declared.
EnsureVisible :: proc(Element: ElementId = 0) {
	target := target_id(Element)
	if target == 0 do return

	index := NO_NODE
	#reverse for &p, i in state.prev {
		if p.frame == state.published && p.id == target {
			index = u32(i)
			break
		}
	}
	if index == NO_NODE do return
	if int(index) >= len(state.nodes) || state.nodes[index].id != target do return

	rect := state.prev[index].rect
	i := state.prev[index].parent
	for i != NO_NODE {
		if int(i) >= len(state.nodes) || state.prev[i].frame != state.published do break
		if state.nodes[i].id != state.prev[i].id do break

		n := &state.nodes[i]
		if scrolls(n, .Vertical) || scrolls(n, .Horizontal) {
			inner := inner_rect(i, n.rect)
			offset := ScrollOffset(n.id)
			next := offset
			limit := scroll_limit(n, inner)

			if scrolls(n, .Vertical) {
				if rect.y < inner.y {
					next.y = offset.y - (inner.y - rect.y)
				} else if rect.y + rect.h > inner.y + inner.h {
					next.y = offset.y + (rect.y + rect.h - inner.y - inner.h)
				}
				next.y = clamp(next.y, 0, limit.y)
			}
			if scrolls(n, .Horizontal) {
				if rect.x < inner.x {
					next.x = offset.x - (inner.x - rect.x)
				} else if rect.x + rect.w > inner.x + inner.w {
					next.x = offset.x + (rect.x + rect.w - inner.x - inner.w)
				}
				next.x = clamp(next.x, 0, limit.x)
			}

			delta := next - offset
			if delta.x != 0 || delta.y != 0 {
				SetScroll(next, n.id)
				rect.x -= delta.x
				rect.y -= delta.y
			}
		}

		i = state.prev[i].parent
	}
}

// scroll_mode returns how `Axis` scrolls.
@(private)
scroll_mode :: #force_inline proc "contextless" (n: ^Node, Axis: ScrollAxis) -> ScrollMode {
	return n.config.Scroll.Vertical if Axis == .Vertical else n.config.Scroll.Horizontal
}

// scrolls reports whether `Axis` moves at all, which every mode but Disabled does.
@(private)
scrolls :: #force_inline proc "contextless" (n: ^Node, Axis: ScrollAxis) -> bool {
	return scroll_mode(n, Axis) != .Disabled
}

// scroll_limit returns how far node `n` can scroll inside `inner` on each axis, and zero on an
// axis that does not scroll.
@(private)
scroll_limit :: proc(n: ^Node, inner: Rect) -> Vec2 {
	limit := Vec2{
		max(n.content_size.x - inner.w, 0),
		max(n.content_size.y - inner.h, 0),
	}
	if !scrolls(n, .Horizontal) do limit.x = 0
	if !scrolls(n, .Vertical)   do limit.y = 0
	return limit
}

// shows_bar reports whether the bar of `Axis` is drawn. Auto and Reserve measure the content
// against the box the node was given, which the arrangement has already set.
@(private)
shows_bar :: proc(n: ^Node, Axis: ScrollAxis, content: Vec2) -> bool {
	p := n.config.Pad
	b := n.style.BorderWidth

	#partial switch scroll_mode(n, Axis) {
	case .Always:
		return true
	case .Auto, .Reserve:
		if Axis == .Vertical {
			return content.y > max(n.rect.h - p.Top - p.Bottom - b.Top - b.Bottom, 0)
		}
		return content.x > max(n.rect.w - p.Left - p.Right - b.Left - b.Right, 0)
	}
	return false
}

// strips returns the axes whose strip is taken from the content. Reserve keeps it even while
// the bar is hidden, so the content never moves.
@(private)
strips :: proc(n: ^Node, content: Vec2) -> bit_set[ScrollAxis] {
	out: bit_set[ScrollAxis]

	if scroll_mode(n, .Vertical) == .Reserve || shows_bar(n, .Vertical, content) {
		out += {.Vertical}
	}
	if scroll_mode(n, .Horizontal) == .Reserve || shows_bar(n, .Horizontal, content) {
		out += {.Horizontal}
	}
	return out
}

// strip_reserved reports whether the strip of `Axis` is out of the content for this frame.
// Only Auto reads the answer the arrangement stored in the frame that just ended.
@(private)
strip_reserved :: proc(n: ^Node, Axis: ScrollAxis) -> bool {
	#partial switch scroll_mode(n, Axis) {
	case .Always, .Reserve:
		return true
	case .Auto:
		return Axis in Storage(n.id, bit_set[ScrollAxis])^
	}
	return false
}

// ScrollDrag remembers a thumb held by the pointer, so the drag survives the pointer leaving
// the thumb and the wheel stands down until the release.
@(private)
ScrollDrag :: struct {
	id:   ElementId,
	axis: ScrollAxis,
	grab: f32,
}

// Scrollbar is the geometry of one axis of a scroll bar: the track the thumb travels inside,
// the thumb itself, and the two lengths that turn a pointer position into an offset.
@(private)
Scrollbar :: struct {
	track:  Rect,
	thumb:  Rect,
	span:   f32,
	window: f32,
}

// scrollbar computes the bar of node `i` on `Axis`, or reports that the axis has no bar.
// When the content fits the thumb fills the track, since the bar reserved its strip.
@(private)
scrollbar :: proc(i: u32, Axis: ScrollAxis) -> (bar: Scrollbar, ok: bool) #no_bounds_check {
	n := &state.nodes[i]
	content := n.content_size
	if Axis not_in n.strips do return

	vertical := Axis == .Vertical
	view := inner_rect(i, n.rect)
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
			if n.strips == {} do continue
			if !Hovered(n.id) do continue

			for axis in ScrollAxis {
				bar, ok := scrollbar(u32(i), axis)
				if !ok || !RectContains(bar.thumb, pos) do continue

				state.drag = {
					id   = n.id,
					axis = axis,
					grab = (pos.y - bar.thumb.y) if axis == .Vertical else (pos.x - bar.thumb.x),
				}
				set_hover(u32(i))
				state.press_ids[.Left] = n.id
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

	i := node_of(state.drag.id)
	if i == NO_NODE do return
	set_hover(i)

	bar, ok := scrollbar(i, state.drag.axis)
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
}

// scroll_update turns the wheel into scroll for the containers under the pointer, from the
// deepest up, until the delta is used up. Only nodes in the hover chain take it, so a container
// under a floating layer does not scroll, and a list at its end hands the rest to its parent.
@(private)
scroll_update :: proc() {
	wheel := MouseWheel()
	if wheel == 0 || state.drag.id != 0 do return

	// One wheel notch scrolls this many pixels.
	STEP :: 40

	remaining := wheel * STEP
	pos := MousePos()
	#reverse for &n, i in state.nodes {
		if remaining == 0 do break
		if !scrolls(&n, .Vertical) && !scrolls(&n, .Horizontal) do continue
		if !Hovered(n.id) do continue
		if !pointer_on(&n, pos) do continue

		offset := ScrollOffset(n.id)
		limit := scroll_limit(&n, inner_rect(u32(i), n.rect))
		next := offset
		if scrolls(&n, .Vertical) {
			next.y = clamp(offset.y - remaining.y, 0, limit.y)
		}
		if scrolls(&n, .Horizontal) {
			next.x = clamp(offset.x - remaining.x, 0, limit.x)
		}
		remaining -= offset - next
		SetScroll(next, n.id)
	}
}
