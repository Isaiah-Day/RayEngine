"""
MyEngine: a small ECS game engine for Julia, built on Raylib.jl and Observables.jl.

Two speeds:
  * hot path  : ECS storages, systems, InputState (plain arrays, no Observables)
  * reactive  : Params, GameState, Bus, listen! (Observables; low volume, change-driven)

The game package supplies concrete `Params` and `GameState` types. The engine only
requires that

  state.status :: Observable{Symbol}   # :running | :paused | :stopped
  state.scene  :: Observable{Symbol}

and, optionally, `params.show_debug :: Observable{Bool}` for the overlay.
"""
module RayEngine

using Observables
using Serialization
import Raylib
using Colors
using ColorTypes

Vec = Array{Int, 1}


include("visual/theme.jl")
include("visual/objects.jl")
include("visual/draw.jl")
include("ecs.jl")
include("commands.jl")
include("input.jl")
include("resources.jl")
include("reactive.jl")
include("engine.jl")
include("debug/dev.jl")
include("debug/overlay.jl")
include("loop.jl")

# ECS
export Entity,
    World,
    spawn!,
    despawn!,
    add!,
    remove!,
    each,
    get_component,
    has_component,
    is_alive,
    entities,
    components,
    entity_count
export CommandBuffer, apply!
# input
export InputState,
    key_down,
    key_pressed,
    key_released,
    key_pressed_fixed,
    button_down,
    button_pressed,
    button_released,
    axis,
    press!
# resources
export Resources, resource, set_resource!, has_resource
# reactive
export Bus, channel, emit!, listen!, unlisten!, unlisten_all!
export Ctx, Engine, EngineConfig
# engine loop
export simulate!, render!, frame!
export start!, stop!, pause!, resume!, step!, enable!, disable!, systems
export start!, stop!, pause!, resume!, step!, enable!, disable!, systems
export reset_scene!, load_scene!, goto_scene!
export inspect, snapshot!, restore!
export Rect, Circle, Ellipse, Triangle, Pixel, Line, BezierSpline, LinearSpline, Style, Theme, draw, getPos
end # module
