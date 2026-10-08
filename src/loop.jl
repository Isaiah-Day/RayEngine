# Windowed frame + the async loop that keeps the REPL alive.

"One windowed frame: poll input, simulate, draw. `render!` runs between Begin/EndDrawing."
function frame!(eng::Engine, dt::Float64)
    poll_input!(eng.input)
    simulate!(eng, dt)
    Raylib.BeginDrawing()
    try
        render!(eng, dt)             # a :render system should clear the background first
    finally
        Raylib.EndDrawing()          # never leave a drawing frame open
    end
    return nothing
end

function run_loop(eng::Engine)
    cfg = eng.config
    Raylib.InitWindow(cfg.width, cfg.height, cfg.title)
    try
        # Frame limiting happens here with `sleep`, not Raylib's SetTargetFPS: Raylib's limiter
        # blocks the whole Julia thread inside EndDrawing, which starves the REPL.
        frame_ns = cfg.fps > 0 ? round(Int, 1e9 / cfg.fps) : 0
        last = time_ns()
        while !Raylib.WindowShouldClose() && eng.state.status[] !== :stopped
            t0 = time_ns()
            dt = (t0 - last) / 1e9
            last = t0
            try
                # invokelatest: the loop is stuck in the world age it started in; this makes
                # every frame see methods that Revise redefined since.
                Base.invokelatest(frame!, eng, dt)
            catch err
                # System errors are caught in run_stage!; reaching here is an engine bug.
                eng.dev.last_error[] = CapturedException(err, catch_backtrace())
                @error "frame failed; pausing" exception = (err, catch_backtrace())
                eng.state.status[] = :paused
            end
            sleep(max(0.001, (frame_ns - (time_ns() - t0)) / 1e9))   # always yields to the REPL
        end
    finally
        Raylib.CloseWindow()
        eng.state.status[] = :stopped
        eng.dev.task = nothing
    end
end

"Open the window and start looping. Returns immediately; the REPL stays live."
function start!(eng::Engine)
    t = eng.dev.task
    (t !== nothing && !istaskdone(t)) &&
        error("engine already running; call stop!(eng) first")
    eng.state.status[] = :running
    eng.dev.task = @async run_loop(eng)    # @async keeps the loop on the thread that owns the GL context
    return eng
end

function stop!(eng::Engine; listeners::Bool = true)
    eng.state.status[] = :stopped
    t = eng.dev.task
    if t !== nothing
        try
            wait(t)
        catch err
            @warn "loop task ended with an error" exception = err
        end
    end
    listeners && unlisten_all!(eng)
    return eng
end
