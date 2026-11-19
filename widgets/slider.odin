package widgets

import "base:intrinsics"
import ui "../ui"

// SliderStyle is what a slider paints: a color per interaction state for the track, the filled
// part and the knob, the focus ring, and the metrics the widget lays out with. `Height` is the
// thickness of a horizontal slider and the width of a vertical one, and `Gap` is the space the
// knob keeps from the box edge.
SliderStyle :: struct {
	Track:       [WidgetState]ui.Color,
	Fill:        [WidgetState]ui.Color,
	Knob:        [WidgetState]ui.Color,
	Ring:        ui.Color,
	Height:      f32,
	TrackHeight: f32,
	KnobRadius:  f32,
	Gap:         f32,
}

// HSlider edits the numeric `Value` inside `Min`..`Max` and reports whether it changed this frame.
// `T` is any integer or float: an integer snaps to whole units and steps by one. Pressing the
// track grabs the knob and the pointer drags it while held. A focused slider takes the arrows,
// PageUp/PageDown and Home/End; `Step` sets how far they move, and zero moves a hundredth of the
// range. Shift multiplies the step by ten. A nil Style uses the theme's.
HSlider :: proc(
	Value:    ^$T,
	Min, Max: T,
	Step:     f64 = 0,
	Width:    ui.Sizing = {Kind = .Fixed, Grow = 1, Shrink = 1},
	Style:    ^SliderStyle = nil,
	Disabled: bool = false,
) -> bool where intrinsics.type_is_ordered_numeric(T) {
	style := Style if Style != nil else &theme.Slider
	return slider(Value, Min, Max, Step, Width, ui.Fixed(style.Height), .Horizontal, style, Disabled)
}

// VSlider is HSlider on the vertical axis: `Min` sits at the bottom and `Max` at the top. `Height`
// is the whole track, the widget is as thick as a horizontal slider, and the keys are the same.
VSlider :: proc(
	Value:    ^$T,
	Min, Max: T,
	Step:     f64 = 0,
	Height:   ui.Sizing = {Kind = .Fixed, Grow = 1, Shrink = 1},
	Style:    ^SliderStyle = nil,
	Disabled: bool = false,
) -> bool where intrinsics.type_is_ordered_numeric(T) {
	style := Style if Style != nil else &theme.Slider
	return slider(Value, Min, Max, Step, ui.Fixed(style.Height), Height, .Vertical, style, Disabled)
}

@(private="file")
SliderAxis :: enum u8 {
	Horizontal,
	Vertical,
}

