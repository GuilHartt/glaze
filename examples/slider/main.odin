package main

import "core:fmt"
import rl "vendor:raylib"
import backend "../../backends/raylib"
import ui "../../ui"
import widgets "../../widgets"

style: widgets.SliderStyle
volume: f32 = 0.5
quality: i32 = 2
locked: f32 = 0.25

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(420, 380, "Glaze slider")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	backend.Setup()

	style = widgets.CurrentTheme().Slider
	style.KnobRadius = 9
	style.Fill[.Normal] = ui.Hex(0x22D3EE)
	style.Fill[.Hovered] = ui.Hex(0x22D3EE)

	for !rl.WindowShouldClose() {
		backend.Update()

		ui.Begin()
		if ui.Column({Width = ui.Fill(), Height = ui.Fill(), Pad = ui.Edge(20), Gap = 16, Justify = .Center, Align = .Center}) {
			if ui.Row({Gap = 12, Align = .Center}) {
				widgets.HSlider(&volume, 0, 1, Step = 0.05, Width = ui.Fixed(220))
				ui.Label(fmt.ctprintf("%.2f", volume), {Width = ui.Fixed(48), Hit = .Ignore}, {Size = 14, TextAlign = .Right})
			}
			if ui.Row({Gap = 12, Align = .Center}) {
				widgets.HSlider(&quality, 0, 4, Width = ui.Fixed(220))
				ui.Label(fmt.ctprintf("%v", quality), {Width = ui.Fixed(48), Hit = .Ignore}, {Size = 14, TextAlign = .Right})
			}
			if ui.Row({Gap = 12, Align = .Center}) {
				widgets.HSlider(&locked, 0, 1, Width = ui.Fixed(220), Disabled = true)
				ui.Label(fmt.ctprintf("%.2f", locked), {Width = ui.Fixed(48), Hit = .Ignore}, {Size = 14, TextAlign = .Right})
			}
			if ui.Column({Gap = 6, Align = .Center}) {
				widgets.VSlider(&volume, 0, 1, Height = ui.Fixed(120), Style = &style)
				ui.Label(fmt.ctprintf("%.2f", volume), {Hit = .Ignore}, {Size = 14, TextAlign = .Center})
			}
		}
		ui.End()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		backend.Render()
		rl.EndDrawing()
	}
}
