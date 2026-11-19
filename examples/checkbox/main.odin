package main

import rl "vendor:raylib"
import backend "../../backends/raylib"
import ui "../../ui"
import widgets "../../widgets"

style: widgets.CheckboxStyle
checked: bool = true
unchecked: bool
disabled: bool = true

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(420, 300, "Glaze checkbox")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	backend.Setup()

	theme := widgets.CurrentTheme()

	style = widgets.CurrentTheme().Checkbox
	style.Box = 28
	style.FontSize = 18
	style.Pad = ui.Edge(12, 10)
	style.Gap = 10

	for !rl.WindowShouldClose() {
		backend.Update()

		ui.Begin()
		if ui.Column({ Width = ui.Fill(), Height = ui.Fill(), Pad = ui.Edge(20), Gap = 12, Justify = .Center, Align = .Center}) {
			widgets.Checkbox("Checked", &checked, Width = ui.Fixed(180), Style = &style)
			widgets.Checkbox("Unchecked", &unchecked, Width = ui.Fixed(180), Style = &style)
			widgets.Checkbox("Disabled", &disabled, Width = ui.Fixed(180), Style = &style, Disabled = true)
		}
		ui.End()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		backend.Render()
		rl.EndDrawing()
	}
}
