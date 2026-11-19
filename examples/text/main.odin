package main

import rl "vendor:raylib"
import backend "../../backends/raylib"
import ui "../../ui"

LOREM :: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.\n\nDuis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

BODY :: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud."

TEAL    :: ui.Color{0x4D, 0xD0, 0xC4, 0xFF}
MAGENTA :: ui.Color{0xFF, 0x2D, 0x95, 0xFF}
PURPLE  :: ui.Color{0xA8, 0x55, 0xF7, 0xFF}
AMBER   :: ui.Color{0xF5, 0xB3, 0x01, 0xFF}

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(720, 640, "Glaze text")
	defer rl.CloseWindow()
	backend.Setup()

	for !rl.WindowShouldClose() {
		backend.Update()

		ui.Begin()
		screen()
		ui.End()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		backend.Render()
		rl.EndDrawing()
	}
}

screen :: proc() {
	if ui.Column({Width = ui.Fill(), Height = ui.Fill(), Pad = ui.Edge(32), Gap = 20}) {
		section("JUSTIFY", TEAL, LOREM, {Size = 20, TextAlign = .Justify, Wrap = .Word})
		section("LEFT", MAGENTA, BODY, {Size = 20, TextAlign = .Left, Wrap = .Word})
		section("CENTER", PURPLE, BODY, {Size = 20, TextAlign = .Center, Wrap = .Word})
		section("RIGHT", AMBER, BODY, {Size = 20, TextAlign = .Right, Wrap = .Word})
		section("ELLIPSIS", TEAL, LOREM, {Size = 20, TextAlign = .Justify, Wrap = .Word, MaxLines = 2, Ellipsis = true})
	}
}

section :: proc(Title: cstring, Tint: ui.Color, Body: cstring, Style: ui.LabelStyle) {
	ui.Label(Title, {Width = ui.Fill()}, {Size = 12, Color = Tint})
	ui.Label(Body, {Width = ui.Fill()}, Style)
}
