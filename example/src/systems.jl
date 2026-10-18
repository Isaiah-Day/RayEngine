### helpers

"Field snapshot shared by the shader and the physics."
field_time_now(eng::RayEngine.Engine) = eng.state.field_time

player(eng::RayEngine.Engine) =
    eng.state.player === nothing ? nothing :
    get_component(eng.world, eng.state.player, PlayerBody)

"""
    shift_field!(eng)

Jump the whole colour field to a new snapshot. Both the shader's `u_shift`
uniform and `sample_field` read `state.field_time`, so the picture and the
physics move together.
"""
function shift_field!(eng::RayEngine.Engine)
    p, st = eng.params, eng.state
    st.shifts += 1
    # Golden-ratio steps give varied, deterministic jumps without an RNG.
    st.field_time += p.shift_min + p.shift_span * mod(st.shifts * 0.6180339887498949, 1.0)
    set_uniform!(p.bg, :u_shift, Float32(st.field_time))   # keep the shader data in sync
    st.shift_clock = p.shift_every
    return nothing
end

the_goal(eng::RayEngine.Engine) =
    eng.state.goal === nothing ? nothing :
    get_component(eng.world, eng.state.goal, Goal)

"Raylib wants N0f8 colours; the game stores Colors.jl colours."
const _N0f8 = typeof(Raylib.WHITE.r)
_rgba(c, a::Real = 1.0) = Raylib.Fade(convert(RGBA{_N0f8}, c), Float32(a))
_white(a::Real = 1.0) = Raylib.Fade(Raylib.WHITE, Float32(a))

# ───────────── input ─────────────

