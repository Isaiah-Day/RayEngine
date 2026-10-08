# Systems are named functions (w::World, ctx). Within a stage they run in definition order.
# A system that throws is disabled and its error stored; fix it, save, then enable!(eng, :name).

# ───────────── :input (always runs, even paused) ─────────────

@system :input function hotkeys!(w::World, ctx)
    inp = ctx.input
    st = ctx.state.status
    key_pressed(inp, Raylib.KEY_P) && (st[] = st[] === :paused ? :running : :paused)
    key_pressed(inp, Raylib.KEY_N) && st[] === :paused && (ctx.dev.pending_steps += 1)
    key_pressed(inp, Raylib.KEY_R) && goto_scene!(ctx.dev, ctx.state.scene[])
    key_pressed(inp, Raylib.KEY_F1) && (ctx.params.show_debug[] = !ctx.params.show_debug[])
    return nothing
end

# ───────────── :fixed_update (deterministic 60 Hz) ─────────────
# Edge-triggered input uses the *_fixed variants; level-triggered input works anywhere.

@system :fixed_update function player_control!(w::World, ctx)
    speed = ctx.params.player_speed[]
    jump = ctx.params.jump_speed[]
    arena = resource(ctx, Arena)
    floor_y = arena.h - 40
    dx = axis(ctx.input, Raylib.KEY_LEFT, Raylib.KEY_RIGHT)
    jumped = key_pressed_fixed(ctx.input, Raylib.KEY_SPACE)
    each(w, Position, Velocity, Player) do e, p, v, _
        v.x = dx * speed
        jumped && p.y >= floor_y - 24 - 1 && (v.y = -jump)
    end
end

@system :fixed_update function spawn_balls!(w::World, ctx)
    key_pressed_fixed(ctx.input, Raylib.KEY_B) || return
    rng = resource(ctx, Xoshiro)
    arena = resource(ctx, Arena)
    spawn!(
        ctx.commands,
        w,
        Position(arena.w * rand(rng, Float32), 60),
        Velocity(200 * (rand(rng, Float32) - 0.5f0), 0),
        Circle(
            10 + 14 * rand(rng, Float32),
            rand(rng, UInt8),
            rand(rng, UInt8),
            rand(rng, UInt8),
        ),
    )
end

@system :fixed_update function gravity!(w::World, ctx)
    g = ctx.params.gravity[] * Float32(ctx.dt)
    each(w, Velocity, Circle) do e, v, _
        v.y += g
    end
end

@system :fixed_update function integrate!(w::World, ctx)
    dt = Float32(ctx.dt)
    each(w, Position, Velocity) do e, p, v
        p.px, p.py = p.x, p.y
        p.x += v.x * dt
        p.y += v.y * dt
    end
end

@system :fixed_update function collide!(w::World, ctx)
    arena = resource(ctx, Arena)
    floor_y = arena.h - 40
    rest = ctx.params.restitution[]
    each(w, Position, Velocity, Circle) do e, p, v, c
        if p.y + c.radius > floor_y
            p.y = floor_y - c.radius
            if abs(v.y) > 60
                v.y = -v.y * rest
                emit!(ctx.bus, Bounce(e))
            else
                v.y = 0
            end
        end
        if p.x < c.radius
            p.x = c.radius
            v.x = abs(v.x)
        elseif p.x > arena.w - c.radius
            p.x = arena.w - c.radius
            v.x = -abs(v.x)
        end
    end
end

# ───────────── :render ─────────────

@system :render function draw_world!(w::World, ctx)
    arena = resource(ctx, Arena)
    Raylib.ClearBackground(Raylib.RAYWHITE)
    Raylib.DrawRectangle(
        0,
        Int32(round(arena.h - 40)),
        Int32(round(arena.w)),
        40,
        Raylib.DARKGRAY,
    )
    a = Float32(ctx.alpha)
    each(w, Position, Circle) do e, p, c
        x = p.px + (p.x - p.px) * a          # interpolate between fixed steps
        y = p.py + (p.y - p.py) * a
        Raylib.DrawCircle(
            Int32(round(x)),
            Int32(round(y)),
            c.radius,
            Raylib.Color(c.r, c.g, c.b, 255),
        )
    end
end

@system :overlay function draw_hud!(w::World, ctx)
    Raylib.DrawText(
        "score $(ctx.state.score[])   [arrows] move  [space] jump  [b] ball  " *
        "[p] pause  [n] step  [r] reset  [F1] debug",
        10,
        Int32(round(resource(ctx, Arena).h)) - 28,
        18,
        Raylib.WHITE,
    )
end
