# WeirdForce — Chromatic Drift

A one-screen prototype for RayEngine where **the background is the physics**.

`src/background.fs` paints a colour field. `src/map.jl` is an allocation-free
CPU port of that exact shader, so the game can sample the colour under the
player and turn it into acceleration:

| sample            | force                        |
| ----------------- | ---------------------------- |
| red dominant      | push left                    |
| green dominant    | push right                   |
| blue dominant     | push up                      |
| white             | hover (forces cancel)        |
| black (vignette)  | dead zone                    |
| yellow            | down (red + green, no blue)  |

You can only steer horizontally. Height is the field's business — ride the
magenta updrafts, let the green water carry you right, and dive through the
yellow downdrafts.

## Play

From `example/`:

```sh
julia --project=. activate.jl
```

or from the REPL:

```julia
using WeirdForce
WeirdForce.run!()
```

Reach the gold beacon before its countdown ring drains. Each capture moves the
tour to a different mood of the field; after all six, the field jumps more
often and the tour starts again. Missing a beacon shifts both the beacon and the
field. Every few seconds the whole field also jumps a little to a new snapshot.

| key                    | action                                 |
| ---------------------- | -------------------------------------- |
| `A` / `D`, `←` / `→`   | nudge left / right                     |
| `W` / `S`, `↑` / `↓`   | nudge up / down                        |
| `G`                    | toggle the force-arrow grid            |
| `F`                    | engine debug overlay                   |
| `P`                    | pause / resume                         |
| `R`                    | restart the run                        |

The white arrows are the field's force at each point (G toggles the grid); the
player has to learn the currents by reading the colours and feeling the drift.

## Headless

```julia
eng = WeirdForce.run!(headless = true, frames = 120)
simulate!(eng, 1 / 60)     # no window, no Raylib calls
```

`Pkg.test()` runs the headless suite: sampler range/determinism, the RGB→force
signs, manual thrust, capture/advance, tour escalation, timed shifts, and `R`
reset.

## Notes for hacking

- `background.fs` and `map.jl` are a pair. If you change the GLSL, mirror it in
  `sample_field`; the physics feels exactly the colours that are drawn.
- The field is a *held snapshot*, not a continuous drift. `background.fs` takes
  `u_shift`, the game writes `state.field_time` into it each frame, and
  `sample_field` samples the same value. `shift_field!` picks the next snapshot
  (a golden-ratio jump); `field_timer` does it every `shift_every` seconds, and
  goal timeouts / completed tours force one too.
- `draw_player` runs in the **overlay** stage, after the HUD: the field loves to
  pin the player to a corner and the light should never hide behind a panel.
