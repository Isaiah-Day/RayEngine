# AGENTS.md — RayEngine

RayEngine is a small ECS game engine for Julia, built on Raylib.jl and Observables.jl. The
engine is the module `RayEngine` in `src/`. Game code is supposed to live in a separate
package; `example/` is a sample game that is currently **out of sync with the engine** and
does not load (see Known issues).

> Note: engine recovered from the stage refactor; test suite is **green** (201 assertions, `Pkg.test()`).
> See Known issues for the remaining gaps.

## Project layout

```
Project.toml        RayEngine package (deps: ColorTypes, Colors, FixedPointNumbers, Observables, Raylib, Serialization, Test)
Manifest.toml       Resolved manifest
.gitignore          `.DS_STORE` only
src/
  RayEngine.jl      Module entry point; `Vec = Array{Int,1}`; includes the files below; exports the public API
  ecs.jl            Entity, Storage (dense vector + sparse index), World, spawn!/add!/remove!/despawn!, each queries
  commands.jl       CommandBuffer: deferred spawn/despawn/add/remove, applied between stages
  input.jl          InputState: polled once per frame into plain BitVectors and fields
  resources.jl      Resources: singletons keyed by type; survive scene resets; opt-in persistence (snapshot)
  reactive.jl       Bus: one Observable per event type; emit!/channel
  engine.jl         EngineConfig, Clock, DevState, Engine{P,S}, Ctx (dead), simulate!, render!, scenes
  loop.jl           frame!, run_loop, start!/stop! (async loop on @async)
  debug/dev.jl      listen!/unlisten!/unlisten_all!, pause!/resume!/step!, enable!/disable!, systems, inspect, snapshot!/restore!
  debug/overlay.jl  Debug HUD: overlay_lines, draw_overlay! (toggled by params.show_debug)
  visual/           Drawables Rect, Circle, Line, Pixel, LinearSpline, BezierSpline,
                    Ellipse, Triangle + draw(); Style/Theme; theme.jl holds the Shader
                    data type, shader.jl the GL backend (see Visual drawing)
test/runtests.jl    Headless suite — GREEN (201 assertions). Covers ECS, CommandBuffer, Resources,
                    InputState, Bus/listen!, Engine (simulate!, pause/step, fixed-input latch,
                    fault isolation, commands-between-stages, render! headless, default ctor),
                    scenes/resets, snapshots, visual shapes. Fixtures: TPos/TVel/TTag,
                    TCounter/TRes resources, make_engine() stage wrapper
example/            Sample game package MyGame — stale, no longer loadable (old API)
```



## Running Julia: use julia-mcp

**Do not run `julia` from bash.** All Julia code goes through the `julia-mcp` server, which
keeps a persistent REPL per project.

### Tools

| Tool | Use |
|---|---|
| `julia_eval` | Run Julia code. Args: `code` (required), `env_path`, `timeout`, `julia_cmd` (rarely) |
| `julia_restart` | Clear a session. Last resort; slow, loses all state |
| `julia_list_sessions` | Show active sessions and their environments |

Use the `mcp__julia_mcp` namespace proxy: `mcp__julia_mcp({ tool: "julia_eval", args: { code, env_path, timeout } })`.

### Rules

- **Always pass `env_path: "/Users/iday/Documents/RayEngine"`** (the project root). That selects this
  project's environment, so `RayEngine` and its deps resolve.
- **Don't type `Pkg.activate()`** in `code`. `env_path` already does that.
- Results come back as printed output, so use `println` or `display` to see values.
- Session state persists between calls. A global set in one call is visible in the next. Keep
  long-lived objects (engines) in globals; use `local` for throwaway values.
- Revise is loaded in every session. Edits to `src/` take effect on the next call, so **don't
  restart** just because a file changed. Restart only when the session is broken or a change
  Revise can't apply (a struct's fields, a `const` value) requires it.
- Pkg operations (`Pkg.instantiate()`, `Pkg.test()`) disable the timeout automatically.

### Common calls

```julia
using RayEngine            # loads Raylib too, but opens no window

using Pkg; Pkg.test()      # full suite — green (201 assertions)

eng = Engine(TParams(), TState();   # headless engine; fixtures in test/runtests.jl
             config = EngineConfig(fixed_dt = 1/60),
             input = stage_input, fixed_update = stage_fixed, update = stage_update)
simulate!(eng, 1/60)       # no window, no Raylib calls
```

Raylib is loaded on `using RayEngine`, but no window opens unless `start!` is called.
`frame!`, `render!`, and `start!` need a display; don't call them from julia-mcp unless the
user wants a window. `stop!(eng)` ends the loop but is currently unsafe without a window
(see Known issues).

## Architecture

### Two speeds
- **Hot path**: ECS storages, systems, `InputState`. Plain arrays, no Observables.
- **Reactive path**: `Params`, `GameState`, `Bus`, `listen!`. Observables, low volume, change-driven.

Don't put per-entity data in Observables, and don't use Observables for anything read every frame.

