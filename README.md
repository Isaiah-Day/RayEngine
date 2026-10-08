# Julia game engine (Raylib.jl + Observables.jl)

```
MyEngine/   ECS, schedule, fixed-timestep loop, reactive layer, dev tools   (the engine)
MyGame/     example game: components, systems, scenes, Params/GameState      (your code)
dev/        setup.jl (one-time) and startup.jl (REPL session)
```

## Run

```
julia dev/setup.jl                         # once: adds deps, develops both packages
julia --project=dev -i dev/startup.jl      # window opens, prompt stays live
```

Tests (no window needed; they drive the engine headless via `simulate!`):

```
julia --project=MyEngine -e 'using Pkg; Pkg.test()'
```

## Layers

| File (MyEngine/src) | Contents |
|---|---|
| `ecs.jl` | `Entity`, sparse-set `Storage`, `World`, `each` queries |
| `commands.jl` | `CommandBuffer`: deferred spawn/despawn/add/remove |
| `input.jl` | `InputState`, polled once per frame; `fixed_pressed` edge latch |
| `resources.jl` | `Resources`: singletons that survive scene resets, opt-in snapshot persistence |
| `reactive.jl` | `Bus`: one Observable per event type |
| `schedule.jl` | stages, `SystemRegistry`, `@system` |
| `engine.jl` | `EngineConfig`, `Clock`, `DevState`, `Engine{P,S}`, `Ctx`, `simulate!`, scenes |
| `dev.jl` | `listen!`, pause/step, enable!/disable!, `inspect`, `snapshot!`/`restore!` |
| `overlay.jl` | debug overlay (`params.show_debug[] = true`, or F1) |
| `loop.jl` | `start!`/`stop!`, async loop with `invokelatest` per frame |

## Writing a game

* Define `Params` and `GameState` (structs of Observables). The engine requires `state.status` and
  `state.scene`, and optionally `params.show_debug`.
* In your module: `const SYSTEMS = SystemRegistry()`, then `@system :stage function name(w, ctx) ... end`.
  Stages: `:input` (always runs, even paused) → `:fixed_update` (0..n times) → `:update` → `:late_update` → `:render` → `:overlay`.
* Scenes: `MyEngine.load_scene!(eng, ::Val{:name})`; `goto_scene!`/`reset_scene!` swap them.
* Structural changes inside systems go through `ctx.commands` (`spawn!(ctx.commands, w, ...)`).
* In `:fixed_update` use `key_pressed_fixed`, elsewhere `key_pressed`.

## REPL workflow

Edit a system, save, and Revise applies it on the next frame. Systems that throw are disabled and the error
(with backtrace) is stored in `eng.dev.last_error[]`; after fixing, `enable!(eng, :name)`.
After adding a brand-new `@system`, run `install!(eng, MyGame.SYSTEMS)`. Changing a struct's fields needs a
restart: `snapshot!` before, `restore!` after.

## Status

Written without a Julia runtime available, so **nothing here has been compiled or run yet**. Expect a small
number of first-run fixes. The most likely spots are Raylib.jl details (key constants like `Raylib.KEY_SPACE`,
`Color` construction, `GetMousePosition` field types); check with `?Raylib.IsKeyDown`.
