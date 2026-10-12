# Debug overlay: frame time, entity counts, system list (with disabled flag), last error.
# Toggle with params.show_debug[] = true.


function overlay_lines(eng::Engine)
    clk, w = eng.clock, eng.world
    lines = String[]
    fps = round(Int, 1000 / max(clk.frame_ms, 1e-3))
    push!(
        lines,
        "frame $(clk.frame) | $(round(clk.frame_ms; digits=1)) ms ($(fps) fps) | $(eng.state.status[])",
    )
    counts = join(("$(nameof(T))=$(length(s))" for (T, s) in w.storages), " ")
    push!(lines, "entities: $(w.n_alive) | $counts")
    for (st, fs) in stage_systems(eng), f in fs
        push!(
            lines,
            "  " *
            rpad(string(st), 13) *
            rpad(string(nameof(f)), 22) *
            (f in eng.disabled ? "[DISABLED]" : ""),
        )
    end
    ce = eng.dev.last_error[]
    if ce !== nothing
        msg = first(split(sprint(showerror, ce.ex), '\n'))
        push!(lines, "last error: " * first(msg, 90))
    end
    return lines
end

function draw_overlay!(eng::Engine)
    lines = overlay_lines(eng)
    h = 16 * length(lines) + 10
    Raylib.DrawRectangle(5, 5, 640, h, RGB(0, 0, 170/255))
    for (i, l) in enumerate(lines)
        Raylib.DrawText(l, 10, 10 + 16 * (i - 1), 14, Raylib.RAYWHITE)
    end
    return nothing
end
