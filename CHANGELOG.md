# Changelog

## [0.4.1] - 2026-11-01

### Added

- `Hit` in `LayoutConfig`, so a container claims every hit inside its rect, padding included
- the scroll bar takes its own strip from the layout, keeps a gap from the content, and its thumb can be dragged

### Fixed

- the wheel reads the rects and clips of the previous frame again, since it now runs at the start of the frame
- the clip a node is tested against is the one it was drawn inside, so a box answers over its padding and its bar

## [0.4.0] - 2026-10-31

### Added

- `Hovered`, `Pressed` and `Clicked` read one id each, decided once at the start of the frame
- a click needs the press and the release on the same element
- hover respects the clip and the draw order, so the topmost element wins
- `ErrorProc` and `BindError`, one place for the host to receive a misuse message
- `glaze_errors_assert` and `glaze_checks`, `#config` flags with explicit defaults

### Changed

- `Active` is now `Pressed`, and the state reads `hover_id`, `press_id` and `click_id`
- `Pressed` keeps the press after the pointer leaves, which is what a drag needs
- each node keeps the clip it was drawn with, so the hit test needs no maps
- `Close`, `PopId` and `End` report through the error channel instead of asserting in debug only
- the duplicate id check is a map instead of a quadratic scan

## [0.3.0] - 2026-10-30

### Added

- `PushClipRect` and `PopClipRect` on the draw list, nesting by intersection
- `Clip` and `Scroll` on `LayoutConfig`, independent of each other
- `ScrollAxis` and the `Scroll` set, so a box scrolls on either axis or both
- `Storage`, an id keyed place for widgets to keep their own state
- `ScrollOffset` and `SetScroll` for reading and writing a scroll position
- `Style.ScrollBar`, drawing a bar on every axis that overflows
- `AddTriangleStroke`, `AddRegularPolygonFilled` and `AddRegularPolygonStroke`

### Changed

- `Rounding` is now `CornerRadius`, and `Round` is `Corners`
- `Style.Radius` is a `CornerRadius`, so corners round independently
- `AddRect`, `AddCircle`, `AddPolygon` and `AddRegularPolygon` take a `Stroke` suffix
- `Viewport` became `ViewportSize`, and `AddViewport` became `AddViewportSize`
- the raylib backend scissors each command to its clip

### Fixed

- `justify` now measures the space left after flex, not before
- `Close` asserts a matching `Open` and no open `PushId`

## [0.2.0] - 2026-10-29

### Added

- `DrawData` returns vertices, indices and draw commands instead of a command list, so the backend draws one mesh
- shapes: rounded rectangles with radii per corner, four corner gradients, circles, arcs, triangles, polygons and lines
- `Paint`, a leaf whose drawing runs once its rect is known
- font loading with `AddFontData` and `AddFontFile`, plus `MergeFont` and `MeasureText`
- Lato Regular embedded, so text renders with no setup
- `ui/fonts/OFL.txt`, the license of the embedded font

### Changed

- text is measured and rasterized by the engine through fontstash, no longer by the host
- the backend uploads the glyph atlas and draws the mesh
- `AddText` and `AddTextRune` from input became `AddTypedText` and `AddTypedRune`
- `Label` takes a `Font`

### Removed

- `CommandRect`, `CommandText`, `CommandImage` and the `Command` union
- `MeasureTextProc` and `SetMeasureText`

## [0.1.0] - 2026-10-29

### Added

- two-pass layout: measure bottom-up, arrange top-down
- automatic ids from the parent and position, with `PushId` and `PopId` scopes
- text and image leaves sized by a backend callback
- typed draw-command list for the backend
- input state, delta time and clipboard
- raylib backend
