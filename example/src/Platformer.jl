"""
A very small platformer built on RayEngine. Jump between platforms, fall off the
bottom to respawn. Runs headless-safe (fixed_update/update) and opens a window
from `run.jl`.
"""
module Platformer

using RayEngine
using Raylib
using Colors
using Observables

export GameParams, GameState, run!

include("game.jl")

end # module
