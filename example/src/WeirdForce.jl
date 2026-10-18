"""
A very small platformer built on RayEngine. Jump between platforms, fall off the
bottom to respawn. Runs headless-safe (fixed_update/update) and opens a window
from `run.jl`.
"""
module WeirdForce

using RayEngine
using Raylib
using Colors
using Observables

export GameParams, GameState, run!

include("map.jl")
include("setup.jl")
include("systems.jl")
include("game.jl")
include("run.jl")

end # module
