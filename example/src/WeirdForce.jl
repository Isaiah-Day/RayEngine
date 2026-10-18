"""
Chromatic Drift — a one-screen prototype for RayEngine.

The background is the force field. The shader paints it and `map.jl` samples
the exact same function, so the colour under the player becomes acceleration:
red pushes left, green pushes right, blue pushes up. The field holds still and
occasionally jumps to a new snapshot. Steer with WASD (or the arrow keys) — a
manual nudge that is deliberately weaker than the field — and ride the currents
to the beacon before its ring runs out.
"""
module WeirdForce

using RayEngine
using Raylib
using Colors
using Observables

export GameParams, GameState, run!

include("setup.jl")
include("map.jl")
include("systems.jl")
include("game.jl")
include("run.jl")

end # module
