# AGENTS.md — RayEngine

RayEngine is a skeleton 2D game engine written in Julia. It builds a small
drawing/input canvas on top of Raylib, with observable-style state modeled on
GameZero.jl. Most of the engine is scaffolding with `TODO` markers; the goal of
this repository is to shape the architecture, not to ship features yet.

## Project layout

```
Project.toml    Julia project config (name, uuid, deps, compat)
Manifest.toml   Resolved dependency manifest
src/
  RayEngine.jl    Module entry point: Screen struct, debug_loop, drawable-scan
  theme.jl        Theme, Style, Shader structs
  input.jl        Keyboard (Observable-based), input plumbing
  drawables.jl    Drawable abstract type; Rect, Line, Circle; getPos
  draw.jl         draw!, fill!, clear! (all TODO stubs)
```

## Dependencies

- `Raylib` — native windowing/rendering bindings
- `Observables` — state as observables (Keyboard, Screen)
- `Colors` / `ColorTypes` — color values and manipulation

Pretty-print the dependency graph with `Julia.@deps` if curious; keep `[compat]`
entries in `Project.toml` in sync with the manifest.

## Core design

- `Screen` is the central handle: width/height, a `Keyboard` observable, and a
  `Theme`. Constructed with `@kwdef` keyword arguments.
- `Vec` is `Array{<:Number,1}` — plain 1-D numeric vectors everywhere.
- Drawables (`Rect`, `Line`, `Circle`) subtype `abstract type Drawable` and carry
  a `style` field typed `Union{Shader,Style}`.
- `getPos(drawable, ::Val{:left|right|up|down})` returns bounding positions:
  Rect edges are its two corners, Line corners are min/max of its endpoints,
  Circle's box is centered on its center.
- `debug_loop(screen; update=0.2)` drives a `Timer` that redraws every `update`
  seconds; `stop_debug_loop()` closes the timer.
- `_draw_all_drawables(screen)` scans the `Main` module's globals, filters out
  names starting with `#` or `@` and the module name itself, keeps values whose
  type is `<: Drawable`, then draws each. Drawing is pull-based from global
  scope, not registered.

## Conventions

- Julia style: 4-space indent, `snake_case` functions, lowercase struct fields.
- Keyword constructors via `@kwdef` for user-facing structs.
- `@kwdef mutable struct` for user-visible types with keyword constructors
- Position vectors are `Vec = Array{<:Number,1}`, usually `[x, y]`
- Drawables subtype the `Drawable` abstract type and carry `style::Union{Shader,Style}`
- `getPos(::Val{:left}, obj)` looks up bounding edge: left/right/up/down for any drawable
- `Shader` is explicitly **not** implemented; do not implement it
- Although multiple `Screen`s may exist, the project only supports one currently.
- `Raylib` exports very few items: generally use `Raylib.X`

## Known TODOs / unimplemented

- `draw!(s, d::Rect)` in `src/draw.jl` is wired to Raylib (`DrawRectangle` +
  optional `DrawRectangleLinesEx` stroke); `fill!` and `clear!` are still
  stubs — background rendering not wired to Raylib yet.
- `Keyboard.getproperty` returns `# TODO` — key-down state is not implemented.
  Mouse needs the same treatment, probably with an enum.
- `Shader` is declared but marked "NOT IMPLEMENTED, DO NOT IMPLEMENT" — leave it.
- `Style`'s `stroke` / `strokewidth` / `alpha` fields are unused so far.

## Working with the code

Run Julia using `julia-mcp`. There are no tests yet; 
behavior is exercised through the REPL by constructing a `Screen` and
calling `debug_loop`. When touching a system, update this file's layout and
TODO sections so the scaffolding stays honest.

Example:
```julia
using RayEngine
s = Screen(800, 800)
debug_loop(s)          # redraw every update seconds (default 0.2)
stop_debug_loop()      # close the timer
```

Raylib needs a display; headless CI can't run the engine. Pure logic (bounding boxes, theme, structs) is testable without opening a window.