### Frame
`frame!` (loop.jl) does, in order:
1. `poll_input!` (reads Raylib into `InputState`)
2. `simulate!` (engine.jl) — headless-safe:
   - apply a pending scene switch
   - `input` stage (always runs, even while paused, so hotkeys can unpause)
   - fixed steps: accumulator-driven, capped by `max_fixed_steps`; the backlog is dropped at the cap.
     Each step runs `fixed_update`, then `apply!` commands, then clears the `fixed_pressed` latch.
   - if not paused: `update`, `apply!` commands, advance `clock.elapsed`
   - paused + `step!` runs exactly one fixed step, then `update` with `dt = fixed_dt`
3. `Raylib.BeginDrawing`, then `render!`: `render`, `overlay`, and the debug overlay if
   `params.show_debug[]`, then `Raylib.EndDrawing` (always, via `try/finally`).

Stage order: `input, fixed_update, update, render, overlay`. There is no `late_update`.

`simulate!` makes no Raylib calls, so tests and replays drive the engine headless. For windowed
frames, `frame!` polls input then calls `simulate!`; in tests, input is faked with `press!`.

### Systems
- A system is a plain function `f(eng::Engine, dt::Float64)`, reaching everything through `eng`
  (`eng.world`, `eng.resources`, `eng.input`, `eng.bus`, `eng.state`, `eng.params`, `eng.commands`).
- A stage is a zero-arg function that returns a tuple of systems, e.g.
  `stage_update() = (move!, collide!)`. Systems run in tuple order. Stages are passed to the
  constructor: `Engine(params, state; config, input, fixed_update, update, render, overlay)`.
- **Fault isolation**: a system that throws is added to `eng.disabled` and the error is stored in
  `eng.dev.last_error[]`. Fix the code, then `enable!(eng, f)` (function object or `:name`).
  `enable!` also clears `last_error`. `disable!` switches a system off by name or object.
- The debug HUD is separate: if it throws, `params.show_debug` is set to `false`.
- Stages are zero-arg functions returning system tuples; `run_systems!` invokes each stage via
  `Base.invokelatest`, and a throwing system is pushed onto `eng.disabled` with an `@error`
  log through `record_error!` (engine.jl). Legacy `Vector{Any}` stages still work.

### Structural changes
- Queue structural changes on `eng.commands`: `spawn!(eng.commands, eng.world, ...)`, `add!`,
  `remove!`, `despawn!`. Commands are applied after each fixed step and after `update`.
- **Never** spawn, despawn, add or remove on the `World` inside an `each` callback. Mutating
  component fields in place is fine.
- `spawn!` reserves the id immediately, so the returned handle is usable before the components land.

### ECS
- Components should be `mutable struct`s so `each` callbacks can edit them in place.
- Storages are dense `Vector{T}` with a swap-remove sparse index.
- Entity handles are `(id, gen)`. Despawning bumps the generation, so stale handles fail `is_alive`.
- `each` supports 1–3 component types, iterating in storage order of the first type.

### Input
- `InputState` stores key state in `BitVector`s indexed by `key+1`, with `NKEYS = 350`, and mouse
  buttons with `NBUTTONS = 7`.
- Use `key_down`, `key_pressed`, `key_released`, `button_*`, and `axis(inp, neg, pos)`,
  `mouse_pos`, `mouse_delta`, `wheel`.
- **Edge-triggered input in `fixed_update` must use `key_pressed_fixed`.** The fixed latch is set
  on press and cleared after one fixed step, so an edge is consumed by exactly one step.
- Keys are Raylib constants (`Raylib.KEY_SPACE`, ...). Use `Raylib.X` qualified; Raylib exports very little.

### Scenes and resets
- A scene is a method `RayEngine.load_scene!(eng, ::Val{:name})`. Extending it from another module
  needs the qualified name.
- `goto_scene!(eng, :name)` is safe from inside a system: the switch happens at the start of the
  next frame (staged in `dev.pending_scene`). `reset_scene!` clears the world and reruns the
  current scene.
- Scene resets keep `params`, `resources`, and `listen!` listeners.

### Params and GameState
The game supplies `Params` and `GameState` types. The engine requires:
- `state.status :: Observable{Symbol}` with `:running | :paused | :stopped`
- `state.scene :: Observable{Symbol}`

and optionally `params.show_debug :: Observable{Bool}` to enable the overlay.

### Resources
`set_resource!(eng.resources, x; persist=false)` stores a singleton keyed by its type. `persist=true`
includes it in `snapshot!`. Resources survive `reset_scene!`.

### Visual drawing
`src/visual/` is a small 2D shaping layer over Raylib, included by `RayEngine.jl`
(`theme.jl` → `objects.jl` → `shader.jl` → `draw.jl`).
- Drawables: `Rect(pos1, pos2)`, `Circle(center, r)`, `Line(x1,y1,x2,y2,w)` / `Line(p1,p2,w)`,
  `Pixel(x, y)`, `LinearSpline([[x,y], ...], width=1.0)`, `BezierSpline(p1, p2, w)`,
  `Ellipse(center, radius_h, radius_v)`, `Triangle(v1, v2, v3)` (6-coordinate forms too);
  `getPos(::Val{:left/:right/:down/:up}, obj)` gives a bounding edge.
