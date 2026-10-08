### ENTITIES

struct Entity
    id::UInt32
    gen::UInt32
end
Base.show(io::IO, e::Entity) = print(io, "Entity(", e.id, "v", e.gen, ")")

### STORAGE

abstract type AbstractStorage end

"""
One dense `Vector{T}` per component type, plus entity→index map.
Components should be *mutable structs* so `each` callbacks can modify them in place.
"""
mutable struct Storage{T} <: AbstractStorage
    dense::Vector{T}
    owners::Vector{Entity}
    index::Dict{UInt32,Int}
end
Storage{T}() where {T} = Storage{T}(T[], Entity[], Dict{UInt32,Int}())

Base.length(s::Storage) = length(s.dense)
has_entity(s::Storage, e::Entity) = haskey(s.index, e.id)
get_any(s::Storage, e::Entity) = s.dense[s.index[e.id]]
clear_storage!(s::Storage) = (empty!(s.dense); empty!(s.owners); empty!(s.index); nothing)

"Swap-remove: O(1), keeps `dense` packed."
function remove_entity!(s::Storage, e::Entity)::Bool
    i = pop!(s.index, e.id, 0)
    i == 0 && return false
    last = length(s.dense)
    if i != last
        s.dense[i] = s.dense[last]
        moved = s.owners[last]
        s.owners[i] = moved
        s.index[moved.id] = i
    end
    pop!(s.dense)
    pop!(s.owners)
    return true
end

### WORLD

mutable struct World
    storages::Dict{DataType,AbstractStorage}
    gens::Vector{UInt32}      # current generation per id (starts at 1, so gen 0 is never valid)
    alive::Vector{Bool}
    free::Vector{UInt32}      # recycled ids
    n_alive::Int
end
World() = World(Dict{DataType,AbstractStorage}(), UInt32[], Bool[], UInt32[], 0)

# Type-unstable lookup, fixed by the assertion. Callers get a concrete Storage{T}.
storage(w::World, ::Type{T}) where {T} = get!(() -> Storage{T}(), w.storages, T)::Storage{T}

entity_count(w::World) = w.n_alive

"Allocate an id without touching any storage. Reserved entities count as alive."
function reserve!(w::World)
    if isempty(w.free)
        push!(w.gens, UInt32(1))
        push!(w.alive, true)
        id = UInt32(length(w.gens))
    else
        id = pop!(w.free)
        w.alive[id] = true
    end
    w.n_alive += 1
    return Entity(id, w.gens[id])
end

is_alive(w::World, e::Entity) =
    1 <= e.id <= length(w.gens) && w.alive[e.id] && w.gens[e.id] == e.gen

function add!(w::World, e::Entity, c::T) where {T}
    is_alive(w, e) || throw(ArgumentError("entity $e is not alive"))
    s = storage(w, T)
    i = get(s.index, e.id, 0)
    if i == 0
        push!(s.dense, c)
        push!(s.owners, e)
        s.index[e.id] = length(s.dense)
    else
        s.dense[i] = c
    end
    return e
end

function spawn!(w::World, comps...)
    e = reserve!(w)
    for c in comps
        add!(w, e, c)
    end
    return e
end

function remove!(w::World, e::Entity, ::Type{T}) where {T}
    is_alive(w, e) || return false
    s = get(w.storages, T, nothing)
    s === nothing && return false
    return remove_entity!(s::Storage{T}, e)
end

function despawn!(w::World, e::Entity)
    is_alive(w, e) || return false
    for s in values(w.storages)
        remove_entity!(s, e)
    end
    w.alive[e.id] = false
    w.gens[e.id] += UInt32(1)      # invalidates every outstanding handle to this slot
    push!(w.free, e.id)
    w.n_alive -= 1
    return true
end

function get_component(w::World, e::Entity, ::Type{T}) where {T}
    is_alive(w, e) || return nothing
    s = get(w.storages, T, nothing)
    s === nothing && return nothing
    st = s::Storage{T}
    i = get(st.index, e.id, 0)
    return i == 0 ? nothing : st.dense[i]
end
has_component(w::World, e::Entity, ::Type{T}) where {T} = get_component(w, e, T) !== nothing

entities(w::World) =
    [Entity(UInt32(i), w.gens[i]) for i in eachindex(w.alive) if w.alive[i]]

"All components of one entity as `Type => value`."
function components(w::World, e::Entity)
    out = Pair{DataType,Any}[]
    is_alive(w, e) || return out
    for (T, s) in w.storages
        has_entity(s, e) && push!(out, T => get_any(s, e))
    end
    return out
end

"Remove everything. Ids are recycled but generations bump, so stale handles stay invalid."
function clear!(w::World)
    foreach(clear_storage!, values(w.storages))
    for id in eachindex(w.alive)
        if w.alive[id]
            w.alive[id] = false
            w.gens[id] += UInt32(1)
            push!(w.free, UInt32(id))
        end
    end
    w.n_alive = 0
    return w
end

### QUERIES
# Function-barrier style: `f` is specialised per call site.
# Do NOT spawn/despawn/add/remove on the World inside these callbacks; use a
# CommandBuffer (ctx.commands). Mutating components in place is fine.

function each(f, w::World, ::Type{A}) where {A}
    sa = storage(w, A)
    for i = 1:length(sa.dense)
        f(sa.owners[i], sa.dense[i])
    end
    return nothing
end

function each(f, w::World, ::Type{A}, ::Type{B}) where {A,B}
    sa, sb = storage(w, A), storage(w, B)
    for i = 1:length(sa.dense)
        e = sa.owners[i]
        j = get(sb.index, e.id, 0)
        j == 0 && continue
        f(e, sa.dense[i], sb.dense[j])
    end
    return nothing
end

function each(f, w::World, ::Type{A}, ::Type{B}, ::Type{C}) where {A,B,C}
    sa, sb, sc = storage(w, A), storage(w, B), storage(w, C)
    for i = 1:length(sa.dense)
        e = sa.owners[i]
        j = get(sb.index, e.id, 0)
        j == 0 && continue
        k = get(sc.index, e.id, 0)
        k == 0 && continue
        f(e, sa.dense[i], sb.dense[j], sc.dense[k])
    end
    return nothing
end
