#+feature global-context
package ui

import "core:fmt"
import "core:os"
import "vendor:fontstash"

// Font identifies a font loaded into the engine. Zero is the first font loaded.
Font :: distinct int

// font_ctx is the shared glyph atlas. Every font rasterizes into it, which is what
// lets text and shapes share one texture.
@(private)
font_ctx: fontstash.FontContext

// atlas_texture is the handle the backend created for the atlas.
@(private)
atlas_texture: Texture

// BUILTIN_FONT_DATA is the font the engine starts with, so a label renders without
// any setup. It is Lato Regular, under the SIL Open Font License in fonts/OFL.txt.
@(private)
BUILTIN_FONT_DATA :: #load("fonts/Lato-Regular.ttf")

// font_init builds the glyph atlas and loads the builtin font before main runs, so
// no call site has to guard against an uninitialized atlas.
@(init)
font_init :: proc() {
	fontstash.Init(&font_ctx, 512, 512, .TOPLEFT)
	fontstash.AddFontMem(&font_ctx, "lato", BUILTIN_FONT_DATA, false)
}

// AddFontData loads a font from memory and returns its handle. The engine takes
// ownership of `Data`.
AddFontData :: proc(Data: []u8) -> Font {
	name := fmt.tprintf("font-%d", len(font_ctx.fonts))
	return Font(fontstash.AddFontMem(&font_ctx, name, Data, true))
}

// AddFontFile loads a font from a file and returns its handle.
AddFontFile :: proc(Path: string) -> (Font, bool) {
	Data, err := os.read_entire_file(Path, context.allocator)
	if err != nil do return 0, false
	return AddFontData(Data), true
}

// MergeFont makes `Fallback` supply the glyphs that `Base` lacks, which is how an
// icon font joins a text font.
MergeFont :: proc(Base, Fallback: Font) -> bool {
	return fontstash.AddFallbackFont(&font_ctx, int(Base), int(Fallback))
}

// MeasureText returns the size `Text` occupies in `Font` at `Size`: the advance
// width and the line height.
MeasureText :: proc(Text: cstring, Font: Font, Size: f32) -> Vec2 {
	if len(font_ctx.fonts) == 0 || Size <= 0 do return {}

	fontstash.SetFont(&font_ctx, int(Font))
	fontstash.SetSize(&font_ctx, Size)

	advance := fontstash.TextBounds(&font_ctx, string(Text))
	_, _, line_height := fontstash.VerticalMetrics(&font_ctx)
	return {advance, line_height}
}

// FontAtlas returns the atlas pixels and its size, for the backend to upload. The
// pixels are one byte of coverage per texel.
FontAtlas :: proc() -> (Pixels: []u8, Width, Height: int) {
	return font_ctx.textureData, font_ctx.width, font_ctx.height
}

// TakeAtlasUpdate reports whether the atlas changed since the last call and clears
// the pending region. The backend re-uploads the atlas when it is true.
TakeAtlasUpdate :: proc() -> bool {
	dirty: [4]f32
	return fontstash.ValidateTexture(&font_ctx, &dirty)
}

// SetAtlasTexture stores the handle the backend created for the atlas.
SetAtlasTexture :: proc(T: Texture) {
	atlas_texture = T
}
