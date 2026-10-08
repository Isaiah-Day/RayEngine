const STAGES = (:input, :fixed_update, :update, :late_update, :render, :overlay)

mutable struct SystemEntry
    name::Symbol
    f::Any                      # the function object; Revise redefines its methods in place
    stage::Symbol
    enabled::Bool
    run_if::Any                 # nothing or (ctx) -> Bool
    last_ns::UInt64
end

struct Schedule
    stages::Dict{Symbol,Vector{SystemEntry}}
    order::Vector{Symbol}
end
Schedule() = Schedule(
    Dict{Symbol,Vector{SystemEntry}}(s => SystemEntry[] for s in STAGES),
    collect(Symbol, STAGES),
)

# ───────────── Declarative registry, owned by the game module ─────────────
# The game declares `const SYSTEMS = SystemRegistry()` once. Because the registry is
# owned by the game module, registrations made at top level survive precompilation.

struct SystemDef
    name::Symbol
    f::Any
    stage::Symbol
    run_if::Any
end

mutable struct SystemRegistry
    defs::Vector{SystemDef}
end
SystemRegistry() = SystemRegistry(SystemDef[])

function register!(reg::SystemRegistry, name::Symbol, f, stage::Symbol; run_if = nothing)
    stage in STAGES || throw(ArgumentError("unknown stage $stage; expected one of $STAGES"))
    d = SystemDef(name, f, stage, run_if)
    i = findfirst(x -> x.name === name, reg.defs)
    i === nothing ? push!(reg.defs, d) : (reg.defs[i] = d)   # redefinition replaces
    return d
end

function _sysname(sig)
    while sig isa Expr && sig.head in (:where, :(::))
        sig = sig.args[1]
    end
    return sig.args[1]
end

"""
    @system :stage function name(w::World, ctx) ... end

Defines the function and registers it in the calling module's `SYSTEMS` registry.
Systems within a stage run in definition order. Must be a named `function ... end`.
"""
macro system(stage, fdef)
    (fdef isa Expr && fdef.head === :function) ||
        error("@system needs a long-form `function ... end` definition")
    name = _sysname(fdef.args[1])
    quote
        $(esc(fdef))
        register!($(esc(:SYSTEMS)), $(QuoteNode(name)), $(esc(name)), $(esc(stage)))
        $(esc(name))
    end
end

function install!(sch::Schedule, reg::SystemRegistry)
    for d in reg.defs
        for (st, vec) in sch.stages            # drop copies left in other stages
            st === d.stage || filter!(s -> s.name !== d.name, vec)
        end
        vec = sch.stages[d.stage]
        entry = SystemEntry(d.name, d.f, d.stage, true, d.run_if, UInt64(0))
        i = findfirst(s -> s.name === d.name, vec)
        i === nothing ? push!(vec, entry) : (vec[i] = entry)
    end
    return sch
end
