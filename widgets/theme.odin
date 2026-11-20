#+feature global-context
package widgets

import ui "../ui"

// WidgetState is the interaction state a widget paints for. A widget picks one per frame from
// the interaction queries and indexes its style with it.
WidgetState :: enum u8 {
	Normal,
	Hovered,
	Pressed,
	Focused,
	Disabled,
}

// WidgetStyle is the visual every box-shaped widget shares: a background, text and border for
// each interaction state, plus the shape and type used to lay the content out.
WidgetStyle :: struct {
	Background:  [WidgetState]ui.Background,
	Text:        [WidgetState]ui.Color,
	Border:      [WidgetState]ui.Color,
	BorderWidth: ui.Edges,
	Corners:     ui.CornerRadius,
	Pad:         ui.Edges,
	Font:        ui.Font,
	FontSize:    f32,
}

// ThemeColor names every color role a theme provides. Widgets read the roles they need, and a
// theme change swaps the whole palette.
ThemeColor :: enum u8 {
	Background,
	Surface,
	SurfaceHovered,
	SurfacePressed,
	SurfaceDisabled,
	Text,
	Muted,
	Accent,
	Border,
	Focus,
}

// ThemeMetric names the scalar roles a theme provides: the corner radius, the gap between
// content, and the text size.
ThemeMetric :: enum u8 {
	Radius,
	Gap,
	FontSize,
}

// ThemeCommon is the part of a theme every widget reads: the color and metric roles, the base
// padding, and the font.
ThemeCommon :: struct {
	Color:  [ThemeColor]ui.Color,
	Metric: [ThemeMetric]f32,
	Pad:    ui.Edges,
	Font:   ui.Font,
}

// Theme is the base every widget derives its style from: the common tokens plus the default
// style of each widget type. An instance style overrides its own widget only.
Theme :: struct {
	using common: ThemeCommon,
	Button:       ButtonStyle,
	Checkbox:     CheckboxStyle,
	Slider:       SliderStyle,
	TextInput:    TextInputStyle,
}

// DefaultTheme returns the built-in dark theme, with every widget default derived from its
// tokens.
DefaultTheme :: proc() -> Theme {
	value := Theme{
		common = {
			Color = {
				.Background      = ui.Hex(0x1E1E1E),
				.Surface         = ui.Hex(0x2D2D2D),
				.SurfaceHovered  = ui.Hex(0x383838),
				.SurfacePressed  = ui.Hex(0x242424),
				.SurfaceDisabled = ui.Hex(0x262626),
				.Text            = ui.Hex(0xF2F2F2),
				.Muted           = ui.Hex(0x9A9A9A),
				.Accent          = ui.Hex(0x4C8DFF),
				.Border          = ui.Hex(0x444444),
				.Focus           = ui.Hex(0x4C8DFF),
			},
			Metric = {
				.Radius   = 6,
				.Gap      = 8,
				.FontSize = 16,
			},
			Pad  = ui.Edge(12, 8),
			Font = 0,
		},
	}
	value.Button = {common = default_widget_style(value)}

	value.Checkbox = {
		common = default_widget_style(value),
		Check  = {
			.Normal   = value.Color[.Accent],
			.Hovered  = value.Color[.Accent],
			.Pressed  = value.Color[.Accent],
			.Focused  = value.Color[.Accent],
			.Disabled = value.Color[.Muted],
		},
		Box = value.Metric[.FontSize],
		Gap = value.Metric[.Gap],
	}

	value.Slider = {
		Track = {
			.Normal   = value.Color[.SurfacePressed],
			.Hovered  = value.Color[.SurfacePressed],
			.Pressed  = value.Color[.SurfacePressed],
			.Focused  = value.Color[.SurfacePressed],
			.Disabled = value.Color[.SurfaceDisabled],
		},
		Fill = {
			.Normal   = value.Color[.Accent],
			.Hovered  = value.Color[.Accent],
			.Pressed  = value.Color[.Accent],
			.Focused  = value.Color[.Accent],
			.Disabled = value.Color[.Muted],
		},
		Knob = {
			.Normal   = value.Color[.Text],
			.Hovered  = value.Color[.Text],
			.Pressed  = ui.Hex(0xFFFFFF),
			.Focused  = value.Color[.Text],
			.Disabled = value.Color[.Muted],
		},
		Ring        = value.Color[.Focus],
		Height      = 24,
		TrackHeight = 4,
		KnobRadius  = 7,
		Gap         = 4,
	}

	value.TextInput = {
		common      = default_widget_style(value),
		Caret       = value.Color[.Text],
		Selection   = ui.Hex(0x4C8DFF, 90),
		Placeholder = value.Color[.Muted],
	}

	return value
}

