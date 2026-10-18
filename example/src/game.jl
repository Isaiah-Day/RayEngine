### BUILD SCENE

"""
    build_level!(eng)

Reset the run: one player at `params.spawn`, the first beacon of the tour.
Called by `reset_scene!`, so `R` is a complete restart.
"""
function build_level!(eng::RayEngine.Engine{GameParams,GameState})
    p, st, w = eng.params, eng.state, eng.world

    st.player = spawn!(
        w,
        PlayerBody(
            copy(p.spawn), [0.0, 0.0], p.player_r,
            (0.5, 0.5, 0.5), (0.0, 0.0), [copy(p.spawn)],
        ),
    )
    st.goal = spawn!(w, Goal(copy(p.goals[1]), p.goal_r, 1))

    st.goal_clock = p.goal_time
    st.captured[] = 0

    # Reset the field to its opening snapshot and the shift cadence.
    st.field_time = FIELD_TIME_OFFSET
    st.shifts = 0
    p.shift_every = FIELD_SHIFT_EVERY
    st.shift_clock = p.shift_every
    set_uniform!(p.bg, :u_shift, Float32(st.field_time))
    st.message = ""
    st.message_age = 99.0
    return nothing
end

RayEngine.load_scene!(eng::RayEngine.Engine{GameParams,GameState}, ::Val{:game}) =
    build_level!(eng)

### STAGES

stage_input()   = (hotkeys,)
stage_fixed()   = (player_thrust, field_timer, field_physics, goal_capture)
stage_update()  = (goal_timer, ripples_update)
# The player is drawn in the overlay, after the HUD: the field loves to pin you to a
# corner, and you should never lose your light behind a score panel.
stage_render()  = (draw_background, draw_field_arrows, draw_ripples, draw_goal)
stage_overlay() = (draw_hud, draw_player)

### RUN

"""
    run!(; headless=false, frames=120)

Build the engine and open the window. `headless=true` only advances the
simulation: no Raylib calls, so it works in CI and from the REPL.
"""
function run!(; headless::Bool = false, frames::Int = 120)
    p = GameParams()
    s = GameState()
    eng = RayEngine.Engine(
        p, s;
        config = RayEngine.EngineConfig(
            title = "WeirdForce: Chromatic Drift",
            width = 1280,
            height = 720,
            fixed_dt = 1 / 60,
            background = Raylib.BLACK,
        ),
        input = stage_input,
        fixed_update = stage_fixed,
        update = stage_update,
        render = stage_render,
        overlay = stage_overlay,
    )
    eng.state.scene[] = :game
    reset_scene!(eng)

    if headless
        for _ in 1:frames
            simulate!(eng, 1 / 60)
        end
        return eng
    end

    RayEngine.start!(eng)
    return eng
end
