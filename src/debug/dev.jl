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

# ───────────── Systems ─────────────
# Stages are re-read on every call, so these listings always match the current stage tuples.

const STAGE_ORDER = (:input, :fixed_update, :update, :render, :overlay)

"`(stage, systems)` pairs in run order."
stage_systems(eng::Engine) =
    [(st, Base.invokelatest(eng.functions[st])) for st in STAGE_ORDER]

function _find_system(eng::Engine, name::Symbol)
    for (_, fs) in stage_systems(eng), f in fs
        nameof(f) === name && return f
    end
    error("no system named :$name")
end

"Re-enable a system by name (or pass the function object to `enable!`)."
enable!(eng::Engine, name::Symbol) = (enable!(eng, _find_system(eng, name)); eng)

"Switch a system off by function object or name; it stays off until `enable!`."
disable!(eng::Engine, f::Function) = (push!(eng.disabled, f); eng)
disable!(eng::Engine, name::Symbol) = disable!(eng, _find_system(eng, name))

"Print every system in run order with its stage and on/OFF state."
systems(eng::Engine) = systems(stdout, eng)
function systems(io::IO, eng::Engine)
    for (st, fs) in stage_systems(eng), f in fs
        println(
            io,
            rpad(string(st), 13),
            rpad(string(nameof(f)), 24),
            f in eng.disabled ? "OFF" : "on ",
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
