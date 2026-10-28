package main

import "core:fmt"
import rl "vendor:raylib"
import backend "../../backends/raylib"
import ui "../../ui"

main :: proc() {
    rl.InitWindow(1280, 720, "Glaze raylib example")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    backend.Setup()

    for !rl.WindowShouldClose() {
        backend.Update()

        ui.Begin()
            if ui.Column({Gap = 10, Pad = ui.Pad(5)}) {
                for i in 0..=10 {
                    ui.Label(fmt.ctprintf("hello %i", i))
                    if ui.Clicked() {
                        fmt.println(i)
                    }
                }
            }
        ui.End()

        rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)
            backend.Render()
        rl.EndDrawing()
    }
}
