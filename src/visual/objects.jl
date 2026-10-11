abstract type Object end


mutable struct Rect <: Object
    pos1::Vec
    pos2::Vec

    style::Union{Shader,Style}

    Rect(pos1::Vec, pos2::Vec) = new(pos1, pos2, Style())
end



mutable struct Line <: Object
    pos1::Vec
    pos2::Vec

    width::Float32

    style::Union{Shader,Style}

    Line(x1, y1, x2, y2, strokewidth) = new([x1, y1], [x2, y2], Float32(strokewidth), Style())
    Line(p1, p2, width) = new(p1, p2, Float32(width), Style())

end



@kwdef mutable struct Circle <: Object
    center::Vec
    radius::Float32

    style::Union{Shader,Style}=Style()

    Circle(center::Vec, r::Real) = new(center, Float32(r), Style())
end



getPos(::Val{:left}, r::Rect) = min(r.pos1[1], r.pos2[1])
getPos(::Val{:right}, r::Rect) = max(r.pos1[1], r.pos2[1])
getPos(::Val{:down}, r::Rect) = min(r.pos1[2], r.pos2[2])
getPos(::Val{:up}, r::Rect) = max(r.pos1[2], r.pos2[2])


# Line: bounding edges of the two endpoints.
getPos(::Val{:left}, l::Line) = min(l.pos1[1], l.pos2[1])
getPos(::Val{:right}, l::Line) = max(l.pos1[1], l.pos2[1])
getPos(::Val{:down}, l::Line) = min(l.pos1[2], l.pos2[2])
getPos(::Val{:up}, l::Line) = max(l.pos1[2], l.pos2[2])

# Circle: bounding box around the center.
getPos(::Val{:left}, c::Circle) = c.center[1] - c.radius
getPos(::Val{:right}, c::Circle) = c.center[1] + c.radius
getPos(::Val{:down}, c::Circle) = c.center[2] - c.radius
getPos(::Val{:up}, c::Circle) = c.center[2] + c.radius
