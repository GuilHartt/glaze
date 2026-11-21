package main

import rl "vendor:raylib"
import backend "../../backends/raylib"
import ui "../../ui"
import widgets "../../widgets"

LOREM :: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.\n\nUt enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.\n\nDuis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.\n\nExcepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.\n\nSed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam.\n\nNemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores.\n\nNeque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit.\n\nUt enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam."

name: [dynamic]u8
price: [dynamic]u8
code: [dynamic]u8
secret: [dynamic]u8
contact: [dynamic]u8
body: [dynamic]u8

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(420, 560, "Glaze text input")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	backend.Setup()

	defer delete(name)
	defer delete(price)
	defer delete(code)
	defer delete(secret)
	defer delete(contact)
	defer delete(body)

	append(&code, "GLZ-0042")
	append(&contact, "you@example.com")
	append(&body, LOREM)

	muted := widgets.CurrentTheme().Color[.Muted]

	for !rl.WindowShouldClose() {
		backend.Update()

		ui.Begin()
		if ui.Column({Width = ui.Fill(), Height = ui.Fill(), Pad = ui.Edge(20), Gap = 12}) {
			caption("PLAIN", muted)
			widgets.TextInput(&name, Placeholder = "Name")

			caption("DECIMAL FILTER", muted)
			widgets.TextInput(&price, Filter = widgets.FilterDecimal, Placeholder = "0.00")

			caption("UPPERCASE FILTER, MAX 8", muted)
			widgets.TextInput(&code, Filter = widgets.FilterUppercase, MaxChars = 8, Placeholder = "CODE")

			caption("MASK", muted)
			widgets.TextInput(&secret, Mask = '*', Placeholder = "Password")

			caption("READ ONLY", muted)
			widgets.TextInput(&contact, ReadOnly = true)

			caption("MULTI-LINE, WRAP, TAB", muted)
			widgets.TextEdit(&body, Height = ui.Fill(), Wrap = true)
		}
		ui.End()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		backend.Render()
		rl.EndDrawing()
	}
}

caption :: proc(Text: string, Tint: ui.Color) {
	ui.Label(Text, {Hit = .Ignore}, {Size = 12, Color = Tint})
}
