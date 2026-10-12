### BUILD SCENE

function build_level!(eng::RayEngine.Engine{GameParams,GameState})
    w = eng.world
    p = eng.params

    # floor
    spawn!(eng.commands, w, Platform([0.0, 680.0], [1280.0, 60.0], true))
    # a few platforms to hop between
    spawn!(eng.commands, w, Platform([250.0, 600.0], [160.0,  24.0], true))
    spawn!(eng.commands, w, Platform([500.0, 550.0], [160.0, 24.0], true))
    spawn!(eng.commands, w, Platform([820.0, 400.0], [160.0, 24.0], true))
    spawn!(eng.commands, w, Platform([560.0, 300.0], [160.0, 24.0], true))
    spawn!(eng.commands, w, Platform([260.0, 220.0], [160.0, 24.0], true))
    # goal
    spawn!(eng.commands, w, Platform([260.0, 160.0], [60.0, 60.0], false))

    # player
    spawn!(eng.commands, w, PlayerBody(copy(p.spawn), [0.0, 0.0], [p.player_w, p.player_h], false, 1.0))

    # text
    spawn!(eng.commands, w, Writing("Hi!\n This is a game made in my game engine.\n It was programmed using Julia, a language\nthat was not designed for making game engines.", [250.0, 400.0], 20))
    spawn!(eng.commands, w, Writing("Go here to win!", [260.0, 130.0], 15))
    return nothing
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
stage_fixed()      = (player_input, physics, respawn, keep_in_view)
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
