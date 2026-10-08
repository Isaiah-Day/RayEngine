# AGENTS.md — RayEngine

RayEngine is a small ECS game engine for Julia, built on Raylib.jl and Observables.jl. The
engine is the module `RayEngine` in `src/`. Game code is supposed to live in a separate
package; `example/` is a sample game that is currently out of sync with the engine (see
Known issues).

## Project layout

```
Project.toml        RayEngine package (deps: Raylib, Observables, Colors, ColorTypes, FixedPointNumbers, Serialization, Test)
Manifest.toml       Resolved manifest
README.md           Design overview (partly stale, see Known issues)
src/
  RayEngine.jl      Module entry point; includes the files below; exports the public API
  ecs.jl            Entity, Storage (sparse set), World, spawn!/add!/remove!/despawn!, each queries
  commands.jl       CommandBuffer: deferred spawn/despawn/add/remove, applied between stages
  input.jl          InputState: polled once per frame into plain BitVectors and fields
  resources.jl      Resources: singletons keyed by type; survive scene resets; opt-in persistence
  reactive.jl       Bus: one Observable per event type; emit!/channel
  schedule.jl       STAGES, Schedule, SystemRegistry, @system, install!
  engine.jl         EngineConfig, Clock, DevState, Engine{P,S}, Ctx, simulate!, render!, scenes
  loop.jl           frame!, run_loop, start!/stop! (async loop on @async)
  debug/dev.jl      listen!/unlisten!, pause!/resume!/step!, enable!/disable!, inspect, snapshot!/restore!
  debug/overlay.jl  Debug HUD (overlay_lines, draw_overlay!)
  visual/           UNUSED leftovers from the old skeleton (see Known issues)
test/runtests.jl    Headless tests (drive simulate!, never open a window)
example/            Sample game module (MyGame) — not currently loadable
```

## Running Julia: use julia-mcp

**Do not run `julia` from bash.** All Julia code goes through the `julia-mcp` server, which
keeps a persistent REPL per project. This file is the only place that describes the workflow;
the tool schema itself is short.

### Tools

| Tool | Use |
|---|---|
| `julia_eval` | Run Julia code. Args: `code` (required), `env_path`, `timeout` (default 60 s), `julia_cmd` (rarely; only if asked) |
| `julia_restart` | Clear a session. Last resort; slow, and it loses all state |
| `julia_list_sessions` | Show active sessions and their environments |

Use the `julia-mcp` namespace proxy: `mcp__julia_mcp` with `tool: "julia_eval"` and `args: {code, env_path, timeout}`
(verified). If the server shows as not connected, run `mcp({ connect: "julia-mcp" })` first.

### Rules

- **Always pass `env_path: "/Users/iday/Documents/RayEngine"`** (the project root). That selects this
  project's environment, so `RayEngine` and its deps resolve. Without it, `using RayEngine` fails with
  `Package RayEngine not found in current path` (verified).
- **Don't type `Pkg.activate()`** in `code`. `env_path` already does that.
- Results come back as printed output, so use `println` or `display` to see values.
- Session state persists between calls. A global you set in one call is visible in the next (verified).
  Keep long-lived objects such as engines in globals, and use `local` for throwaway values.