- `LinearSpline` draws segment-by-segment with `DrawLineEx` (raylib's `DrawLineStrip` wrapper
  takes `Ref{<:StaticArray}`, so a `Vector{RayVector2}` won't dispatch). `Pixel`, `LinearSpline`
  and `BezierSpline` have no raylib outline variant; a non-`nothing` `stroke` is ignored with
  a `@warn` (same as `Line`). `Ellipse` and `Triangle` stroke via `DrawEllipseLines`/`DrawTriangleLines`.
- `Style`/`Theme` hold a Colors.jl `Color`, `alpha`, optional `stroke`/`strokewidth`, and an
  optional `shader::Union{Shader,Nothing}`. Objects hold a `style::Style` (not a union), so the
  plain-color path is always available.
- `draw(obj)` emits the Raylib draw calls and needs an active window (not callable headless).
- The types are exported but not wired into a dedicated stage; games call `draw` from a
  `:render`/`:overlay` system.

#### Shaders
- `Shader(frag; vert="", is_path=false, kwargs...)` in `theme.jl` is **plain data** (source,
  uniforms, a lazily-filled `handle`). Constructing one makes no Raylib calls, so it is safe on
  the headless data path. `file_shader(path)` loads from a `.fs` file and re-reads it when the
  mtime changes; `set_uniform!`/`set_source!` mutate it.
- `shader.jl` is the only file that touches GL. `draw(::Rect)` calls `with_shader(sh; size)`,
  which compiles on first use, uploads built-ins (`u_time`, `u_size`) plus user uniforms, wraps
  `f()` in `BeginShaderMode`/`EndShaderMode` (in a `finally`), and is the shader path for now.
- A shaded `Rect` is drawn as a 1x1 white texture stretched over the rect (`DrawTexturePro`), so
  `fragTexCoord` runs 0..1. raylib's own shape calls sample a sliver of its white texture, which
  is why they are not used here.
- `Style.shader` is only honoured by `Rect`; other shapes warn once and draw the plain colour.
- Compiling must happen on the window thread. `unload_all_shaders!()` runs in `start!`'s `finally`
  just before `CloseWindow`; shader finalizers are intentionally not used.
- raylib 4.0's bindings declare `const void *` as `Ref{Nothing}`; `ShaderValueRef <: Ref{Nothing}`
  in `shader.jl` is the adapter that lets `SetShaderValue` see any buffer.
- raylib 4.0 has no `IsShaderReady`: a compile failure silently falls back to the default shader.

### Bus and listeners
- `emit!(bus, event)` notifies synchronously, in registration order, on the game thread.
- `listen!(f, eng, :key, observable)` replaces any previous listener under `:key`, so re-running
  a REPL cell doesn't stack listeners. Prefer named functions as `f` so edits hot-reload.

### Loop and REPL
- `start!(eng)` opens the window on an `@async` task, so the REPL stays live; `stop!(eng)` waits for the task.
- The loop calls `Base.invokelatest(frame!, ...)` every frame, so Revise-redefined methods apply
  with no re-install. Stage listings are also re-read every call.
- Frame limiting uses `sleep`, not `Raylib.SetTargetFPS` (Raylib's limiter starves the REPL).
- A `frame!` error pauses the engine and records it; it does not crash the loop.

### Snapshots
`snapshot!(eng, path)` and `restore!(eng, path)` use `Serialization`. The format is not stable
across Julia versions; use snapshots only for same-version restarts. Struct field changes need a
restart: snapshot, restart Julia, restore.

## Conventions

- Julia style: 4-space indent, `snake_case` functions, lowercase struct fields. Mutating functions end in `!`.
- Keyword constructors via `@kwdef` for user-facing structs (`EngineConfig`, `Params`, `GameState`).
- Section dividers in `.jl` source use `# ───────────── Title ─────────────`. Keep that style.
- Engine code must not reference a window or Raylib in the data path; keep `simulate!` and the ECS
  Raylib-free so tests stay headless.
- Keep the exported surface in `src/RayEngine.jl` in sync with new public functions.
- Keep this file honest when you change layout, stages, or the public API.

## Known issues (verified 2025-10-14)

1. **`test/runtests.jl` needs `Test` in `[extras]`/`[targets]`** — already done; run
   `Pkg.resolve()` after touching deps so Pkg stops warning about a stale manifest.
2. **Shaders are Rect-only.** `Circle`/`Ellipse`/`Triangle` would need a bounding-box quad plus
   a `discard` in GLSL; `Line`/splines/`Text`/`Pixel` don't fit the UV model. All of them warn
   once and fall back to `Style.color`.
3. **A shader compile error cannot be detected.** raylib 4.0 lacks `IsShaderReady`; it logs to
   stderr and draws with the default shader. `compile!` only guards against a zero program id.
4. **`start!` is the only path that unloads shaders.** Driving `frame!` by hand (e.g. in a test
   window harness) leaves handles alive until `unload_all_shaders!` is called manually.
