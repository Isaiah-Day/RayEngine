# ───────────── Params & state ─────────────

Base.@kwdef mutable struct GameParams
    show_debug::Observable{Bool} = Observable(false)

    # world (y grows downward; engine renders top-left origin)
    width::Float64 = 1280
    height::Float64 = 720

    # player physics, tuned to fixed_dt = 1/60
    gravity::Float64 = 1500.0
    jump_velocity::Float64 = 560.0
    move_speed::Float64 = 280.0
    player_w::Float64 = 36.0
    player_h::Float64 = 52.0
    spawn::Vector{Float64} = [200.0, 500.0]

    colors = Dict{Symbol,Color}(
        :background => colorant"#2b2d42",
        :player    => colorant"#ef476f",
        :ground    => colorant"#457b9d",
        :platform  => colorant"#f4a261",
    )
end

Base.@kwdef mutable struct GameState
    status::Observable{Symbol} = Observable(:stopped)
    scene::Observable{Symbol}  = Observable(:none)
    jumps::Observable{Int}     = Observable(0)
    deaths::Observable{Int}    = Observable(0)
end

function debug_enabled(p::GameParams)
    get(p.show_debug)
end

# ───────────── Components ─────────────

mutable struct PlayerBody
    pos::Vector{Float64}     # top-left corner
    vel::Vector{Float64}
    size::Vector{Float64}
    on_ground::Bool
    facing::Float64
end

mutable struct Platform
    pos::Vector{Float64}     # top-left corner
    size::Vector{Float64}
    solid::Bool              # true = collide; false = pure decoration
end

# ───────────── Systems ─────────────

"Read input during the fixed step: horizontal move + jump on an edge (fixed latch)."
function player_input(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p      = eng.params
    joy    = axis(eng.input, Raylib.KEY_LEFT, Raylib.KEY_RIGHT)  # -1/0/+1
    jumping = key_pressed_fixed(eng.input, Raylib.KEY_SPACE)

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

"Gravity + integrate position, then resolve collisions axis-by-axis against platforms."
function physics(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    p = eng.params
    each(eng.world, PlayerBody) do e, pb
        pb.vel[2] += p.gravity * dt
        pb.on_ground = false

        # horizontal, then vertical — keeps corners from snagging
        pb.pos[1] += pb.vel[1] * dt
        resolve_axis!(eng, pb, 1)
        pb.pos[2] += pb.vel[2] * dt
        resolve_axis!(eng, pb, 2)
    end
    return nothing
end

function resolve_axis!(eng, pb::PlayerBody, axis_i::Int)
    each(eng.world, Platform) do _, pl
        (pl.solid && overlaps(pb, pl)) || return
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

# ───────────── Render ─────────────

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
    return nothing
end

# ───────────── Scene ─────────────

function build_level!(eng::RayEngine.Engine{GameParams,GameState})
    w = eng.world
    p = eng.params

    # floor
    spawn!(eng.commands, w, Platform([0.0, 680.0], [1280.0, 60.0], true))
    # a few platforms to hop between
    spawn!(eng.commands, w, Platform([200.0, 560.0], [160.0, 24.0], true))
    spawn!(eng.commands, w, Platform([500.0, 480.0], [160.0, 24.0], true))
    spawn!(eng.commands, w, Platform([820.0, 400.0], [160.0, 24.0], true))
    spawn!(eng.commands, w, Platform([560.0, 300.0], [160.0, 24.0], true))
    spawn!(eng.commands, w, Platform([260.0, 220.0], [160.0, 24.0], true))
    # decorative ledge
    spawn!(eng.commands, w, Platform([1000.0, 320.0], [60.0, 60.0], false))

    spawn!(eng.commands, w, PlayerBody(copy(p.spawn), [0.0, 0.0], [p.player_w, p.player_h], false, 1.0))
    return nothing
end

RayEngine.load_scene!(eng::RayEngine.Engine{GameParams,GameState}, ::Val{:game}) =
    build_level!(eng)

# ───────────── Stage listings ─────────────

"Hotkeys that must work even while paused: debug overlay + pause toggle."
function input_controls(eng::RayEngine.Engine{GameParams,GameState}, dt::Float64)
    if key_pressed(eng.input, Raylib.KEY_F)
        p = eng.params
        p.show_debug[] = !p.show_debug[]
    end
    if key_pressed(eng.input, Raylib.KEY_P)
        s = eng.state
        s.status[] = s.status[] === :paused ? :running : :paused
    end
    return nothing
end

stage_input()      = (input_controls,)
stage_fixed()      = (player_input, physics, respawn, keep_in_view)
stage_update()     = ()                                  # nothing frame-rate driven
stage_render()     = (clear, draw_scene)
stage_overlay()    = ()                                  # debug overlay handled by engine

# ───────────── Entry point ─────────────

"""
    run!(; headless=false)

Build and start the engine window. With `headless=true` it calls `simulate!` a few
frames so smoke tests / CI can run without a display.
"""
function run!(; headless::Bool = false, frames::Int = 1)
    p = GameParams()
    s = GameState()
    eng = RayEngine.Engine(
        p, s;
        config = RayEngine.EngineConfig(title = "RayEngine Platformer"),
        input      = stage_input,
        fixed_update = stage_fixed,
        update     = stage_update,
        render     = stage_render,
        overlay    = stage_overlay,
    )
    eng.state.scene[] = :game
    reset_scene!(eng)                 # runs load_scene!(Val(:game))

    if headless
        for _ in 1:frames
            simulate!(eng, 1 / 60)
        end
        return eng
    end
    s.status[] = :running
    start!(eng)
    return eng
end