// slider declares the slider's box, turns the interaction into a value and paints it. The box
// exists only to carry an id, a hit area and the focus; the arithmetic runs in f64, so one core
// serves every numeric type.
@(private="file")
slider :: proc(
	Value:         ^$T,
	Min, Max:      T,
	Step:          f64,
	Width, Height: ui.Sizing,
	Axis:          SliderAxis,
	Style:         ^SliderStyle,
	Disabled:      bool,
) -> bool where intrinsics.type_is_ordered_numeric(T) {
	low, high := f64(Min), f64(Max)
	value := f64(Value^)

	element := ui.Open({Width = Width, Height = Height, Hit = .Ignore if Disabled else .Stop, Focusable = !Disabled})
	defer ui.Close()

	if rect := ui.ElementRect(element); !Disabled && rect.w > 0 && rect.h > 0 {
		if ui.Pressed(element) {
			inset := Style.KnobRadius + Style.Gap
			span := rect.w - inset * 2
			offset := ui.MousePos().x - rect.x - inset
			if Axis == .Vertical {
				span = rect.h - inset * 2
				offset = rect.y + rect.h - ui.MousePos().y - inset
			}
			value = low + (high - low) * f64(clamp(offset / max(span, 1), 0, 1))
		} else if ui.Focused(element) && high > low {
			step := Step if Step > 0 else (high - low) / 100
			when intrinsics.type_is_integer(T) {
				step = max(f64(i64(step)), 1)
			}
			if ui.ModifierDown(.Shift) do step *= 10

			up, down := ui.Key.Right, ui.Key.Left
			if Axis == .Vertical do up, down = .Up, .Down

			switch {
			case ui.KeyPressed(up, true):
				value = min(value + step, high)
			case ui.KeyPressed(down, true):
				value = max(value - step, low)
			case ui.KeyPressed(.PageUp, true):
				value = min(value + step * 10, high)
			case ui.KeyPressed(.PageDown, true):
				value = max(value - step * 10, low)
			case ui.KeyPressed(.Home):
				value = low
			case ui.KeyPressed(.End):
				value = high
			}
		}
		if ui.Hovered(element) {
			ui.SetCursor(.ResizeEW if Axis == .Horizontal else .ResizeNS)
		}
	}

	when intrinsics.type_is_integer(T) {
		value = f64(i64(value + (0.5 if value >= 0 else -0.5)))
	}
	value = clamp(value, low, high)

	changed := value != f64(Value^)
	if changed do Value^ = T(value)

	state := widget_state(element, Disabled)
	visual := SliderVisual{
		Track = Style.Track[state], Fill = Style.Fill[state], Knob = Style.Knob[state], Ring = Style.Ring,
		Inset = Style.KnobRadius + Style.Gap, TrackHeight = Style.TrackHeight, KnobRadius = Style.KnobRadius,
		T    = f32(clamp((value - low) / (high - low), 0, 1)) if high > low else 0,
		Axis = Axis, Focused = ui.Focused(element),
	}

	ui.Custom(draw_slider, {Width = ui.Fill(1), Height = ui.Fill(1), Hit = .Ignore}, {}, visual)
	return changed
}

// SliderVisual is what the paint callback receives: the colors resolved for this frame, how far
// the knob sits, and the axis. It is copied into the frame, so it may be a local.
@(private="file")
SliderVisual :: struct {
	Track, Fill, Knob, Ring:       ui.Color,
	Inset, TrackHeight, KnobRadius: f32,
	T:                              f32,
	Axis:                           SliderAxis,
	Focused:                        bool,
}

// draw_slider paints the track, the filled part and the knob along the axis the slider runs.
@(private="file")
draw_slider :: proc(Rect: ui.Rect, List: ^ui.DrawList, Element: ui.ElementId, User: rawptr) {
	visual := (^SliderVisual)(User)
	inset := visual.Inset

	if visual.Axis == .Horizontal {
		thickness := min(visual.TrackHeight, Rect.h)
		middle := Rect.y + Rect.h / 2
		track := ui.Rect{Rect.x + inset, middle - thickness / 2, max(Rect.w - inset * 2, 0), thickness}

		ui.AddRectFilled(List, track, visual.Track, ui.Corners(thickness / 2))
		if visual.T > 0 {
			ui.AddRectFilled(List, {track.x, track.y, track.w * visual.T, track.h}, visual.Fill, ui.Corners(thickness / 2))
		}
		ui.AddCircleFilled(List, {track.x + track.w * visual.T, middle}, visual.KnobRadius, visual.Knob)
	} else {
		thickness := min(visual.TrackHeight, Rect.w)
		middle := Rect.x + Rect.w / 2
		track := ui.Rect{middle - thickness / 2, Rect.y + inset, thickness, max(Rect.h - inset * 2, 0)}
		knob := track.y + track.h * (1 - visual.T)

		ui.AddRectFilled(List, track, visual.Track, ui.Corners(thickness / 2))
		if visual.T > 0 {
			ui.AddRectFilled(List, {track.x, knob, track.w, track.h * visual.T}, visual.Fill, ui.Corners(thickness / 2))
		}
		ui.AddCircleFilled(List, {middle, knob}, visual.KnobRadius, visual.Knob)
	}

	if visual.Focused {
		ui.AddRectStroke(List, Rect, visual.Ring, 1, ui.Corners(min(Rect.w, Rect.h) / 2))
	}
}
