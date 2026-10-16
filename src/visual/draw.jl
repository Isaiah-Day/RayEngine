using FixedPointNumbers


# TEMP: nothing besides rect has shaders rn
function _no_shader(o::Object)
    if !isnothing(o.style.shader)
        @warn "$(nameof(typeof(o))) does not support Style.shader yet; drawing the plain color." maxlog = 1
    end
    return nothing
end


function draw(d::Rect)
    x = Int(round(min(d.pos1[1], d.pos2[1])))
    y = Int(round(min(d.pos1[2], d.pos2[2])))
    w = Int(round(abs(d.pos1[1] - d.pos2[1])))
    h = Int(round(abs(d.pos1[2] - d.pos2[2])))

    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)

    if isnothing(d.style.shader)
        Raylib.DrawRectangle(x, y, w, h, fill)
    else
        # A shape's built-in draw call samples a tiny sliver of raylib's white texture, so
        # `fragTexCoord` would not span the rectangle. Stretching our own 1x1 white texture
        # over it gives clean 0..1 UVs (and keeps rotation possible later).
        with_shader(d.style.shader; size = (Float32(w), Float32(h))) do
            tex = white_texture()
            src = Raylib.RayRectangle(0.0f0, 0.0f0, 1.0f0, 1.0f0)
            dst = Raylib.RayRectangle(Float32(x), Float32(y), Float32(w), Float32(h))
            Raylib.DrawTexturePro(tex, src, dst, Raylib.RayVector2(0.0f0, 0.0f0), 0.0f0, fill)
        end
    end

    if !isnothing(d.style.stroke)
        line = Raylib.Fade(convert(RGBA{N0f8}, d.style.stroke), d.style.alpha)
        rec = Raylib.RayRectangle(Float32(x), Float32(y), Float32(w), Float32(h))
        Raylib.DrawRectangleLinesEx(rec, d.style.strokewidth, line)
    end
end




function draw(d::Circle)
    _no_shader(d)
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
    _no_shader(d)
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
    _no_shader(d)
    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawText(d.text, d.pos[1], d.pos[2], d.size, fill)
end


function draw(p::Pixel)
    _no_shader(p)
    fill = Raylib.Fade(convert(RGBA{N0f8}, p.style.color), p.style.alpha)
    Raylib.DrawPixel(p.pos[1], p.pos[2], fill)

    if !isnothing(p.style.stroke)
        @warn "Pixel.style.stroke is not `nothing`. Ignoring: `Pixel` cannot have stroke."
    end
end


function draw(s::LinearSpline)
    _no_shader(s)
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
    _no_shader(b)
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
    _no_shader(e)
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
    _no_shader(t)
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
