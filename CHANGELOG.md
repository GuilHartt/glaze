# Changelog

## [0.2.0] - 2026-10-29

### Added

- vertex, index and draw-command output, replacing the old command list
- shapes: rounded rects per corner, four corner gradients, circles, arcs, triangles, polygons and lines
- `Paint` leaves, so custom drawing is sized without a container
- text through fontstash, with Lato Regular embedded and `MergeFont` for icon fonts
- `ui/fonts/OFL.txt`, the license of the embedded font

### Changed

- the backend uploads the glyph atlas and draws the mesh
- `AddPolyline` and `AddConvexPolyFilled` became `AddPolygon` and `AddPolygonFilled`
- `AddText` and `AddTextRune` from input became `AddTypedText` and `AddTypedRune`
- `TextBounds` became `MeasureText`
- `Paint` is a leaf, no longer a callback on the last element

### Removed

- `SetMeasureText` and `MeasureTextProc`, the engine measures text itself
- `CommandRect`, `CommandText`, `CommandImage` and the `Command` union
- `ui/command.odin`, replaced by `ui/draw.odin`

## [0.1.0] - 2026-10-29

### Added

- two-pass layout: measure bottom-up, arrange top-down
- automatic ids from the parent and position, with `PushId` and `PopId` scopes
- text and image leaves sized by a backend callback
- typed draw-command list for the backend
- input state, delta time and clipboard
- raylib backend
