# Components are small mutable data bags (mutable so `each` callbacks can edit in place).
# Changing a struct's fields needs a Julia restart: use snapshot!/restore! to get back fast.

mutable struct Position
    x::Float32
    y::Float32
    px::Float32      # previous fixed-step position, for render interpolation
    py::Float32
end
Position(x::Real, y::Real) = Position(Float32(x), Float32(y), Float32(x), Float32(y))

mutable struct Velocity
    x::Float32
    y::Float32
end
Velocity(x::Real, y::Real) = Velocity(Float32(x), Float32(y))

struct Circle
    radius::Float32
    r::UInt8
    g::UInt8
    b::UInt8
end

struct Player end            # tag component

# Resource: playfield size
struct Arena
    w::Float32
    h::Float32
end

# Bus event
struct Bounce
    entity::Entity
end