- Revise is loaded in every session. Edits to `src/` take effect on the next call, so **don't restart**
  just because a file changed. Restart only when the session is broken, or when a change Revise can't
  apply (a struct's fields, or a `const` value) requires it.
- Precompile notices of the form "N dependencies precompiled but different versions are currently
  loaded" mean the session has stale stdlib/dep versions loaded. Restart the session once if you see
  it and the next step depends on those packages.
- Pkg operations (`Pkg.instantiate()`, `Pkg.test()`) disable the timeout automatically. Use the normal
  timeout for everything else.

### Common calls

```julia
# load the engine (env_path = project root)
using RayEngine

# headless tests
using Pkg; Pkg.test()

# headless simulation: no window, no Raylib calls
eng = RayEngine.Engine(...)   # see test/runtests.jl make_engine() for a complete example
simulate!(eng, 1/60)
```

Raylib is loaded on `using RayEngine`, but no window is opened unless `start!` is called.
`frame!`, `render!`, and `start!` need a display. Don't call them from julia-mcp unless the user
wants a window. `stop!(eng)` ends the loop.

`Pkg.test()` runs the whole suite (10 testsets, all passing at the last run). To check one testset,
copy its body into a `julia_eval` call after `using RayEngine` and the fixtures at the top of
`test/runtests.jl`.

## Architecture

### Two speeds
- **Hot path**: ECS storages, systems, `InputState`. Plain arrays, no Observables.
- **Reactive path**: `Params`, `GameState`, `Bus`, `listen!`. Observables, low volume, change-driven.

Don't put per-entity data in Observables, and don't use Observables for anything that needs to
be read every frame.

### Frame
`frame!` (loop.jl) does, in order:
1. `poll_input!` (reads Raylib into `InputState`)
2. `simulate!` (engine.jl):
   - apply a pending scene switch
   - `:input` stage (always runs, even while paused, so hotkeys can unpause)
   - fixed steps: accumulator-driven, capped by `max_fixed_steps`; the backlog is dropped at the cap.
     Each step runs `:fixed_update`, then `apply!` commands, then clears the `fixed_pressed` latch.
   - if not paused: `:update`, `:late_update`, `apply!` commands, advance `clock.elapsed`
   - paused + `step!` runs exactly one fixed step, then `:update` and `:late_update` with `dt = fixed_dt`
3. `Raylib.BeginDrawing`, then `render!`: `:render`, `:overlay`, and the debug overlay if
   `params.show_debug[]`, then `Raylib.EndDrawing` (always, via `try/finally`).

Stage order: `(:input, :fixed_update, :update, :late_update, :render, :overlay)`.

`simulate!` takes no Raylib calls, so tests and replays can drive the engine headless. Input must
already be polled, or faked with `press!`.

### Systems
- Declare `const SYSTEMS = SystemRegistry()` once in the game module. Then
  `@system :stage function name(w::World, ctx) ... end` registers the function there.
- Systems run in definition order within a stage.
- `install!(eng, MyGame.SYSTEMS)` attaches the registry to an engine. Run it again after adding a
  new `@system`.
- **Fault isolation**: a system that throws is disabled, and the error is stored in
  `eng.dev.last_error[]`. Fix the code, then `enable!(eng, :name)`. An error in the overlay disables
  the overlay instead.

### Structural changes
- Inside a system, use `ctx.commands` (`spawn!(ctx.commands, w, ...)`, `add!`, `remove!`,
  `despawn!`). Commands are applied between stages.
- **Never** spawn, despawn, add or remove on the `World` inside an `each` callback. Mutating
  component fields in place is fine.- `spawn!` reserves the id immediately, so the handle is usable before the components land.

### ECS
- Components should be `mutable struct`s so `each` callbacks can edit them in place.
- Storages are dense `Vector{T}` with a swap-remove sparse index.
- Entity handles are `(id, gen)`. Despawning bumps the generation, so stale handles fail `is_alive`.
- `each` supports 1–3 component types. Entities are iterated in storage order.

### Input
- `InputState` stores key state in `BitVector`s indexed by `key+1`, with `NKEYS = 350`, and mouse
  buttons with `NBUTTONS = 7`.
- Use `key_down`, `key_pressed`, `key_released`, and `axis(inp, neg, pos)`.
- **Edge-triggered input in `:fixed_update` must use `key_pressed_fixed`.** The fixed latch is set
  on press and cleared after one fixed step, so an edge is consumed by exactly one step. Plain
  `key_pressed` can miss or double-fire in fixed steps.
- Keys are Raylib constants (`Raylib.KEY_SPACE`, ...). Use `Raylib.X` qualified; Raylib exports very little.

### Scenes and resets
- A scene is a method `RayEngine.load_scene!(eng, ::Val{:name})`. Extending it from another module
  needs the qualified name.
- `goto_scene!(eng_or_dev, :name)` is safe from inside a system: the switch happens at the start of
  the next frame. `reset_scene!` clears the world and reruns the current scene.
- Scene resets keep `params`, `resources`, and `listen!` listeners.

### Params and GameState
The game supplies `Params` and `GameState` types. The engine requires:
- `state.status :: Observable{Symbol}` with `:running | :paused | :stopped`
- `state.scene :: Observable{Symbol}`

and optionally `params.show_debug :: Observable{Bool}` to enable the overlay.

### Resources
`set_resource!(eng.resources, x; persist=false)` stores a singleton keyed by its type. `persist=true`
includes it in `snapshot!`.

### Bus and listeners
- `emit!(bus, event)` notifies synchronously, in registration order, on the game thread.
- `listen!(f, eng, :key, observable)` replaces any previous listener under `:key`, so re-running
  a REPL cell doesn't stack listeners. Prefer named functions as `f` so edits hot-reload.

### Loop and REPL
- `start!(eng)` opens the window on an `@async` task, so the REPL stays live. `stop!(eng)` waits for the task.
- The loop calls `Base.invokelatest(frame!, ...)` each frame, so Revise-redefined methods take effect.
- Frame limiting uses `sleep`, not `Raylib.SetTargetFPS`, because Raylib's limiter blocks the Julia
  thread and starves the REPL.
- A `frame!` error pauses the engine and records the error; it does not crash the loop.

### Snapshots
`snapshot!(eng, path)` and `restore!(eng, path)` use `Serialization`. The format is not stable
across Julia versions; use snapshots only for same-version restarts. Struct field changes need a
restart: snapshot, restart Julia, restore.

## Conventions

- Julia style: 4-space indent, `snake_case` functions, lowercase struct fields. Mutating functions end
  in `!`.
- Keyword constructors via `@kwdef` for user-facing structs (`EngineConfig`, `Params`, `GameState`).
- Section dividers in source use `# ───────────── Title ─────────────`. Keep that style when adding
  sections.
- Engine code must not reference a window or Raylib in the data path. Keep `simulate!` and the ECS
  Raylib-free so the tests stay headless.
- Keep the exported surface in `src/RayEngine.jl` in sync with new public functions.
- Keep this file and `README.md` honest when you change layout, stages, or the public API.

## Known issues (as of this writing)

1. **`example/` does not match the engine.** `example/src/MyGame.jl` says `using MyEngine`, and
   `scenes.jl` extends `MyEngine.load_scene!`. The package is `RayEngine`, and `example/Project.toml`
   has no dependencies. The example can't load as is.
2. **`README.md` describes a layout that doesn't exist** (`MyEngine/`, `MyGame/`, `dev/setup.jl`,
   `dev/startup.jl`, and `dev.jl`/`overlay.jl` at the top level). Its "Status" section says nothing
   has been compiled; the engine loads and the tests pass (Julia 1.12.7, macOS aarch64).
3. **`src/visual/` is dead code** from the old skeleton (`Screen`, `Rect`, `Style`, `Shader`, `Theme`).
   It is not included by `RayEngine.jl`, and it references types that no longer exist. Don't wire it
   in without rewriting it. Shader is still marked "NOT IMPLEMENTED, DO NOT IMPLEMENT".
4. **`test.jl` at the repo root** is a skeleton script that calls `Screen()`, `Rect`, and `draw!`.
   Those no longer exist.
5. `Project.toml` lists `Test` under `[deps]`. It belongs in `[extras]`/`[targets]`.
6. No `.gitignore` yet; `.DS_Store` is untracked.
7. The old `AGENTS.md` (skeleton: `Screen`, `debug_loop`, drawables) was removed from the working
   tree. This file replaces it.
