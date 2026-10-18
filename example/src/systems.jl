### INPUT

"Read input during the fixed step: horizontal move + jump on an edge (fixed latch)."
function player_input(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p      = eng.params
    joy    = axis(eng.input, Raylib.KEY_LEFT, Raylib.KEY_RIGHT)
    joy   += axis(eng.input, Raylib.KEY_A, Raylib.KEY_D)      # WASD alias
    joy     = clamp(joy, -1, 1)

    each(eng.world, PlayerBody) do e, pb
        pb.vel[1] = joy * p.move_speed
        pb.facing = joy == 0 ? pb.facing : sign(joy)
    end
    return nothing
end


### PHYSICS
"Gravity + integrate position, then resolve collisions axis-by-axis against platforms."
function physics(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p = eng.params
    c = eng.config
    each(eng.world, PlayerBody) do e, pb
        # horizontal, then vertical: keeps corners from snagging
        pb.pos[1] += pb.vel[1] * dt
        pb.pos[2] += pb.vel[2] * dt
    end
    return nothing
end


"Clamp the player inside the world so they can't walk off-screen sideways."
function keep_in_view(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p = eng.params
    each(eng.world, PlayerBody) do e, pb
        if pb.pos[1] < 0
            pb.pos[1] = 0.0
            pb.vel[1] = 0.0
        elseif pb.pos[1] > p.width - pb.size[1]
            pb.pos[1] = p.width - pb.size[1]
            pb.vel[1] = 0.0
        end
    end
end

### RENDER

function clear(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    Raylib.ClearBackground(Raylib.RAYWHITE)
    return nothing
end

"Draw all platforms and the player as Rect shapes."
function draw_scene(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p = eng.params
    c = eng.config

    each(eng.world, Background) do _, bg
        r = Rect([0,0], [eng.config.width, eng.config.height], bg.shader)
        draw(r)
    end

    each(eng.world, PlayerBody) do _, pb
        r = Rect(Int.(round.(pb.pos)), Int.(round.(pb.pos .+ pb.size)))
        r.style = Style(color = RGB(1,1,1), strokewidth = 3)
        draw(r)
    end


    return nothing
end