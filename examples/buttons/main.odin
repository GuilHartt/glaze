package main

import "core:fmt"
import rl "vendor:raylib"
import backend "../../backends/raylib"
import ui "../../ui"
import widgets "../../widgets"

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(420, 300, "Glaze buttons")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	backend.Setup()

	flat := widgets.CurrentTheme().Button
	flat.Corners = {}

	for !rl.WindowShouldClose() {
		backend.Update()

		ui.Begin()
		if ui.Column({Width = ui.Fill(), Height = ui.Fill(), Pad = ui.Edge(20), Gap = 12, Justify = .Center, Align = .Center}) {
			if widgets.Button("Rounded", Width = ui.Fixed(180)) {
				fmt.println("rounded clicked")
			}
			if widgets.Button("Flat", Width = ui.Fixed(180), Style = &flat) {
				fmt.println("flat clicked")
			}
			widgets.Button("Disabled", Width = ui.Fixed(180), Disabled = true)
		}
		ui.End()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		backend.Render()
		rl.EndDrawing()
	}
}
