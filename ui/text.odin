#+feature global-context
package ui

import "core:strings"
import "vendor:fontstash"

// Line is one wrapped line: the byte range it covers in the source, the width it takes in
// layout units, and whether the text was cut there.
Line :: struct {
	Start, End: u32,
	Width:      f32,
	Truncated:  bool,
}

// ELLIPSIS ends a line the text was cut on.
@(private)
ELLIPSIS :: "…"

// lines is the scratch the wrap writes into, so a frame reuses its capacity.
@(private) lines: [dynamic]Line

// stale is the scratch the purge collects keys in before deleting them.
@(private="file") stale: [dynamic]LabelKey

// LabelKey is what a wrapped result depends on: the words, and the font, size, mode, width,
// line limit, ellipsis and scale they were broken for. Text that matches shares one entry, and
// the cache owns a copy of `text`, so a key outlives the caller's buffer.
@(private="file")
LabelKey :: struct {
	text:     string,
	font:     Font,
	size:     f32,
	mode:     WrapMode,
	width:    f32,
	maxLines: u16,
	ellipsis: bool,
	scale:    f32,
}

// LabelCache is the wrapped layout of one text. `frame` is what the purge reads to drop the
// entries no label asked for.
@(private="file")
LabelCache :: struct {
	frame: u32,
	block: Vec2,
	lines: [dynamic]Line,
}

@(private="file")
label_cache: map[LabelKey]LabelCache

// WrapText breaks `Text` into lines according to `Mode`, measuring with `Font` at `Size`. A
// line is a byte range in the source, so no text is copied, and the result is valid until the
// next call. Only `Word` breaks by `MaxWidth`; `MaxLines` stops the text and `Ellipsis` marks
// the line it stopped on.
WrapText :: proc(
	Text: string,
	Font: Font,
	Size: f32,
	Mode: WrapMode,
	MaxWidth: f32,
	MaxLines: u16 = 0,
	Ellipsis: bool = false,
) -> []Line {
	clear(&lines)
	if len(Text) == 0 || Size <= 0 do return lines[:]

	scale := effective_scale()
	fontstash.SetFont(&font_ctx, int(Font))
	fontstash.SetSize(&font_ctx, Size * scale)

	src, space := Text, measure(" ")
	limit := MaxWidth * scale if Mode == .Word else f32(0)

	// Without a width there is nothing to cut against, so an intrinsic measurement keeps the
	// whole text.
	cap := MaxLines if MaxWidth > 0 else u16(0)

	start: int
	for i in 0 ..= len(src) {
		if i < len(src) && src[i] != '\n' do continue
		wrap_paragraph(src[start:i], start, limit, space, scale, cap)
		start = i + 1
		if cap > 0 && len(lines) > int(cap) do break
	}

	if MaxLines > 0 && len(lines) > int(MaxLines) && MaxWidth > 0 {
		resize(&lines, int(MaxLines))
		cut(&lines[len(lines) - 1], src, MaxWidth * scale, space, scale, Ellipsis)
	}
	return lines[:]
}

// MeasureTextWrapped returns the block size `Text` occupies when wrapped to `Width`, in layout
// units: the widest line by the stacked line height.
MeasureTextWrapped :: proc(
	Text: string,
	Font: Font,
	Size: f32,
	Mode: WrapMode,
	Width: f32,
	MaxLines: u16 = 0,
	Ellipsis: bool = false,
) -> Vec2 {
	broken := WrapText(Text, Font, Size, Mode, Width, MaxLines, Ellipsis)
	widest: f32
	for line in broken do widest = max(widest, line.Width)
	return {widest, MeasureText("", Font, Size).y * f32(len(broken))}
}

// label_measure returns the block size a text takes at `Width` and the lines it broke into,
// reusing the cached entry when the key did not change.
@(private)
label_measure :: proc(Content: TextContent, Width: f32) -> (block: Vec2, broken: []Line) {
	cached := cached_label(Content, Width)
	return cached.block, cached.lines[:]
}

