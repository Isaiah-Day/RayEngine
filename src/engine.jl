Base.@kwdef struct EngineConfig
    title::String = "Game"
    width::Int = 1280
    height::Int = 720
    fixed_dt::Float64 = 1/60
    max_fixed_steps::Int = 5             # catch-up cap per frame
    max_frame_dt::Float64 = 0.25         # clamp for long stalls (breakpoints, REPL pauses)
    fps::Int = 60 # 0=unlimited
end

mutable struct Clock                     # changes every frame
    accumulator::Float64
    elapsed::Float64
    frame::Int
    frame_ms::Float64                    # smoothed, for the overlay
end
Clock() = Clock(0.0, 0.0, 0, 16.0)

mutable struct DevState                  # only the REPL and tooling touch this
    listeners::Dict{Symbol,Observables.ObserverFunction}
    last_error::Observable{Union{Nothing,CapturedException}}
    pending_steps::Int
    pending_scene::Union{Nothing,Symbol}
    task::Union{Task,Nothing}
    scratch::Dict{Symbol,Any}
end
DevState() = DevState(
    Dict{Symbol,Observables.ObserverFunction}(),
    Observable{Union{Nothing,CapturedException}}(nothing),
    0,
    nothing,
    nothing,
    Dict{Symbol,Any}(),
)



"""
`P` and `S` are the game's Params and GameState types.
"""
struct Engine{P,S}
    config::EngineConfig
    world::World
    commands::CommandBuffer
    schedule::Schedule
    input::InputState
    resources::Resources
    params::P
    state::S
    bus::Bus
    clock::Clock
    dev::DevState
end

Engine(params::P, state::S; config::EngineConfig = EngineConfig()) where {P,S} =
    Engine{P,S}(
        config,
        World(),
        CommandBuffer(),
        Schedule(),
        InputState(),
        Resources(),
        params,
        state,
        Bus(),
        Clock(),
        DevState(),
    )


function Base.show(io::IO, eng::Engine)
    print(
        io,
        "Engine(",
        eng.state.status[],
        ", frame=",
        eng.clock.frame,
        ", entities=",
        eng.world.n_alive,
        ")",
    )
end

# Per-frame context

struct Ctx{P,S}
    dt::Float64
    alpha::Float64          # accumulator/fixed_dt, for render interpolation
    time::Float64
    frame::Int
    params::P
    state::S
    bus::Bus
    input::InputState
    commands::CommandBuffer
    resources::Resources
    dev::DevState
end

function Ctx(eng::Engine{P,S}, dt::Float64) where {P,S}
    clk, cfg = eng.clock, eng.config
    alpha =
        eng.state.status[] === :paused ? 1.0 :
        clamp(clk.accumulator / cfg.fixed_dt, 0.0, 1.0)
    return Ctx{P,S}(
        dt,
        alpha,
        clk.elapsed,
        clk.frame,
        eng.params,
        eng.state,
        eng.bus,
        eng.input,
        eng.commands,
        eng.resources,
        eng.dev,
    )
end

resource(ctx::Ctx, ::Type{T}) where {T} = resource(ctx.resources, T)

install!(eng::Engine, reg::SystemRegistry) = (install!(eng.schedule, reg); eng)





function record_error!(eng::Engine, name::Symbol, err, bt)
    eng.dev.last_error[] = CapturedException(err, bt)
    @error "system `$name` failed and was disabled; fix it, then enable!(eng, :$name)" exception =
        (err, bt)
    return nothing
end







# Running stages

function run_stage!(eng::Engine, stage::Symbol, dt::Float64)
    ctx = Ctx(eng, dt)
    for s in eng.schedule.stages[stage]
        s.enabled || continue
        if s.run_if !== nothing && !s.run_if(ctx)
            continue
        end
        t0 = time_ns()
        try
            s.f(eng.world, ctx)
        catch err
            s.enabled = false
            record_error!(eng, s.name, err, catch_backtrace())
        end
        s.last_ns = time_ns() - t0
    end
    return nothing
end

function run_fixed_step!(eng::Engine)
    run_stage!(eng, :fixed_update, eng.config.fixed_dt)
    apply!(eng.commands, eng.world)
    fill!(eng.input.fixed_pressed, false)    # edges are consumed by exactly one fixed step
    return nothing
end

function apply_pending_scene!(eng::Engine)
    s = eng.dev.pending_scene
    s === nothing && return nothing
    eng.dev.pending_scene = nothing
    eng.state.scene[] = s
    reset_scene!(eng)
    return nothing
end

"""
Advance the simulation by one rendered frame's worth of time. No Raylib calls, so it
works headless (tests, replays). Input must already be polled (or faked).
"""
function simulate!(eng::Engine, dt::Float64)
    cfg, clk, dev = eng.config, eng.clock, eng.dev
    dt = min(dt, cfg.max_frame_dt)
    apply_pending_scene!(eng)
    paused = eng.state.status[] === :paused
    stepping = paused && dev.pending_steps > 0

    run_stage!(eng, :input, dt)              # always runs, so hotkeys can unpause

    if stepping
        run_fixed_step!(eng)                 # exactly one fixed step per stepped frame
        dev.pending_steps -= 1
    elseif !paused
        clk.accumulator += dt
        n = 0
        while clk.accumulator >= cfg.fixed_dt && n < cfg.max_fixed_steps
            run_fixed_step!(eng)
            clk.accumulator -= cfg.fixed_dt
            n += 1
        end
        # Hit the cap with work left over: drop the backlog instead of living in catch-up.
        n == cfg.max_fixed_steps &&
            clk.accumulator >= cfg.fixed_dt &&
            (clk.accumulator = 0.0)
    end

    if !paused || stepping
        udt = stepping ? cfg.fixed_dt : dt
        run_stage!(eng, :update, udt)
        run_stage!(eng, :late_update, udt)
        apply!(eng.commands, eng.world)
        clk.elapsed += udt
    end

    clk.frame_ms = 0.9 * clk.frame_ms + 0.1 * dt * 1000
    clk.frame += 1
    return nothing
end

function render!(eng::Engine, dt::Float64)
    run_stage!(eng, :render, dt)
    run_stage!(eng, :overlay, dt)
    if debug_enabled(eng.params)
        try
            draw_overlay!(eng)
        catch err
            eng.params.show_debug[] = false      # don't spam the same failure every frame
            record_error!(eng, :overlay, err, catch_backtrace())
        end
    end
    return nothing
end

debug_enabled(p) = hasproperty(p, :show_debug) && p.show_debug[]








# Scenes

"Define `MyEngine.load_scene!(eng, ::Val{:name})` in your game to add a scene."
load_scene!(eng, ::Val{S}) where {S} =
    error("no scene :$S; define load_scene!(eng, ::Val{:$S})")

"Clear the world and rerun the scene loader. Params, resources and listeners are kept."
function reset_scene!(eng::Engine)
    clear!(eng.world)
    empty!(eng.commands.queue)
    empty!(eng.commands.draining)
    eng.clock.accumulator = 0.0
    sc = eng.state.scene[]
    sc === :none || Base.invokelatest(load_scene!, eng, Val(sc))
    return eng
end

"Safe from inside a system: the switch happens at the start of the next frame."
goto_scene!(dev::DevState, scene::Symbol) = (dev.pending_scene = scene; nothing)
goto_scene!(eng::Engine, scene::Symbol) = goto_scene!(eng.dev, scene)