"Hotkeys live in the input stage, so they keep working while paused."
function hotkeys(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p, inp = eng.params, eng.input
    if key_pressed(inp, Raylib.KEY_F)
        p.show_debug[] = !p.show_debug[]
    end
    if key_pressed(inp, Raylib.KEY_G)
        p.show_field[] = !p.show_field[]
    end
    if key_pressed(inp, Raylib.KEY_P)
        s = eng.state
        s.status[] = s.status[] === :paused ? :running : :paused
    end
    if key_pressed(inp, Raylib.KEY_R)
        reset_scene!(eng)
    end
    return nothing
end

# ───────────── fixed step ─────────────

"Every `shift_every` seconds the whole field jumps to a new snapshot."
function field_timer(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    st = eng.state
    st.shift_clock -= dt
    if st.shift_clock <= 0.0
        shift_field!(eng)
    end
    return nothing
end

"WASD / arrows: a manual nudge on both axes. Deliberately weaker than the field."
function player_thrust(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    inp, p = eng.input, eng.params
    mx = clamp(
        Float64(axis(inp, Raylib.KEY_LEFT, Raylib.KEY_RIGHT)) +
        Float64(axis(inp, Raylib.KEY_A, Raylib.KEY_D)),
        -1.0, 1.0,
    )
    my = clamp(
        Float64(axis(inp, Raylib.KEY_UP, Raylib.KEY_DOWN)) +
        Float64(axis(inp, Raylib.KEY_W, Raylib.KEY_S)),
        -1.0, 1.0,
    )

    # Don't let diagonals be stronger than a cardinal thrust.
    mag = hypot(mx, my)
    if mag > 1.0
        mx /= mag
        my /= mag
    end

    pb = player(eng)
    pb === nothing && return nothing
    pb.vel[1] += mx * p.thrust * dt
    pb.vel[2] += my * p.thrust * dt
    return nothing
end

"""
The whole trick: sample the shader colour under the player and use it as
acceleration, then integrate through a thick fluid.
"""
function field_physics(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p, cfg = eng.params, eng.config
    W, H = Float64(cfg.width), Float64(cfg.height)
    t = field_time_now(eng)

    pb = player(eng)
    pb === nothing && return nothing

    cx, cy = pb.pos
    rgb = sample_field(cx, cy, t; ux = W, uy = H, zoom = p.field_zoom)
    ax, ay = field_force(rgb, p.field_gain)
    pb.rgb = rgb
    pb.force = (ax, ay)

    pb.vel[1] += ax * dt
    pb.vel[2] += ay * dt

    damp = exp(-p.drag * dt)
    pb.vel[1] *= damp
    pb.vel[2] *= damp

    sp = hypot(pb.vel[1], pb.vel[2])
    if sp > p.max_speed
        k = p.max_speed / sp
        pb.vel[1] *= k
        pb.vel[2] *= k
    end

    pb.pos[1] += pb.vel[1] * dt
    pb.pos[2] += pb.vel[2] * dt

    # walls: soft bounce, so the field can pin you to an edge but not through it
    r = pb.radius
    if pb.pos[1] < r
        pb.pos[1] = r
        pb.vel[1] = abs(pb.vel[1]) * p.bounce
    elseif pb.pos[1] > W - r
        pb.pos[1] = W - r
        pb.vel[1] = -abs(pb.vel[1]) * p.bounce
    end
    if pb.pos[2] < r
        pb.pos[2] = r
        pb.vel[2] = abs(pb.vel[2]) * p.bounce
    elseif pb.pos[2] > H - r
        pb.pos[2] = H - r
        pb.vel[2] = -abs(pb.vel[2]) * p.bounce
    end

    push!(pb.trail, [pb.pos[1], pb.pos[2]])
    while length(pb.trail) > p.trail_len
        popfirst!(pb.trail)
    end
    return nothing
end

"Reach the beacon: advance the tour, leave a ripple."
function goal_capture(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    pb, g = player(eng), the_goal(eng)
    (pb === nothing || g === nothing) && return nothing

    dx, dy = pb.pos[1] - g.pos[1], pb.pos[2] - g.pos[2]
    if dx * dx + dy * dy <= (pb.radius + g.radius)^2
        p, st = eng.params, eng.state
        n = length(p.goals)
        beacon = g.index
        st.captured[] += 1
        spawn!(eng.commands, eng.world, Ripple(copy(g.pos), 0.0, 1.1, pb.rgb))
        advance_goal!(eng)

        if st.captured[] % n == 0
            # One tour down: the field jumps more often now.
            p.shift_every = max(FIELD_SHIFT_FLOOR, p.shift_every * 0.85)
            shift_field!(eng)
            st.message = "TOUR COMPLETE - THE FIELD QUICKENS"
        else
            st.message = "BEACON $beacon / $n"
        end
        st.message_age = 0.0
    end
    return nothing
end

function advance_goal!(eng::RayEngine.Engine{GameParams,GameState})
    p, st = eng.params, eng.state
    g = the_goal(eng)
    g === nothing && return nothing
    g.index = mod1(g.index + 1, length(p.goals))
    g.pos = copy(p.goals[g.index])
    st.goal_clock = p.goal_time
    return nothing
end

# ───────────── update ─────────────

"Run clock, beacon deadline and the toast timer."
function goal_timer(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    st = eng.state
    st.message_age += dt
    the_goal(eng) === nothing && return nothing
    st.goal_clock -= dt
    if st.goal_clock <= 0.0
        advance_goal!(eng)
        shift_field!(eng)          # the beacon moved, and so did the field
    end
    return nothing
end

"Ripples expand and die. Expiry is queued; `each` never mutates the world."
function ripples_update(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    dead = Entity[]
    each(eng.world, Ripple) do e, rp
        rp.age += dt
        rp.age >= rp.life && push!(dead, e)
    end
    for e in dead
        despawn!(eng.commands, e)
    end
    return nothing
end

# ───────────── render ─────────────

function draw_background(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p, cfg = eng.params, eng.config
    # Drive the shader from the same held snapshot and zoom the physics samples.
    set_uniform!(p.bg, :u_shift, Float32(field_time_now(eng)))
    set_uniform!(p.bg, :u_zoom, Float32(p.field_zoom))
    draw(Rect([0, 0], [cfg.width, cfg.height], Style(; shader = p.bg)))
    return nothing
end

"White arrow from `(x, y)` along the unit vector `(dx, dy)`."
function draw_arrow!(x, y, dx, dy, len, width, alpha)
    tx, ty = x + dx * len, y + dy * len
    bx, by = tx - dx * 6.0, ty - dy * 6.0
    lx, ly = -dy * 4.5, dx * 4.5

    shaft = Line(round(Int, x), round(Int, y), round(Int, bx), round(Int, by), width)
    shaft.style = Style(; color = RGB(1, 1, 1), alpha = alpha)
    draw(shaft)

    head = Triangle(round(Int, tx), round(Int, ty),
                    round(Int, bx + lx), round(Int, by + ly),
                    round(Int, bx - lx), round(Int, by - ly))
    head.style = Style(; color = RGB(1, 1, 1), alpha = min(1.0, alpha + 0.2))
    draw(head)
    return nothing
end

"Little arrows everywhere: the field made legible. G toggles."
function draw_field_arrows(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p = eng.params
    p.show_field[] || return nothing
    cfg = eng.config
    W, H = Float64(cfg.width), Float64(cfg.height)
    t = field_time_now(eng)
    step = p.field_step

    y = step * 0.55
    while y < H - 18
        x = step * 0.62
        while x < W - 18
            rgb = sample_field(x, y, t; ux = W, uy = H, zoom = p.field_zoom)
            ax, ay = field_force(rgb, 1.0)
            m = hypot(ax, ay)
            if m > 0.07
                draw_arrow!(x, y, ax / m, ay / m, 9.0 + 20.0 * min(m, 1.0), 2, 0.5)
            end
            x += step
        end
        y += step
    end
    return nothing
end

function draw_ripples(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    each(eng.world, Ripple) do _, rp
        k = clamp(rp.age / rp.life, 0.0, 1.0)
        rad = 24.0 + 150.0 * k
        draw(Circle(round.(Int, rp.pos), rad, Style(;
            color = RGB(rp.rgb...), alpha = 0.05 * (1.0 - k),
            stroke = RGB(1, 1, 1), strokewidth = 2,
        )))
    end
    return nothing
end

function draw_goal(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p, st = eng.params, eng.state
    g = the_goal(eng)
    g === nothing && return nothing

    ix, iy = round(Int, g.pos[1]), round(Int, g.pos[2])
    pulse = Float32(1.0 + 0.07 * sin(eng.clock.elapsed * 3.0))
    R = Float32(g.radius)

    # Dark puck keeps the beacon readable on top of the bright white hole.
    Raylib.DrawCircle(ix, iy, R * 2.1f0, _rgba(colorant"black", 0.22))
    Raylib.DrawCircle(ix, iy, R * 1.7f0 * pulse, _rgba(p.colors[:goal], 0.12))
    Raylib.DrawCircleLines(ix, iy, R * pulse, _rgba(p.colors[:goal], 0.95))
    Raylib.DrawCircle(ix, iy, 4.0f0, _white(0.9))

    # Deadline arc: drains clockwise, turns red when it is nearly gone.
    frac = clamp(st.goal_clock / p.goal_time, 0.0, 1.0)
    col = frac > 0.3 ? _rgba(p.colors[:goal], 0.95) : _rgba(p.colors[:hot], 0.95)
    n = 36
    ar = R + 12.0f0
    for k in 0:(n-1)
        k / n < frac || break
        a0 = -pi / 2 + 2pi * k / n
        a1 = -pi / 2 + 2pi * (k + 1) / n
        Raylib.DrawLineEx(
            Raylib.RayVector2(ix + ar * cos(a0), iy + ar * sin(a0)),
            Raylib.RayVector2(ix + ar * cos(a1), iy + ar * sin(a1)),
            3.0f0, col,
        )
    end
    return nothing
end

function draw_player(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    pb = player(eng)
    pb === nothing && return nothing

    cx, cy = pb.pos
    c = round.(Int, pb.pos)
    rgb = RGB(pb.rgb...)

    if length(pb.trail) >= 2
        spline = LinearSpline([round.(Int, q) for q in pb.trail], 3.0)
        spline.style = Style(; color = rgb, alpha = 0.30)
        draw(spline)
    end

    # Aura = the colour being felt right now.
    draw(Circle(c, pb.radius * 3.0, Style(; color = rgb, alpha = 0.35)))
    # Black ring so the light stays readable on the white parts of the field.
    draw(Circle(c, pb.radius + 3.0, Style(; color = RGB(0, 0, 0), alpha = 0.9)))
    draw(Circle(c, pb.radius, Style(; color = RGB(1, 1, 1), stroke = rgb, strokewidth = 2)))

    # Force vector coming out of the player.
    ax, ay = pb.force
    m = hypot(ax, ay)
    if m > 55.0
        dx, dy = ax / m, ay / m
        len = clamp(0.045 * m, 14.0, 64.0)
        draw_arrow!(cx + dx * pb.radius, cy + dy * pb.radius, dx, dy,
                    len - pb.radius, 3, 0.85)
    end
    return nothing
end

# ───────────── overlay ─────────────

"Beacon deadline bar and pause state."
function draw_hud(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p, st, cfg = eng.params, eng.state, eng.config
    W, H = cfg.width, cfg.height

    frac = clamp(st.goal_clock / p.goal_time, 0.0, 1.0)
    bw, bx, by = 260, (W - 260) ÷ 2, 24
    Raylib.DrawRectangle(bx, by, bw, 6, _rgba(colorant"black", 0.35))
    bar = frac > 0.3 ? p.colors[:goal] : p.colors[:hot]
    Raylib.DrawRectangle(bx, by, round(Int, bw * frac), 6, _rgba(bar, 0.95))

    if st.message_age < 2.2
        a = clamp(1.0 - (st.message_age - 1.3) / 0.9, 0.0, 1.0)
        tw = Raylib.MeasureText(st.message, 32)
        mx = (W - tw) ÷ 2
        Raylib.DrawText(st.message, mx + 2, 120, 32, _rgba(colorant"black", 0.45 * a))
        Raylib.DrawText(st.message, mx, 118, 32, _white(a))
    end

    if st.status[] === :paused
        tx = (W - Raylib.MeasureText("PAUSED", 26)) ÷ 2
        Raylib.DrawText("PAUSED", tx + 2, H ÷ 2 - 38, 26, _rgba(colorant"black", 0.45))
        Raylib.DrawText("PAUSED", tx, H ÷ 2 - 40, 26, _white(0.9))
    end
    return nothing
end
