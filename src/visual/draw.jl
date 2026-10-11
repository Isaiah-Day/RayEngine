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
