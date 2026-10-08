# Deferred structural changes. Systems record and the engine applies between stages.

mutable struct CommandBuffer
    queue::Vector{Any}       # callables (w::World) -> nothing
    draining::Vector{Any}    # batch being applied; swapped back to reuse allocations
end
CommandBuffer() = CommandBuffer(Any[], Any[])

"Spawn later. The id is reserved NOW so you can use the handle immediately."
function spawn!(cb::CommandBuffer, w::World, comps...)
    e = reserve!(w)
    push!(cb.queue, world -> foreach(c -> add!(world, e, c), comps))
    return e
end

add!(cb::CommandBuffer, e::Entity, c) =
    (push!(cb.queue, w -> is_alive(w, e) && add!(w, e, c)); nothing)

remove!(cb::CommandBuffer, e::Entity, ::Type{T}) where {T} =
    (push!(cb.queue, w -> is_alive(w, e) && remove!(w, e, T)); nothing)

despawn!(cb::CommandBuffer, e::Entity) = (push!(cb.queue, w -> despawn!(w, e)); nothing)

function apply!(cb::CommandBuffer, w::World)
    isempty(cb.queue) && return nothing
    # Swap so commands queued *during* apply wait for the next apply!.
    cb.queue, cb.draining = cb.draining, cb.queue
    for cmd in cb.draining
        try
            cmd(w)
        catch err
            @error "command failed" exception = (err, catch_backtrace())
        end
    end
    empty!(cb.draining)
    return nothing
end
