# RayEngine Platformer example

A tiny 2D platformer using the RayEngine ECS. Jump between platforms, fall off the
bottom to respawn. No textures, no camera, no audio — one `PlayerBody`, a floor and a
few `Platform`s.

## Layout

```
example/
  Project.toml      package manifest deps; RayEngine wired as a path dep
  activate.jl       Pkg.develop("..") so RayEngine resolves
  src/
    Platformer.jl   module entry (exports run!)
    game.jl         Params, GameState, components, systems, scene, run!
    run.jl          entry: builds + starts the window
```

## Run

From any Julia after instantiating this environment:

```julia
using Pkg; Pkg.instantiate()
using Platformer
eng = Platformer.run!()          # opens the window, REPL stays live
```

With julia-mcp, activate the `example/` environment first (`env_path`), then
`using Platformer; Platformer.run!(headless=true)` for a smoke test that needs no
display.

## Controls

| Key | Action |
|---|---|
| Left / Right arrows | move |
| Space | jump (edge-triggered, one per ground contact) |
| F | toggle debug overlay (`params.show_debug`) |
| P | pause / resume |
| Esc | close window |

## How it's wired

- **fixed_update** = `(player_input, physics, respawn, keep_in_view)`. Input reads the
  fixed latch (`key_pressed_fixed`) so a Space tap is consumed by exactly one fixed step.
  Physics integrates gravity then resolves AABB collisions axis-by-axis against solid
  `Platform`s so the player can't snag corners.
- **render** = `(clear, draw_scene)`. Rebuilds `Rect`s each frame from floating-point
  bodies and draws them with `RayEngine.draw`.
- The scene is defined by `RayEngine.load_scene!(eng, ::Val{:game})`; `run!` sets
  `state.scene[] = :game` and calls `reset_scene!`.

`GameState` carries `status`, `scene`, `jumps` and `deaths` as `Observable`s, so you can
`listen!` to them:
```julia
listen!(x -> println("jumps=", x), eng, :jump_log, eng.state.jumps)
```

## Headless smoke test

No window, runs N fixed frames, returns the engine:
```julia
eng = Platformer.run!(headless=true, frames=60)
entity_count(eng.world)               # player + 7 platforms = 8
```

## Note

Fixed `dt = 1/60` with `gravity = 1500`, `jump_velocity = 560` gives snappy hops; tune
in `GameParams`. The world is fixed to the 1280×720 viewport — extend `build_level!` to
add more sections.
