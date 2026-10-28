package ui

CommandRect :: struct {
	Bounds: Rect,
	Color:  Color,
	Radius: f32,
	Border: Border,
}

CommandText :: struct {
	Bounds: Rect,
	Text:   cstring,
	Color:  Color,
	Size:   f32,
}

CommandImage :: struct {
	Bounds: Rect,
	Handle: rawptr,
	Tint:   Color,
}

Command :: union {
	CommandRect,
	CommandText,
	CommandImage,
}

@(private)
build_commands :: proc() {
	for n in state.nodes {
		switch content in n.content {
			case TextContent:
				append(&state.cmds, CommandText{
					n.rect,
					content.text,
					content.config.Color,
					content.config.Size,
				})
			case ImageContent:
				append(&state.cmds, CommandImage{
					n.rect,
					content.handle,
					content.config.Tint,
				})
			case:
				if n.style.Background.a != 0 || n.style.Border.Width > 0 {
					append(&state.cmds, CommandRect{
						n.rect,
						n.style.Background,
						n.style.Radius,
						n.style.Border,
					})
				}
		}
	}
}
