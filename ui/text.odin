#+feature global-context
package ui

import "core:strings"
import "vendor:fontstash"

// Line is one wrapped line: the byte range it covers in the source, and the width
// it takes on screen.
Line :: struct {
	Start, End: u32,
	Width:      f32,
}

// lines is the scratch the wrap writes into, so a frame reuses its capacity instead
// of allocating once per label.
@(private) lines: [dynamic]Line

// stale is the scratch the purge collects keys in before deleting them, so a frame
// does not allocate to walk the cache.
@(private="file") stale: [dynamic]LabelKey

// LabelKey is what a wrapped result depends on: the words themselves, and the font,
// size, mode and width they were broken for. Text that matches shares one entry, and
// the cache owns a copy of `text`, so a key outlives the caller's buffer.
LabelKey :: struct {
	text:  string,
	font:  Font,
	size:  f32,
	mode:  WrapMode,
	width: f32,
}

// LabelCache is the wrapped layout of one text, keyed by everything that would
// invalidate it. `frame` is what the purge reads to drop the entries no label asked
// for.
LabelCache :: struct {
	frame: u32,
	block: Vec2,
	lines: [dynamic]Line,
}

@(private="file")
label_cache: map[LabelKey]LabelCache

// WrapText breaks `Text` into lines according to `Mode`, measuring with `Font` at
// `Size`. A line is a byte range in the source, so no text is copied, and the result
// is valid until the next call. Every mode breaks at the newlines, and only Word
// breaks by `MaxWidth` as well.
WrapText :: proc(Text: cstring, Font: Font, Size: f32, Mode: WrapMode, MaxWidth: f32) -> []Line {
	clear(&lines)
	if Text == nil || Size <= 0 do return lines[:]

	fontstash.SetFont(&font_ctx, int(Font))
	fontstash.SetSize(&font_ctx, Size)

	src, space := string(Text), measure(" ")
	limit := MaxWidth if Mode == .Word else f32(0)
	start: int
	for i in 0 ..= len(src) {
		if i < len(src) && src[i] != '\n' do continue
		wrap_paragraph(src[start:i], start, limit, space)
		start = i + 1
	}
	return lines[:]
}

// label_measure returns the block size a text takes at `Width` and the lines it broke
// into, wrapping when the key changed and reusing the entry otherwise. The measure
// pass keeps both on the node, so the draw never asks twice.
@(private)
label_measure :: proc(Content: TextContent, Width: f32) -> (block: Vec2, broken: []Line) {
	cached := cached_label(Content, Width)
	return cached.block, cached.lines[:]
}

// cached_label returns the entry for this text, wrapping again when the key changed,
// and marks it as used in the current frame.
@(private="file")
cached_label :: proc(Content: TextContent, Width: f32) -> ^LabelCache {
	key := LabelKey{
		text  = string(Content.text),
		font  = Content.font,
		size  = Content.config.Size,
		mode  = Content.config.Wrap,
		width = Width,
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

// label_purge drops the entries no label asked for in the frame that just ended, so a
// text that disappears does not keep its lines forever.
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

// wrap_block wraps the text once and returns the size of the block it forms: the
// widest line by the stacked line heights.
@(private="file")
wrap_block :: proc(Content: TextContent, Width: f32) -> Vec2 {
	width: f32
	for line in WrapText(Content.text, Content.font, Content.config.Size, Content.config.Wrap, Width) {
		width = max(width, line.Width)
	}
	height := MeasureText("", Content.font, Content.config.Size).y * f32(len(lines))
	return {width, height}
}

// wrap_paragraph appends the lines of one paragraph, which holds no newline, and
// never splits a word: one wider than the line overflows it, which is what the web
// does by default.
@(private="file")
wrap_paragraph :: proc(P: string, Offset: int, MaxWidth, Space: f32) {
	if len(P) == 0 {
		append(&lines, Line{u32(Offset), u32(Offset), 0})
		return
	}

	// The whole paragraph fitting is the common case, and it costs one measurement.
	width := measure(P)
	if MaxWidth <= 0 || width <= MaxWidth {
		append(&lines, Line{u32(Offset), u32(Offset + len(P)), width})
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

		append(&lines, Line{u32(Offset + start), u32(Offset + fit), line})
		start = fit + 1
	}
}

// measure returns the width `Text` takes. It measures the slice itself, since
// fontstash reads a length and not a terminator, and it assumes WrapText already set
// the font and the size.
@(private="file")
measure :: proc(Text: string) -> f32 { return fontstash.TextBounds(&font_ctx, Text) }
