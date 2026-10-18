### BUILD SCENE

function build_level!(eng::RayEngine.Engine{GameParams,GameState})
    w = eng.world
    p = eng.params

    spawn!(eng.commands, w, Background(Style(;shader=file_shader("/Users/iday/Documents/RayEngine/example/src/background.fs"))))

    # player
    spawn!(eng.commands, w, PlayerBody(copy(p.spawn), [0.0, 0.0], [p.player_w, p.player_h], 1.0))


end

RayEngine.load_scene!(eng::RayEngine.Engine{GameParams,GameState}, ::Val{:game}) =
    build_level!(eng)

### STAGES

"Hotkeys that must work even while paused: debug overlay + pause toggle."
function input_controls(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    if key_pressed(eng.input, Raylib.KEY_F)
        p = eng.params
        p.show_debug[] = !p.show_debug[]
    end
    if key_pressed(eng.input, Raylib.KEY_P)
        s = eng.state
        s.status[] = s.status[] === :paused ? :running : :paused
    end
    return nothing
end

stage_input()      = (input_controls,)
stage_fixed()      = (player_input, physics)
stage_update()     = ()                                  # nothing frame-rate driven
stage_render()     = (clear, draw_scene)
stage_overlay()    = ()                                  # debug overlay handled by engine











"""
    run!(; headless=false)

Build and start the engine window. With `headless=true` it calls `simulate!` a few
frames so smoke tests / CI can run without a display.
"""
function run!(; headless::Bool = false, frames::Int = 1)
    p = GameParams()
    s = GameState()
    eng = RayEngine.Engine(
        p, s;
        config = RayEngine.EngineConfig(title = "RayEngine Platformer"),
        input      = stage_input,
        fixed_update = stage_fixed,
        update     = stage_update,
        render     = stage_render,
        overlay    = stage_overlay,
    )
    eng.state.scene[] = :game
    reset_scene!(eng)                 # runs load_scene!(Val(:game))

    if headless
        for _ in 1:frames
            simulate!(eng, 1 / 60)
        end
        return eng
    end
    RayEngine.start!(eng)
    return eng
end
