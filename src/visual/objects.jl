abstract type Object end


mutable struct Rect <: Object
    pos1::Vec
    pos2::Vec

    style::Union{Shader,Style}
end



mutable struct Line <: Object
    pos1::Vec
    pos2::Vec

    width::Float32

    style::Union{Shader,Style}

    Line(x1, y1, x2, y2, strokewidth) = new([x1, y1], [x2, y2], width, Style())
    Line(p1, p2, width) = new(p1, p2, width, Style())

end



@kwdef mutable struct Circle <: Object
    center::Vec
    r::Float32

    style::Union{Shader,Style}=Style()

    Circle(center::Vec, r::Float32) = new(center, r, Style())
end



getPos(::Val{:left}, r::Rect) = r.pos1[1]
getPos(::Val{:right}, r::Rect) = r.pos2[1]
getPos(::Val{:down}, r::Rect) = r.pos1[2]
getPos(::Val{:up}, r::Rect) = r.pos1[2]


# Line: bounding edges of the two endpoints.
getPos(::Val{:left}, l::Line) = min(l.pos1[1], l.pos2[1])
getPos(::Val{:right}, l::Line) = max(l.pos1[1], l.pos2[1])
getPos(::Val{:down}, l::Line) = min(l.pos1[2], l.pos2[2])
getPos(::Val{:up}, l::Line) = max(l.pos1[2], l.pos2[2])

# Circle: bounding box around the center.
getPos(::Val{:left}, c::Circle) = c.center[1] - c.r
getPos(::Val{:right}, c::Circle) = c.center[1] + c.r
getPos(::Val{:down}, c::Circle) = c.center[2] - c.r
