"""
Example game: a player circle plus bouncing balls. Exercises fixed-step physics, render
interpolation (`ctx.alpha`), the command buffer, the bus, params, scenes and hotkeys.

Keys: arrows move, SPACE jump, B ball, P pause, N step (while paused), R reset scene, F1 debug.
"""
module MyGame

using RayEngine
using Observables
using Random
import Raylib

# Every @system in this module registers here. See MyEngine.@system.
const SYSTEMS = SystemRegistry()

include("components.jl")
include("state.jl")
include("systems.jl")
include("scenes.jl")

"""
    new_engine() -> Engine

Build an engine with systems installed and the :arena scene loaded. Does not open a window.
"""
function new_engine(; width::Int = 1280, height::Int = 720, seed::Integer = 1)
    cfg = EngineConfig(title = "MyGame", width = width, height = height)
    eng = Engine(Params(), GameState(); config = cfg)
    set_resource!(eng.resources, Arena(Float32(width), Float32(height)))
    set_resource!(eng.resources, Xoshiro(seed); persist = true)
    install!(eng, SYSTEMS)
    wire_listeners!(eng)
    goto_scene!(eng, :arena)          # loaded at the start of the first frame
    return eng
end

"Open the window and return the running engine; the prompt stays live."
launch(; kw...) = start!(new_engine(; kw...))

end # module