// SetTheme replaces the global theme. Widgets declared after it use the new defaults.
SetTheme :: proc(Value: Theme) {
	theme = Value
}

// CurrentTheme returns a copy of the global theme, for changing one token or copying a widget
// style before an instance override.
CurrentTheme :: proc() -> Theme {
	return theme
}

// Every widget runs the same pipeline: widget_box opens and closes the box, widget_state
// resolves the visual, widget_style builds the box style, and widget_cursor asks for the pointer.

// widget_box opens the node every widget sits in, with the hit and focus a disabled widget
// turns off, and closes it at the end of the block.
@(private)
@(require_results, deferred_none = ui.Close)
widget_box :: proc(Config: ui.ContainerConfig, Disabled: bool) -> bool {
	config := Config
	config.Hit = .Ignore if Disabled else .Stop
	config.Focusable = !Disabled
	ui.Open(config)
	return true
}

// widget_state picks the state a widget paints for from the interaction of `Element`. A widget
// is pressed only while the pointer holds it, not when the keyboard activates it.
@(private)
widget_state :: proc(Element: ui.ElementId, Disabled: bool) -> WidgetState {
	switch {
	case Disabled:            return .Disabled
	case ui.Pressed(Element): return .Pressed
	case ui.Hovered(Element): return .Hovered
	case ui.Focused(Element): return .Focused
	}
	return .Normal
}

// widget_style builds the box style of one state, keeping the focus ring on a focused widget.
@(private)
widget_style :: proc(Style: ^WidgetStyle, State: WidgetState, Focused: bool) -> ui.BoxStyle {
	return {
		Background   = Style.Background[State],
		CornerRadius = Style.Corners,
		BorderColor  = Style.Border[.Focused] if Focused else Style.Border[State],
		BorderWidth  = Style.BorderWidth,
	}
}

// widget_cursor asks for `Icon` while a widget is hovered and enabled. The hand is the default,
// since most widgets are clickable.
@(private)
widget_cursor :: proc(Element: ui.ElementId, Disabled: bool, Icon: ui.CursorIcon = .Hand) {
	if !Disabled && ui.Hovered(Element) do ui.SetCursor(Icon)
}

// default_widget_style derives the shared box style from the theme's color and metric roles.
@(private)
default_widget_style :: proc(Source: Theme) -> WidgetStyle {
	return {
		Background = {
			.Normal   = Source.Color[.Surface],
			.Hovered  = Source.Color[.SurfaceHovered],
			.Pressed  = Source.Color[.SurfacePressed],
			.Focused  = Source.Color[.Surface],
			.Disabled = Source.Color[.SurfaceDisabled],
		},
		Text = {
			.Normal   = Source.Color[.Text],
			.Hovered  = Source.Color[.Text],
			.Pressed  = Source.Color[.Text],
			.Focused  = Source.Color[.Text],
			.Disabled = Source.Color[.Muted],
		},
		Border = {
			.Normal   = Source.Color[.Border],
			.Hovered  = Source.Color[.Border],
			.Pressed  = Source.Color[.Border],
			.Focused  = Source.Color[.Focus],
			.Disabled = Source.Color[.Border],
		},
		BorderWidth = ui.Edge(1),
		Corners     = ui.Corners(Source.Metric[.Radius]),
		Pad         = Source.Pad,
		Font        = Source.Font,
		FontSize    = Source.Metric[.FontSize],
	}
}

@(private)
theme: Theme = DefaultTheme()
