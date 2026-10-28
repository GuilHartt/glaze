# Glaze

A small immediate-mode UI engine written in [Odin](https://odin-lang.org).

Glaze borrows its layout model from Clay and its style and interaction feel from
Dear ImGui. You declare the tree on every frame, the engine measures and arranges
it, and the backend draws the resulting command list. There is no retained widget
tree, and no hidden state beyond what interaction needs.

The engine itself has no platform dependency. A backend is a thin adapter that
feeds events in and draws commands out, so the engine does not care which one is
in use. A raylib backend is included as the first of them.

> **Status: pre-1.0.** The API is still moving and a minor version may break it.
> The intent is to freeze the public surface at 1.0. Clipping, scrolling, text
> input and overlays are not implemented yet.

## How a frame works

`ui.Begin` opens the frame, elements are declared in between, and `ui.End` runs the
layout. Layout takes two passes: the tree is measured bottom-up, so every node
knows its natural size, then arranged top-down, so every node knows its final
rect. That split is what lets a child hug its content while its parent distributes
whatever space is left.

Sizing follows the flexbox vocabulary. `Grow`, `Fill`, `Fit` and `Fixed` build a
`Sizing`, and `Shrink`, `Min` and `Max` are plain fields on the same struct.
`Justify` distributes space along the main axis; `Align` positions children across
it, and `Stretch` only affects children that did not fix a size of their own.

Element ids are derived from the parent id and the element's position in the tree,
so a call site never carries one. `Hovered`, `Active` and `Clicked` target the last
element declared, and `PushId`/`PopId` open a scope when a subtree needs its own
namespace. The id that `Label` and `Image` return is only needed to target an
element other than the last one.

## Usage

The host program owns the window and the frame loop. Each frame it hands the frame
to the engine and asks the backend to draw what came out:

```odin
backend.Setup()   // once, after the window exists

backend.Update()  // per frame: input, timing and viewport
ui.Begin()
    if ui.Column({Gap = 10, Pad = ui.Pad(8)}) {
        ui.Label("hello")
        if ui.Clicked() {
            // ...
        }
    }
ui.End()
backend.Render()  // per frame: draw the commands
```

## Writing a backend

A backend is one file that exposes three procedures and stays out of the loop.

* `Setup` binds the text measurement callback and, where the platform has one,
  the clipboard.
* `Update` feeds the frame state: pointer, buttons, wheel, keys, typed text,
  delta time and the viewport.
* `Render` walks `ui.DrawData()` and draws each command.

Everything the engine consumes arrives through `ui.Add*`, and everything a widget
reads leaves through a `ui.*` query, so no engine code names a backend type. A new
platform means a new file under `backends/`, and nothing else changes.

## Repository layout

* `ui/` holds the engine: layout, input, draw commands and helpers.
* `backends/` holds one file per backend, each with the same three entry points.
* `examples/` holds runnable programs, including a raylib one.

## License

GNU Affero General Public License v3.0. See [LICENSE](LICENSE).

Copyright (C) 2026 Guilherme Avelar
