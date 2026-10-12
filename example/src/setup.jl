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

### COMPONENTS

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
    solid::Bool
end


mutable struct Writing
    text::String
    pos::Vector{Float64}
    size::Int
end