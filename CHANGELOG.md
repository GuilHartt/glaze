# Changelog

## [0.6.0] - 2026-11-08

### Added

* `ImageFit` with `Stretch`, `Contain` and `Cover`, setting how a texture fills the image rect
* `AddImage` on the draw list, with an optional UV range for a cropped quad
* `AddTextureFile` and `RemoveTexture` on the raylib backend, which owns the texture lifetime
* `AddFramebufferSize`, `AddDpiScale` and `SetUiScale`, so the host reports the framebuffer and the zoom
* `Frame.Scale`, the framebuffer pixels per layout unit

### Changed

* `Texture` is a value with the backend handle and the pixel size, and an image takes its intrinsic size from it divided by the DPI
* `Image` takes a `Texture` and `Width` and `Height` sizing instead of a raw handle and a `Size`, and takes a `Fit`
* `ImageConfig` loses `Size` and gains `Fit`
* text measures and rasterizes at the effective scale and stays logical in the layout
* the pointer arrives in screen units, and `AddMousePos` divides it by the UI zoom
* `ViewportSize` returns layout units instead of the surface pixels
* the raylib backend divides the DPI out of `Frame.Scale`, since raylib already applies it
* the atlas uses bilinear filtering when it is recreated

### Removed

* `AddViewportSize`, replaced by `AddFramebufferSize` and `AddDpiScale`
* `ImageConfig.Size`, since the texture carries the pixel size

### Fixed

* the image leaf draws its texture through the list, so an image inside a clip or a scroll paints instead of only measuring
* the draw and the pointer share the framebuffer scale, so a click lands on the element it paints at 125%

## [0.5.1] - 2026-11-07

### Fixed

- the text cache owns the text it keys on, so text built in a temporary buffer no longer leaves a key pointing at freed memory
- the vertex and index buffers grow geometrically, so a large mesh no longer copies the whole buffer for every primitive
- the raylib backend binds the texture after it opens the primitive, so raylib 5.5 paints glyphs instead of solid quads
- the raylib backend uploads the atlas in `Setup`, so the first frame samples text instead of the default white texture
- `odin check -vet` passes with `glaze_errors_assert` on and off

### Removed

- `glaze_text_cache`, since the cache is also what owns the wrapped lines

## [0.5.0] - 2026-11-03

### Added

- `Wrap` on `Label`, with `None` and `Word`: `Word` breaks a line between words when it does not fit the width
- `Align` on `Label`, with `Left`, `Center` and `Right`, placing each line inside the width the label got
- `ScrollMode` for each axis, with `Disabled`, `Auto`, `Always`, `Never` and `Reserve`

### Changed

- layout runs in three passes, so text wraps against the width it ends up with and its height follows the lines
- `Scroll` is a mode per axis instead of a set of axes, and `Style.ScrollBar` is gone
- `Paint` takes a width and a height, and its callback receives the element id instead of a user pointer
- `Grow` and `Fill` shrink by default, so siblings give up space before they overflow
- the wrapped lines of a text are cached, keyed by the text, font, size, mode and width

### Fixed

- `Storage` keys on the id and the type, so one element can hold a value of each type
- a label draws inside its padding and border instead of over them

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
