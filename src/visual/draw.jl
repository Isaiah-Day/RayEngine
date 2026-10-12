using FixedPointNumbers


function draw(d::Rect)
    x = Int(round(min(d.pos1[1], d.pos2[1])))
    y = Int(round(min(d.pos1[2], d.pos2[2])))
    w = Int(round(abs(d.pos1[1] - d.pos2[1])))
    h = Int(round(abs(d.pos1[2] - d.pos2[2])))

    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawRectangle(x, y, w, h, fill)

    if !isnothing(d.style.stroke)
        line = Raylib.Fade(convert(RGBA{N0f8}, d.style.stroke), d.style.alpha)
        rec = Raylib.RayRectangle(Float32(x), Float32(y), Float32(w), Float32(h))
        Raylib.DrawRectangleLinesEx(rec, d.style.strokewidth, line)
    end
end




function draw(d::Circle)
    cx = Int(round(d.center[1]))
    cy = Int(round(d.center[2]))

    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawCircle(cx, cy, d.radius, fill)
    if !isnothing(d.style.stroke)
        line = Raylib.Fade(convert(RGBA{N0f8}, d.style.stroke), d.style.alpha)
        Raylib.DrawCircleLines(cx, cy, d.radius, line)
    end
end


function draw(d::Line)
    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawLineEx(
        Raylib.RayVector2(Float32(d.pos1[1]), Float32(d.pos1[2])),
        Raylib.RayVector2(Float32(d.pos2[1]), Float32(d.pos2[2])),
        d.width,
        fill,
    )

    if !isnothing(d.style.stroke)
        @warn "Line.style.stroke is not `nothing`. Ignoring: `Line` cannot have stroke."
    end
end


function draw(d::Text)
    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawText(d.text, d.pos[1], d.pos[2], d.size, fill)
end


function draw(p::Pixel)
    fill = Raylib.Fade(convert(RGBA{N0f8}, p.style.color), p.style.alpha)
    Raylib.DrawPixel(p.pos[1], p.pos[2], fill)

    if !isnothing(p.style.stroke)
        @warn "Pixel.style.stroke is not `nothing`. Ignoring: `Pixel` cannot have stroke."
    end
end


function draw(s::LinearSpline)
    isempty(s.points) && return
    pts = [Raylib.RayVector2(Float32(p[1]), Float32(p[2])) for p in s.points]

    fill = Raylib.Fade(convert(RGBA{N0f8}, s.style.color), s.style.alpha)
    for i in 1:(length(pts) - 1)
        Raylib.DrawLineEx(pts[i], pts[i + 1], s.width, fill)
    end

    if !isnothing(s.style.stroke)
        @warn "LinearSpline.style.stroke is not `nothing`. Ignoring: `LinearSpline` cannot have stroke."
    end
end


function draw(b::BezierSpline)
    fill = Raylib.Fade(convert(RGBA{N0f8}, b.style.color), b.style.alpha)
    Raylib.DrawLineBezier(
        Raylib.RayVector2(Float32(b.pos1[1]), Float32(b.pos1[2])),
        Raylib.RayVector2(Float32(b.pos2[1]), Float32(b.pos2[2])),
        b.width,
        fill,
    )

    if !isnothing(b.style.stroke)
        @warn "BezierSpline.style.stroke is not `nothing`. Ignoring: `BezierSpline` cannot have stroke."
    end
end


function draw(e::Ellipse)
    cx = Int(round(e.center[1]))
    cy = Int(round(e.center[2]))

    fill = Raylib.Fade(convert(RGBA{N0f8}, e.style.color), e.style.alpha)
    Raylib.DrawEllipse(cx, cy, e.radius_h, e.radius_v, fill)
    if !isnothing(e.style.stroke)
        line = Raylib.Fade(convert(RGBA{N0f8}, e.style.stroke), e.style.alpha)
        Raylib.DrawEllipseLines(cx, cy, e.radius_h, e.radius_v, line)
    end
end


function draw(t::Triangle)
    v1 = Raylib.RayVector2(Float32(t.v1[1]), Float32(t.v1[2]))
    v2 = Raylib.RayVector2(Float32(t.v2[1]), Float32(t.v2[2]))
    v3 = Raylib.RayVector2(Float32(t.v3[1]), Float32(t.v3[2]))

    fill = Raylib.Fade(convert(RGBA{N0f8}, t.style.color), t.style.alpha)
    Raylib.DrawTriangle(v1, v2, v3, fill)
    if !isnothing(t.style.stroke)
        line = Raylib.Fade(convert(RGBA{N0f8}, t.style.stroke), t.style.alpha)
        Raylib.DrawTriangleLines(v1, v2, v3, line)
    end
end