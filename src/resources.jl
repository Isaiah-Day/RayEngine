# Singletons (camera, RNG, asset handles). Separate from World so they survive
# reset_scene! and don't end up in snapshots unless you opt in.

struct Resources
    items::Dict{DataType,Any}
    persist::Set{DataType}      # types included in snapshot!
end
Resources() = Resources(Dict{DataType,Any}(), Set{DataType}())

resource(r::Resources, ::Type{T}) where {T} = r.items[T]::T
has_resource(r::Resources, ::Type{T}) where {T} = haskey(r.items, T)

function set_resource!(r::Resources, x::T; persist::Bool = false) where {T}
    r.items[T] = x
    persist ? push!(r.persist, T) : delete!(r.persist, T)
    return x
end
