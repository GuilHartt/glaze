package ui

// PAYLOAD_MAX is the largest drag payload that travels inline, in bytes. Larger data goes by a
// handle in the payload.
@(private)
PAYLOAD_MAX :: 256

// DRAG_THRESHOLD is how far the pointer moves before a press becomes a drag, in layout units.
@(private)
DRAG_THRESHOLD :: 6

// DragDrop is the item being carried between a source and a target, with the payload the source
// set.
@(private)
DragDrop :: struct {
	source:    ElementId,
	button:    MouseButton,
	type:      typeid,
	data:      [PAYLOAD_MAX]u8,
	size:      int,
	active:    bool,
	delivered: bool,
}

// Dragging reports whether `Element` is the active drag source with `Button`: the press started there
// and the pointer moved past the threshold. 0 is the last element declared.
Dragging :: proc(Element: ElementId = 0, Button: MouseButton = .Left) -> bool {
	source := target_id(Element)
	dd := &state.drag_drop

	if !dd.active {
		if state.press_ids[Button] != source do return false
		pos := MousePos()
		delta := pos - state.press_pos[Button]
		if delta.x * delta.x + delta.y * delta.y <= DRAG_THRESHOLD * DRAG_THRESHOLD do return false
		dd^ = {source = source, button = Button, active = true}
	}

	return dd.source == source && dd.button == Button && !MouseReleased(Button)
}

// SetDragDropPayload copies `Data` into the drag. Its type is `T`, which the target asks for.
SetDragDropPayload :: proc(Data: ^$T) {
	dd := &state.drag_drop
	if !dd.active do return
	if Data == nil {
		report("ui: drag drop payload without data")
		return
	}
	if size_of(T) > PAYLOAD_MAX {
		report("ui: drag drop payload larger than PAYLOAD_MAX")
		return
	}
	copy(dd.data[:], ([^]u8)(Data)[:size_of(T)])
	dd.type = typeid_of(T)
	dd.size = size_of(T)
}

// DragTarget reports whether a drag of `T` is over `Element`, so a widget can highlight the drop
// area. 0 is the last element declared.
DragTarget :: proc(T: typeid, Element: ElementId = 0) -> bool {
	dd := &state.drag_drop
	return dd.active && dd.type == T && Hovered(target_id(Element))
}

// AcceptDragDropPayload returns the payload once a drag of `T` is released over `Element`, and marks
// it delivered, so only one target takes it. 0 is the last element declared.
AcceptDragDropPayload :: proc($T: typeid, Element: ElementId = 0) -> (Data: ^T, ok: bool) {
	dd := &state.drag_drop
	if !dd.active || dd.delivered do return
	if !MouseReleased(dd.button) do return
	if !Hovered(target_id(Element)) do return
	if dd.type != typeid_of(T) do return
	dd.delivered = true
	return (^T)(&dd.data[0]), true
}

// drag_drop_end clears the drag once the button is up, after the targets had their frame.
@(private)
drag_drop_end :: proc() {
	if state.drag_drop.active && !MouseDown(state.drag_drop.button) {
		state.drag_drop = {}
	}
}
