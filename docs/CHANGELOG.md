# Changelog

## [0.9.0] - 2026-11-21

### Added

* `widgets`, a layer on the public surface: `Button`, `Checkbox`, `HSlider`, `VSlider`, `TextInput` and `TextEdit`
* `Theme`, `DefaultTheme`, `CurrentTheme` and `SetTheme`, one theme for the whole widget layer
* `TextEdit`, a multi-line editor that wraps, takes tabs and scrolls through the layout
* `TextInput`, one line, with `Mask`, `ReadOnly`, `MaxChars` and a `CharFilter`
* `FilterDigits`, `FilterDecimal`, `FilterHexadecimal` and `FilterUppercase`
* `Custom`, a leaf that paints its own content, with `CustomProc` and `CustomContent`
* `LabelStyle`, `ImageStyle` and `BoxStyle`, one style per element
* `ContainerConfig` and `ElementConfig`, one config per kind
* `VerticalAlign`, and `MaxLines` with `Ellipsis` on a label
* `InnerRect`, the box a node places its children in
* `SetAntialias`, `PushAntialias` and `PopAntialias`, so the host or a scope decides whether a shape feathers
* `ClaimTab`, which keeps a plain Tab for one element
* `DestroyProc`, so the state stored under an id is freed with its entry
* `SetKeyRepeat`, the delay and the rate a held key repeats at

### Changed

* ids come from the call site, so an element inside a conditional no longer shifts the ids below it
* `Storage` is an open-addressed table keyed by id and type, and the dead entries leave by a sweep with a fixed cost per frame
* the tree, the input and the state are private
* the text surface takes `string`, and a backend converts to `cstring` at its own boundary

### Removed

* `Paint`, replaced by `Custom`
* `PaintProc`, replaced by `CustomProc`
* `LayoutConfig`, replaced by `ContainerConfig`
* `ImageConfig`, since `ElementConfig` and `ImageStyle` carry it
* `Screen`, `Node`, `State`, `Input`, `Content`, `Placement` and `Time`, which live inside the package now

### Fixed

* a tab measures and paints as four spaces instead of a missing glyph
* a reserved scroll bar hides when the content fits
* a full circle no longer closes on a duplicate point

## [0.8.0] - 2026-11-17

### Added

* `HitMode`, with `Auto`, `Stop`, `Pass` and `Ignore`, so an element decides whether it is seen, observes or owns a press, and the leaves take `Hit` beside their size
* `Floating`, a block out of the flow anchored to an element, the parent, the root or the pointer, with a pivot and a viewport clamp, above the tree
* `SetStyle`, so a widget picks the hover or pressed look after opening its element
* `LastId`, the id of the last element declared, which the interaction queries use when no id is given
* `SetCursor`, `Cursor` and `CursorIcon`, a cursor request per frame that the backend reads after `End`
* `Focusable`, `Focused`, `RequestFocus` and `ClearFocus`, with Tab walking the declaration order
* `DoubleClicked` and `ClickCount`, counting clicks on one element within 0.30 s and 6 layout units
* `Dragging`, `DragTarget`, `AcceptDragDropPayload` and `SetDragDropPayload`, moving typed data between a source and one target
* `HoveredId`, `PressedId`, `ClickedId` and `FocusedId`, so the host reads the interaction owner without testing every id
* `Activated`, one test for a click or a focused Enter/Space
* `ElapsedTime`, `FrameCount` and `MeasureTextWrapped`
* `ElementRect`, the rect an element had in the last finished layout, readable while the next frame is being declared
* `EnsureVisible`, scrolling the scrolling ancestors of an element after `End`

### Changed

* `HitMode` replaces `Hit`, and `Hovered` answers for the element and its ancestors while `Pressed` and `Clicked` answer for the owner
* `Pressed` and `Clicked` take a mouse button, so each button has its own owner
* the wheel consumes the delta from the deepest container and hands the rest to the parent
* `RequestFocus(0)` targets the last element, and `ClearFocus` clears the focus
* `Id` is `ElementId`, and the public surface takes an `Element`
* `PushId` takes an explicit seed, which stays stable when a list is reordered and does not shift the following automatic ids
* the library reads its checks and asserts from Odin's build mode

### Removed

* `Hit`, replaced by `HitMode`
* `glaze_errors_assert` and `glaze_checks`, since the build mode decides
* `LabelCache` and `LabelKey` are no longer public

### Fixed

* `ElementRect` ignores a placement the arrangement did not write, so a stale rect never answers
* `LastId` returns 0 before the first frame instead of reading an empty array
* only `Auto` scroll writes and reads the strip storage, so a tree without it keeps the map empty

### Performance

* measure and resolve walk the flat pre-order array, and the hover chain and a floating anchor follow parent indices instead of scanning the node array

## [0.7.0] - 2026-11-14

### Added

* `Gradient`, the four corner colors a fade is made of
* `AddCircleGradient`, `AddTriangleGradient`, `AddPolygonGradient`, `AddRegularPolygonGradient` and `AddImageGradient`, so every filled shape takes a fade
* `Edges`, one length per side, and `Edge` to build it

### Changed

* `PaintProc` replaces `DrawProc` and joins `Content`, so a custom leaf carries its own painting instead of a field on the node
* `Label`, `Image` and `Paint` take `Style`, `Width` and `Height`, so a leaf paints a box and takes a size without a `Row` or `Column` around it
* `Style.Background` is a `Background`, either one flat color or a `Gradient`
* `Style` carries `BorderColor` and `BorderWidth` as two fields, and `BorderWidth` measures each side, so a box underlines one side or rules between children
* `AddRectGradient` takes one `Gradient` instead of four loose colors
* `TextConfig` is gone, and its fields live on `TextContent`
* `Padding` is now `Edges` and `Pad` is now `Edge`, since the type also measures border thickness
* the three leaves take the payload, then the sizing, then the look, then the style, in that order
* an equal border on every side keeps the corner radius, and sides that differ paint as plain edges

### Removed

* `DrawProc`, replaced by `PaintProc`
* `Border`, replaced by `Style.BorderColor` and `Style.BorderWidth`
* `TextConfig`, since its fields moved to `TextContent`

### Fixed

* `inset`, `inner_rect` and the scroll bar measure the border per side instead of twice one width

## [0.6.1] - 2026-11-14

### Added

* `RectOverlaps`, which reports whether two rects share any area

### Fixed

* a scrolling axis clips even when it draws no bar, so `.Never` cuts the content that overflows
* a text wider than its box still draws, since the cull measures the painted block instead of the inner rect
* a stroke fills the wedge at each interior vertex, so corners stop notching

### Performance

* a node whose rect misses the clip skips its background, its border, its paint callback and its bar, and its text and image are culled too
* a convex fill writes one vertex per path point and indexes the fan into them, instead of three vertices per triangle
* a stroke edge writes one quad, four vertices instead of six

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
