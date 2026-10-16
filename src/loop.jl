"One windowed frame: poll input, simulate, draw."
function frame!(eng::Engine, dt::Float64)
    poll_input!(eng.input)
    simulate!(eng, dt)
    Raylib.BeginDrawing()
    try
        # Always clear: the GL back buffer is undefined after a swap, so without this
        # an engine with no :render systems flickers between garbage buffers.
        Raylib.ClearBackground(eng.config.background)
        render!(eng, dt)             # render systems may clear again with their own color
    finally
        Raylib.EndDrawing()          # never leave a drawing frame open
    end
    return nothing
end

"Open the window and run frames on the calling (main) thread until the user closes it.
Returns after the window closes."
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
                Base.invokelatest(frame!, eng, clamp(dt, 0.0, cfg.max_frame_dt))
            catch err
                eng.dev.last_error[] = CapturedException(err, catch_backtrace())
                @error "frame failed; stopping" exception = (err, catch_backtrace())
                eng.state.status[] = :stopped
                break
            end

            pause = max(0.001, (frame_ns > 0 ? frame_ns - (time_ns() - t0) : 0) / 1e9)
            # sleep(pause)
        end
    finally
        try
            unload_all_shaders!()   # GL objects must go before the context dies
        catch err
            @warn "failed to unload shaders" exception = (err, catch_backtrace())
        end
        Raylib.CloseWindow()
        eng.state.status[] = :stopped
        eng.dev.task = nothing
    end
    return eng
end

"Send a stop request."
stop!(eng::Engine; listeners::Bool = true) = begin
    eng.state.status[] = :stopped        # the running `while` sees this and exits at the next frame
    listeners && unlisten_all!(eng)
    return eng
end
