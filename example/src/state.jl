# Live-tunable values. Change from the REPL:  eng.params.gravity[] = 300f0
Base.@kwdef struct Params
    gravity::Observable{Float32} = Observable(1500.0f0)   # px/s²
    player_speed::Observable{Float32} = Observable(320.0f0)    # px/s
    jump_speed::Observable{Float32} = Observable(700.0f0)    # px/s
    restitution::Observable{Float32} = Observable(0.8f0)
    show_debug::Observable{Bool} = Observable(false)
end

# The engine requires `status` and `scene`; the rest is yours.
Base.@kwdef struct GameState
    status::Observable{Symbol} = Observable(:stopped)   # :running | :paused | :stopped
    scene::Observable{Symbol} = Observable(:none)
    score::Observable{Int} = Observable(0)
end

score_changed(s) = nothing          # edit me at the REPL: Revise picks it up

"Keyed listeners: re-running this replaces them instead of stacking."
function wire_listeners!(eng)
    listen!(eng, :score, channel(eng.bus, Bounce)) do b
        b === nothing && return
        eng.state.score[] += 1
        score_changed(eng.state.score[])
    end
    return eng
end
