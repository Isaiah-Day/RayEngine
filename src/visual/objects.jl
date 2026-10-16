abstract type Object end


mutable struct Rect <: Object
    pos1::Vec
    pos2::Vec

    style::Style
end

Rect(pos1::Vec, pos2::Vec) = Rect(pos1, pos2, Style())

mutable struct Line <: Object
    pos1::Vec
    pos2::Vec

    width::Float32

    style::Style
end

Line(x1::Int, y1::Int, x2::Int, y2::Int, strokewidth) = Line([x1, y1], [x2, y2], Float32(strokewidth), Style())
Line(p1::Vec, p2::Vec, width) = Line(p1, p2, Float32(width), Style())


mutable struct Circle <: Object
    center::Vec
    radius::Float32

    style::Style
end

Circle(center::Vec, r) = Circle(center, Float32(r), Style())



mutable struct Text <: Object
    text::String
    pos::Vec
    size::Int

    style::Style
end

Text(text::String, pos::Vec, size::Int) = Text(text, pos, size, Style())



mutable struct Pixel <: Object
    pos::Vec

    style::Style
end

Pixel(pos::Vec) = Pixel(pos, Style())
Pixel(x::Integer, y::Integer) = Pixel([x, y], Style())


mutable struct LinearSpline <: Object
    points::Vector{Vec}
    width::Float32

    style::Style
end

LinearSpline(points::Vector{Vec}, width=1.0) = LinearSpline(points, Float32(width), Style())



mutable struct BezierSpline <: Object
    pos1::Vec
    pos2::Vec

    width::Float32

    style::Style
end

BezierSpline(x1, y1, x2, y2, strokewidth) = BezierSpline([x1, y1], [x2, y2], Float32(strokewidth), Style())
BezierSpline(p1::Vec, p2::Vec, width) = BezierSpline(p1, p2, Float32(width), Style())


mutable struct Ellipse <: Object
    center::Vec
    radius_h::Float32
    radius_v::Float32

    style::Style
end

Ellipse(center::Vec, radius_h::Real, radius_v::Real) = Ellipse(center, Float32(radius_h), Float32(radius_v), Style())


mutable struct Triangle <: Object
    v1::Vec
    v2::Vec
    v3::Vec

    style::Style
end

Triangle(v1::Vec, v2::Vec, v3::Vec) = Triangle(v1, v2, v3, Style())
Triangle(x1, y1, x2, y2, x3, y3) = Triangle([x1, y1], [x2, y2], [x3, y3], Style())



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

# Pixel: bounding box of the single point.
getPos(::Val{:left}, p::Pixel) = p.pos[1]
getPos(::Val{:right}, p::Pixel) = p.pos[1]
getPos(::Val{:down}, p::Pixel) = p.pos[2]
getPos(::Val{:up}, p::Pixel) = p.pos[2]

# LinearSpline: bounding box of all points.
getPos(::Val{:left}, s::LinearSpline) = minimum(p -> p[1], s.points)
getPos(::Val{:right}, s::LinearSpline) = maximum(p -> p[1], s.points)
getPos(::Val{:down}, s::LinearSpline) = minimum(p -> p[2], s.points)
getPos(::Val{:up}, s::LinearSpline) = maximum(p -> p[2], s.points)

# BezierSpline: bounding edges of the two endpoints
getPos(::Val{:left}, b::BezierSpline) = min(b.pos1[1], b.pos2[1])
getPos(::Val{:right}, b::BezierSpline) = max(b.pos1[1], b.pos2[1])
getPos(::Val{:down}, b::BezierSpline) = min(b.pos1[2], b.pos2[2])
getPos(::Val{:up}, b::BezierSpline) = max(b.pos1[2], b.pos2[2])

# Ellipse: bounding box around the center.
getPos(::Val{:left}, e::Ellipse) = e.center[1] - e.radius_h
getPos(::Val{:right}, e::Ellipse) = e.center[1] + e.radius_h
getPos(::Val{:down}, e::Ellipse) = e.center[2] - e.radius_v
getPos(::Val{:up}, e::Ellipse) = e.center[2] + e.radius_v

# Triangle: bounding box of the three vertices.
getPos(::Val{:left}, t::Triangle) = min(t.v1[1], t.v2[1], t.v3[1])
getPos(::Val{:right}, t::Triangle) = max(t.v1[1], t.v2[1], t.v3[1])
getPos(::Val{:down}, t::Triangle) = min(t.v1[2], t.v2[2], t.v3[2])
getPos(::Val{:up}, t::Triangle) = max(t.v1[2], t.v2[2], t.v3[2])
