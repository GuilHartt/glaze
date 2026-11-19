<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/glaze-logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/glaze-logo-light.svg">
    <img alt="Glaze" width="460" src="docs/images/glaze-logo-light.svg">
  </picture>
</p>

<p align="center">
  A small immediate-mode UI engine written in Odin.
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#layout">Layout</a> ·
  <a href="#interaction">Interaction</a> ·
  <a href="#text">Text</a> ·
  <a href="#drawing">Drawing</a> ·
  <a href="#widgets">Widgets</a> ·
  <a href="#backends">Backends</a> ·
  <a href="#building">Building</a>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-1f1f1f"></a>
  <img alt="Odin dev-2026-11" src="https://img.shields.io/badge/odin-dev--2026--11-1f1f1f">
</p>

Glaze is an immediate-mode UI engine written in Odin. You declare the interface every frame; the engine lays it out and hands the backend a draw list of vertices, indices and draw commands. Nothing survives a frame except what interaction, scrolling and layout keep.

It has no platform dependency. A backend is one file that feeds events in and draws the list out, and raylib ships as the first of them.

## Features

* Flexbox sizing: `Fit`, `Fixed`, `Grow` and `Fill`, with `Shrink`, `Min` and `Max` on the same struct.
* Four layout passes in the order CSS uses, with wrapped text feeding back into the measurement.
* Ids derived from the tree, so a call site never carries one. `PushId` opens a scope for loops.
* Hover, press, click, double click, click count and focus, plus drag and drop.
* Scrolling per axis, with the bar laid out by the engine, and `EnsureVisible`.
* A Dear ImGui style draw list: a gradient per shape, a radius per corner, antialiasing and a clip stack.
* An embedded font, font merging, word wrap and per line alignment.
* No platform type in the engine, so a new backend is one file.

## Quick start

The host owns the window and the loop. Every frame runs the same sequence:

```odin
backend.Setup()   // once, after the platform surface exists

backend.Update()  // input, timing and the viewport
ui.Begin()
    if ui.Column({Pad = ui.Edge(8), Gap = 10}) {
        ui.Label("hello")
        if ui.Clicked() {
            // the label was clicked
        }
    }
ui.End()
backend.Render()  // draws the vertices the frame produced
```

Containers nest as `if` statements, and a leaf returns its id:

```odin
if ui.Row({Width = ui.Fill(), Pad = ui.Edge(16), Gap = 12, Align = .Center}) {
    ui.Label("Settings", Style = {Size = 22})
    if widgets.Button("Save", Width = ui.Fixed(120)) {
        Save()
    }
}
```

Run an example to see it move:

```
odin run examples/widgets
```

## Layout

`Row` and `Column` open a container that closes at the end of the block. `Open` and `Close` are the same pair without the sugar, for a widget that builds its own container.

`ui.Fit()` hugs the content, `ui.Fixed(px)` sets an exact size, `ui.Grow(weight)` takes a weighted share of the leftover space and `ui.Fill(weight)` divides the parent's space ignoring content. Bounds are fields on the same struct: `{Kind = .Fit, Min = 120, Max = 320}`.

Layout runs four passes in the order CSS runs them: intrinsic widths from the inside out, final widths from the outside in, intrinsic heights once every width is known, positions from the outside in. Floats are placed last, so every anchor is already arranged.

`Gap` spaces the children, `Justify` spreads them along the main axis and `Align` places them across it, where `Stretch` only touches children that did not size themselves. `Scroll` takes a `ScrollMode` per axis and the bar is part of the box, so nothing is laid out or painted under it.

## Interaction

An element id derives from its parent and its position in the tree, so a call site never carries one. `LastId` returns the element just declared and `ElementRect` answers its rect from the last published frame.

`Hovered`, `Pressed`, `Clicked`, `DoubleClicked`, `ClickCount`, `Focused` and `Activated` take an element id, or the last element declared when it is omitted. `HoveredId`, `PressedId`, `ClickedId` and `FocusedId` answer with an id instead, which is what a container or a global shortcut needs.