// cached_label returns the entry for this text, wrapping again when the key changed, and
// marks it as used in the current frame.
@(private="file")
cached_label :: proc(Content: TextContent, Width: f32) -> ^LabelCache {
	key := LabelKey{
		text     = Content.text,
		font     = Content.font,
		size     = Content.size,
		mode     = Content.wrap,
		width    = Width,
		maxLines = Content.max_lines,
		ellipsis = Content.ellipsis,
		scale    = effective_scale(),
	}

	if cached, ok := &label_cache[key]; ok {
		cached.frame = state.frame
		return cached
	}

	key.text = strings.clone(key.text)
	block := wrap_block(Content, Width)

	label_cache[key] = LabelCache{frame = state.frame, block = block}
	cached := &label_cache[key]

	resize(&cached.lines, len(lines))
	copy(cached.lines[:], lines[:])
	return cached
}

// label_purge drops the entries no label asked for in the frame that just ended.
@(private)
label_purge :: proc() {
	clear(&stale)
	for key, cached in label_cache {
		if cached.frame != state.frame do append(&stale, key)
	}
	for key in stale {
		if cached, ok := label_cache[key]; ok do delete(cached.lines)
		delete_key(&label_cache, key)
		delete(key.text)
	}
}

// wrap_block wraps the text once and returns the size of the block it forms: the widest
// line by the stacked line heights.
@(private="file")
wrap_block :: proc(Content: TextContent, Width: f32) -> Vec2 {
	width: f32
	for line in WrapText(Content.text, Content.font, Content.size, Content.wrap, Width, Content.max_lines, Content.ellipsis) {
		width = max(width, line.Width)
	}
	height := MeasureText("", Content.font, Content.size).y * f32(len(lines))
	return {width, height}
}

// cut shortens `line` to fit `MaxWidth` with the ellipsis, landing between words.
@(private="file")
cut :: proc(line: ^Line, Source: string, MaxWidth, Space, Scale: f32, Ellipsis: bool) {
	line.Truncated = true
	if !Ellipsis do return

	room, tail := MaxWidth, measure(ELLIPSIS)
	room -= tail

	// A paragraph end, or no width to break against, keeps its words and only gains the mark.
	if room <= 0 || line.Width*Scale <= room {
		line.Width = (line.Width*Scale + tail) / Scale
		return
	}

	start := int(line.Start)
	cursor, fit, width := start, start, f32(0)

	for cursor < len(Source) && Source[cursor] != '\n' {
		end := cursor
		for end < len(Source) && Source[end] != ' ' && Source[end] != '\n' do end += 1

		w := measure(Source[cursor:end])
		gap := Space if fit > start else 0
		if fit > start && width + gap + w > room do break

		width += gap + w
		fit = end
		cursor = end + 1
	}

	line.End, line.Width = u32(fit), (width + tail) / Scale
}

// wrap_paragraph appends the lines of one paragraph, which holds no newline, and never
// splits a word: one wider than the line overflows it, which is what the web does. It stops a
// line past `MaxLines`.
@(private="file")
wrap_paragraph :: proc(P: string, Offset: int, MaxWidth, Space: f32, Scale: f32, MaxLines: u16) {
	if len(P) == 0 {
		append(&lines, Line{u32(Offset), u32(Offset), 0, false})
		return
	}

	// The whole paragraph fitting is the common case, and it costs one measurement.
	width := measure(P)
	if MaxWidth <= 0 || width <= MaxWidth {
		append(&lines, Line{u32(Offset), u32(Offset + len(P)), width / Scale, false})
		return
	}

	start := 0
	for start < len(P) {
		line, fit := f32(0), start

		for cursor := start; cursor < len(P); {
			end := cursor
			for end < len(P) && P[end] != ' ' do end += 1

			w := measure(P[cursor:end])
			gap := Space if fit > start else 0
			if fit > start && line + gap + w > MaxWidth do break

			line += gap + w
			fit = end
			cursor = end + 1
		}

		append(&lines, Line{u32(Offset + start), u32(Offset + fit), line / Scale, false})
		if MaxLines > 0 && len(lines) > int(MaxLines) do return

		start = fit + 1
	}
}

// measure returns the width `Text` takes. It measures the slice itself, since fontstash
// reads a length and not a terminator.
@(private="file")
measure :: proc(Text: string) -> f32 { return fontstash.TextBounds(&font_ctx, Text) }
