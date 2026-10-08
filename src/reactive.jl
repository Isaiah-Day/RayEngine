# Typed event bus: one Observable per event type, created lazily.
# Listeners run synchronously in registration order. Notify from the game thread only.

struct Bus
    channels::Dict{DataType,Observable}
end
Bus() = Bus(Dict{DataType,Observable}())

channel(b::Bus, ::Type{T}) where {T} = get!(
    () -> Observable{Union{T,Nothing}}(nothing),
    b.channels,
    T,
)::Observable{Union{T,Nothing}}

emit!(b::Bus, ev::T) where {T} = (channel(b, T)[] = ev; nothing)
