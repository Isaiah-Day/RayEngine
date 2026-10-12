### INPUT

"Read input during the fixed step: horizontal move + jump on an edge (fixed latch)."
function player_input(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p      = eng.params
    joy    = axis(eng.input, Raylib.KEY_LEFT, Raylib.KEY_RIGHT)
    joy   += axis(eng.input, Raylib.KEY_A, Raylib.KEY_D)      # WASD alias
    joy     = clamp(joy, -1, 1)
    jumping = key_pressed_fixed(eng.input, Raylib.KEY_SPACE) ||
              key_pressed_fixed(eng.input, Raylib.KEY_W)

    each(eng.world, PlayerBody) do e, pb
        pb.vel[1] = joy * p.move_speed
        pb.facing = joy == 0 ? pb.facing : sign(joy)
        if jumping && pb.on_ground
            pb.vel[2] = -p.jump_velocity
            pb.on_ground = false
            eng.state.jumps[] = eng.state.jumps[] + 1
        end
    end
    return nothing
end


### PHYSICS
"Gravity + integrate position, then resolve collisions axis-by-axis against platforms."
function physics(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p = eng.params
    pb_g = nothing
    each(eng.world, PlayerBody) do e, pb
        pb_g = pb
        pb.vel[2] += p.gravity * dt
        pb.on_ground = false

        # horizontal, then vertical: keeps corners from snagging
        pb.pos[1] += pb.vel[1] * dt
        resolve_axis!(eng, pb, 1)
        pb.pos[2] += pb.vel[2] * dt
        resolve_axis!(eng, pb, 2)
    end


    each(eng.world, Platform) do _, pl
        if !pl.solid
            if overlaps(pb_g, pl)
                spawn!(eng, Writing("YOU WIN!", [250.0, 250.0], 40))
                spawn!(eng, Writing("Sorry this was so small.\nMaking a game engine is very hard.", [250.0, 300.0], 20))
            end
        end
    end
    return nothing
end

function resolve_axis!(eng, pb::PlayerBody, axis_i::Int)
    each(eng.world, Platform) do _, pl
        if pl.solid && overlaps(pb, pl)
            if axis_i == 1
                if pb.vel[1] > 0
                    pb.pos[1] = pl.pos[1] - pb.size[1]
                elseif pb.vel[1] < 0
                    pb.pos[1] = pl.pos[1] + pl.size[1]
                end
                pb.vel[1] = 0
            else
                if pb.vel[2] >= 0            # moving down: land on top
                    pb.pos[2] = pl.pos[2] - pb.size[2]
                    pb.on_ground = true
                else
                    pb.pos[2] = pl.pos[2] + pl.size[2]
                end
                pb.vel[2] = 0
            end
        end
    end
    return nothing
end

overlaps(pb::PlayerBody, pl::Platform) =
    pb.pos[1] < pl.pos[1] + pl.size[1] && pb.pos[1] + pb.size[1] > pl.pos[1] &&
    pb.pos[2] < pl.pos[2] + pl.size[2] && pb.pos[2] + pb.size[2] > pl.pos[2]

"Fell off the bottom: respawn at the spawn point and count a death."
function respawn(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p = eng.params
    each(eng.world, PlayerBody) do e, pb
        if pb.pos[2] > p.height + 80
            pb.pos .= p.spawn
            pb.vel .= 0.0
            pb.on_ground = false
            eng.state.deaths[] = eng.state.deaths[] + 1
        end
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
    ground_c = p.colors[:ground]
    plat_c   = p.colors[:platform]

    each(eng.world, Platform) do _, pl
        c = pl.solid ? ground_c : plat_c
        r = Rect(Int.(round.(pl.pos)), Int.(round.(pl.pos .+ pl.size)))
        r.style = Style(color = c)
        draw(r)
    end

    each(eng.world, PlayerBody) do _, pb
        r = Rect(Int.(round.(pb.pos)), Int.(round.(pb.pos .+ pb.size)))
        r.style = Style(color = p.colors[:player],
                        stroke = colorant"#f1faee",
                        strokewidth = 3)
        draw(r)
    end

    each(eng.world, Writing) do _, t
        r = RayEngine.Text(t.text, Int.(round.(t.pos)), t.size)
        draw(r)
    end
    return nothing
end