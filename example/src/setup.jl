# ───────────── tuning ─────────────

const MAP_SIZE = (1280.0, 720.0)      # reference canvas the shader was tuned on
const FIELD_ITERATIONS = 40            # loop count in background.fs
const FIELD_ZOOM_SCALE = 0.82          # < 1 magnifies the field and its vignette inward
const FIELD_TIME_OFFSET = 5.0          # opening snapshot time
const FIELD_SHIFT_EVERY = 0.05          # seconds between field jumps
const FIELD_SHIFT_MIN = 0.05           # smallest jump, in field seconds
const FIELD_SHIFT_SPAN = 0          # extra jump range (0.25 .. 0.45)
const FIELD_SHIFT_FLOOR = FIELD_SHIFT_EVERY * 0.5   # quickening can at most double the rate

const FIELD_FRAG = joinpath(@__DIR__, "background.fs")

# ───────────── parameters & state ─────────────

Base.@kwdef mutable struct GameParams
    # engine / debug
    show_debug::Observable{Bool} = Observable(false)
    show_field::Observable{Bool} = Observable(true)     # G toggles the force arrows

    # force field: a held snapshot, occasionally shifted
    field_gain::Float64 = 1500.0       # colour units -> px/s²
    field_zoom::Float64 = FIELD_ZOOM_SCALE
    shift_every::Float64 = FIELD_SHIFT_EVERY
    shift_min::Float64   = FIELD_SHIFT_MIN
    shift_span::Float64  = FIELD_SHIFT_SPAN

    # player (centre position)
    player_r::Float64  = 13.0
    spawn::Vector{Float64} = [300.0, 610.0]
    thrust::Float64    = 520.0         # manual accel, px/s² (weaker than the field by design)
    drag::Float64      = 1.7           # 1/s; the field is a thick fluid
    max_speed::Float64 = 420.0
    bounce::Float64    = 0.30          # wall restitution
    trail_len::Int     = 20

    # goals: a tour of the field's different moods
    goals::Vector{Vector{Float64}} = [
        [1095.0, 165.0],               # top-right: thin, cool, weak lift
        [185.0, 175.0],                # top-left: green pushes right + down
        [640.0, 630.0],                # bottom: magenta updraft
        [1135.0, 545.0],               # bottom-right: dark, almost no force
        [330.0, 355.0],                # left side: cyan stream up-right
        [755.0, 260.0],                # the white hole: a dead zone
    ]
    goal_r::Float64    = 20.0
    goal_time::Float64 = 24.0          # seconds per beacon
    field_step::Float64 = 84.0         # arrow grid spacing

    bg::Shader = file_shader(FIELD_FRAG; u_shift = FIELD_TIME_OFFSET, u_zoom = FIELD_ZOOM_SCALE)

    colors::Dict{Symbol,Color} = Dict{Symbol,Color}(
        :goal => RGB(1.00, 0.94, 0.62),
        :hot  => RGB(1.00, 0.45, 0.50),
    )
end

Base.@kwdef mutable struct GameState
    status::Observable{Symbol} = Observable(:stopped)
    scene::Observable{Symbol}  = Observable(:none)
    captured::Observable{Int}  = Observable(0)

    player::Union{Nothing,Entity} = nothing
    goal::Union{Nothing,Entity}   = nothing

    goal_clock::Float64  = 0.0
    field_time::Float64  = FIELD_TIME_OFFSET   # current held snapshot (shader = physics)
    shift_clock::Float64 = FIELD_SHIFT_EVERY
    shifts::Int          = 0
    message::String      = ""
    message_age::Float64 = 99.0
end

function debug_enabled(p::GameParams)
    get(p.show_debug)
end

# ───────────── components ─────────────

"One drifting light. `pos` is the centre."
mutable struct PlayerBody
    pos::Vector{Float64}
    vel::Vector{Float64}
    radius::Float64
    rgb::NTuple{3,Float64}       # colour under the player this step
    force::NTuple{2,Float64}     # acceleration it produced, px/s²
    trail::Vector{Vector{Float64}}
end

mutable struct Goal
    pos::Vector{Float64}
    radius::Float64
    index::Int
end

"An expanding ring left behind by a capture. `age` drives the fade."
mutable struct Ripple
    pos::Vector{Float64}
    age::Float64
    life::Float64
    rgb::NTuple{3,Float64}
end
