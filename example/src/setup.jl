# ENGINE SETUP

Base.@kwdef mutable struct GameParams
    show_debug::Observable{Bool} = Observable(false)

    width::Float64 = 1280
    height::Float64 = 720

    # player physics, tuned to fixed_dt = 1/60
    gravity::Float64 = 1500.0
    jump_velocity::Float64 = 800.0
    move_speed::Float64 = 280.0
    player_w::Float64 = 36.0
    player_h::Float64 = 52.0
    spawn::Vector{Float64} = [200.0, 500.0]


    weirdforce::Vector{Float64} = [100, 100]

    colors = Dict{Symbol,Color}(
        :player    => colorant"#ef476f",
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

### COMPONENTS

mutable struct PlayerBody
    pos::Vector{Float64}     # top-left corner
    vel::Vector{Float64}
    size::Vector{Float64}
    facing::Float64
end

mutable struct Background
    shader::Style
end