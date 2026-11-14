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

// ScrollOffset returns the scroll offset stored for `Id`, in pixels. When `Id` is 0 it
// targets the last element declared.
ScrollOffset :: proc(Id: Id = 0) -> Vec2 {
	return Storage(target_id(Id), Vec2)^
}

// SetScroll stores the scroll offset for `Id`, in pixels. When `Id` is 0 it targets the last
// element declared.
SetScroll :: proc(Offset: Vec2, Id: Id = 0) {
	Storage(target_id(Id), Vec2)^ = Offset
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

// shows_bar reports whether the bar of `Axis` is drawn. Auto and Reserve measure the content
// against the box the node was given, which the arrangement has already set.
@(private)
shows_bar :: proc(n: ^Node, Axis: ScrollAxis, content: Vec2) -> bool {
	p  := n.config.Pad
	bw := n.style.Border.Width * 2

	#partial switch scroll_mode(n, Axis) {
	case .Always:
		return true
	case .Auto, .Reserve:
		if Axis == .Vertical {
			return content.y > max(n.rect.h - p.Top - p.Bottom - bw, 0)
		}
		return content.x > max(n.rect.w - p.Left - p.Right - bw, 0)
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

// strip_reserved reports whether the strip of `Axis` is out of the content for this tick.
// Only Auto reads the answer the arrangement stored in the tick that just ended.
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
	id:   Id,
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
		if !scrolls(&n, .Vertical) && !scrolls(&n, .Horizontal) do continue
		if !pointer_on(&n, pos) do continue

		s := ScrollOffset(n.id)
		if scrolls(&n, .Vertical)   do s.y -= wheel.y * STEP
		if scrolls(&n, .Horizontal) do s.x -= wheel.x * STEP
		SetScroll(s, n.id)
		break
	}
}
