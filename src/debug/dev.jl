# REPL-facing API. The REPL only runs when the loop yields, i.e. between frames,
# so direct mutation of world/params from the prompt needs no locking.

spawn!(eng::Engine, comps...) = spawn!(eng.world, comps...)
despawn!(eng::Engine, e::Entity) = despawn!(eng.world, e)

# ───────────── Keyed listeners (no stacking on re-run) ─────────────

"""
    listen!(f, eng, :key, observable)

Like `on`, but re-running replaces the previous listener under `:key`. Have `f` call a
named function so edits to that function hot-reload.
"""
function listen!(f, eng::Engine, key::Symbol, obs::Observable)
    unlisten!(eng, key)
    eng.dev.listeners[key] = on(f, obs)
    return nothing
end

function unlisten!(eng::Engine, key::Symbol)
    l = pop!(eng.dev.listeners, key, nothing)
    l === nothing || off(l)
    return nothing
end

function unlisten_all!(eng::Engine)
    foreach(off, values(eng.dev.listeners))
    empty!(eng.dev.listeners)
    return nothing
end

# ───────────── Run control ─────────────

pause!(eng::Engine) = (eng.state.status[] = :paused; eng)
resume!(eng::Engine) = (eng.state.status[] = :running; eng)

"Pause (if needed) and advance `n` frames, one fixed step each."
function step!(eng::Engine, n::Int = 1)
    eng.state.status[] === :running && pause!(eng)
    eng.dev.pending_steps += n
    return eng
end

function _find_system(eng::Engine, name::Symbol)
    for vec in values(eng.schedule.stages), s in vec
        s.name === name && return s
    end
    error("no system named :$name")
end

"Re-enable a system that fault isolation (or you) switched off."
function enable!(eng::Engine, name::Symbol)
    _find_system(eng, name).enabled = true
    eng.dev.last_error[] = nothing
    return eng
end
disable!(eng::Engine, name::Symbol) = (_find_system(eng, name).enabled = false; eng)

function systems(eng::Engine)
    for st in eng.schedule.order, s in eng.schedule.stages[st]
        println(
            rpad(st, 13),
            rpad(s.name, 24),
            s.enabled ? "on " : "OFF",
            "  ",
            round(s.last_ns / 1e3; digits = 1),
            " µs",
        )
    end
    return nothing
end

# ───────────── Inspection ─────────────

inspect(eng::Engine, e::Entity) = components(eng.world, e)

# ───────────── Snapshots ─────────────
# Serialization's format is not stable across Julia versions; use for same-version restarts.

function _observable_values(x; skip = ())
    out = Dict{Symbol,Any}()
    for f in fieldnames(typeof(x))
        f in skip && continue
        v = getfield(x, f)
        v isa Observable && (out[f] = v[])
    end
    return out
end

function _set_observables!(x, vals)
    for (k, v) in vals
        hasfield(typeof(x), k) || continue
        getfield(x, k)[] = v
    end
end

function snapshot!(eng::Engine, path::AbstractString)
    snap = (;
        version = 1,
        world = eng.world,
        params = _observable_values(eng.params),
        state = _observable_values(eng.state; skip = (:status,)),
        clock = (eng.clock.elapsed, eng.clock.frame),
        resources = Dict{DataType,Any}(
            T => eng.resources.items[T] for T in eng.resources.persist
        ),
    )
    serialize(path, snap)
    return path
end

function restore!(eng::Engine, path::AbstractString)
    snap = deserialize(path)
    w, s = eng.world, snap.world
    w.storages, w.gens, w.alive, w.free, w.n_alive =
        s.storages, s.gens, s.alive, s.free, s.n_alive
    empty!(eng.commands.queue)
    empty!(eng.commands.draining)
    _set_observables!(eng.params, snap.params)
    _set_observables!(eng.state, snap.state)
    eng.clock.elapsed, eng.clock.frame = snap.clock
    for (T, x) in snap.resources
        eng.resources.items[T] = x
        push!(eng.resources.persist, T)
    end
    return eng
end
