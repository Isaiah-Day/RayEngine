# Windowed loop. Raylib/GLFW on macOS **must** run window creation, the GL context and
# the event loop on the *main* thread — and the calling thread here *is* the main thread
# when you call `start!` from the REPL. So no `@async`: we loop synchronously and the
# REPL is busy until the window closes. That is the only form that works on macOS.

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

"Open the window and run frames on the calling (main) thread until the user closes it.
Returns after the window closes. The REPL is busy the whole time — that is required:
GLFW/GL context/event loop live on the main thread, so nothing else can run while the
window is up (macOS; also true on Linux if the REPL acts as the main thread)."
function start!(eng::Engine)
    cfg   = eng.config
    p     = eng.params
    t     = eng.dev.task
    (t !== nothing && !istaskdone(t)) &&
        error("engine already running; call stop!(eng) first")

    Raylib.InitWindow(Int(cfg.width), Int(cfg.height), cfg.title)
    try
        eng.state.status[] = :running
        frame_ns = cfg.fps > 0 ? round(Int, 1e9 / cfg.fps) : 0
        last = time_ns()
        while !Raylib.WindowShouldClose() && eng.state.status[] !== :stopped
            t0 = time_ns()
            dt = clamp((t0 - last) / 1e9, 0.0, cfg.max_frame_dt)
            last = t0
            try
                # invokelatest: the loop is stuck in the world age it started in; this makes
                # every frame see methods that Revise redefined since.
                Base.invokelatest(frame!, eng, clamp(dt, 0.0, cfg.max_frame_dt))
            catch err
                # System errors are caught in run_stage!; reaching here is an engine bug.
                eng.dev.last_error[] = CapturedException(err, catch_backtrace())
                @error "frame failed; pausing" exception = (err, catch_backtrace())
                eng.state.status[] = :paused
            end
            # Frame limiting with `sleep`, not Raylib's SetTargetFPS: Raylib's limiter
            # blocks the whole Julia thread inside EndDrawing, which starves the REPL.
            pause = max(0.001, (frame_ns > 0 ? frame_ns - (time_ns() - t0) : 0) / 1e9)
            sleep(pause)
        end
    finally
        Raylib.CloseWindow()
        eng.state.status[] = :stopped
        eng.dev.task = nothing
    end
    return eng
end

"Send a stop request. Without a window on macOS the loop is not running, so this just
records the request; call it only while the REPL is busy with a running window"
stop!(eng::Engine; listeners::Bool = true) = begin
    eng.state.status[] = :stopped        # the running `while` sees this and exits at the next frame
    listeners && unlisten_all!(eng)
    return eng
end