`Hit` decides what an element does with the pointer: `Ignore` hides it and its subtree, `Pass` observes without owning, `Stop` owns the whole box and `Auto` owns when nothing above it stops. `Storage(Element, T)` holds the per element state that outlives the frame.

## Text

Lato Regular is embedded, so `Label` renders with no setup and no asset to ship. More fonts come from `AddFontData` and `AddFontFile`, and `MergeFont` makes a second font supply the glyphs the first one lacks, which is how an icon font joins a text font.

`WrapMode.Word` breaks text at the width it was given, `TextAlign` places each line across it and `VerticalAlign` places the whole block down the height. `MaxLines` cuts the text at a line limit, and `Ellipsis` ends the cut line with `…`. Measured lines are cached by text, font and size, so a label that does not change costs a lookup.

## Drawing

Any element paints a box through `BoxStyle`: a background that is a flat color or a four corner gradient, a radius per corner, and a border per side. Containers and leaves take one, so a leaf that needs a background needs no container around it.

For everything else there is a draw list, shaped after Dear ImGui's `ImDrawList`: `AddRectFilled`, `AddRectStroke`, `AddRectGradient`, `AddCircleFilled`, `AddCircleStroke`, `AddCircleGradient`, `AddArc`, `AddTriangleFilled`, `AddTriangleStroke`, `AddTriangleGradient`, `AddPolygonFilled`, `AddPolygonStroke`, `AddPolygonGradient`, `AddRegularPolygonFilled`, `AddRegularPolygonStroke`, `AddRegularPolygonGradient`, `AddLine`, `AddImage`, `AddImageGradient` and `AddText`.

Shapes carry a one pixel transparent fringe, so their edges blend into what is behind them. `SetAntialias(false)` turns it off. Everything a frame emits lands in one vertex and index buffer, and a draw command is cut only when the texture or the clip changes.

`Custom` is the leaf whose look is a callback, run once its rect is known. Its `User` value is copied into the frame, so a widget can hand its context to the callback without allocating.

## Widgets

`widgets` is a separate package built on the engine alone: `Button`, `Checkbox`, a `Theme` with the palette, the metrics and the default style of every widget, and `SetTheme` to swap it at runtime.

```odin
if widgets.Button("Save", Width = ui.Fixed(140)) {
    Save()
}

widgets.Checkbox("Remember me", &Remember)
```

`examples/widgets` shows the widgets side by side and `examples/checkbox` a checkbox in its three states.

## Backends

A backend is one file with three entry points, and it owns neither the window nor the loop.

* `Setup` binds the clipboard and uploads the font atlas. Call it once, after the surface exists.
* `Update` feeds the frame: pointer, buttons, wheel, keys, typed text, the framebuffer size, the DPI scale and the delta time.
* `Render` walks `DrawData()`, drawing each command with the clip and the texture it carries, and applies the cursor `Cursor()` asks for.

Everything the engine consumes arrives through `ui.Add*` and everything a widget reads leaves through a `ui.*` query, so no engine code names a backend type.

## Building

The library reads its settings from Odin's build mode, so there is nothing to configure. Build an example with `-debug` while developing:

```
odin run examples/widgets -debug
```

A build meant for other people turns the optimizer on and drops the asserts:

```
odin build examples/widgets -o:speed -disable-assert
```

* `-o:speed` turns the optimizer on. The Odin default, `-o:minimal`, does little.
* With asserts on, a misuse traps: an unbalanced `PushId`, a duplicate element id. With `-disable-assert` the library reports through `BindError` and keeps running.

`BindError` is worth wiring in a build that ships. `SetUiScale` zooms the whole interface over the platform scale, so an application can offer 1x or 2x without touching a layout.

## Repository layout

* `ui/` holds the engine: layout, interaction, scrolling, the draw list and its shapes, text and fonts.
* `widgets/` holds the button, the checkbox and the theme, built on the engine alone.
* `backends/` holds one file per backend, each with the same three entry points.
* `examples/` holds runnable programs that import the engine and a backend.
* `docs/` holds the [changelog](docs/CHANGELOG.md) and the images.

## License

MIT License. See [LICENSE](LICENSE).

Copyright (C) 2026 Guilherme Avelar
