# RayEngine: a Julia game engine

This repo is my attempt at making a game engine in the Julia language. This scene is very sparsely populated (I would estimate that there's less than 15 public attempts at a game engine) for a few reasons, the three most prominent being GC, distribution, and gaps in infastructure (which I guess this project is attempting to fix).

To make the project feasable, I did use Raylib.jl (bindings for the C library raylib) for graphics. There are no other major dependencies. I coded an ECS (see src/ecs.jl) as the storage.

Docs are coming soon. For now, look at the example.



For instructions on running examples go to a specific release.