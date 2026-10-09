using FixedPointNumbers


function draw(d::Rect)
    x = min(d.pos1[1], d.pos2[1])
    y = min(d.pos1[2], d.pos2[2])
    w = abs(d.pos1[1] - d.pos2[1])
    h = abs(d.pos1[2] - d.pos2[2])

    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawRectangle(x, y, w, h, fill)

    if !isnothing(d.style.stroke)
        line = Raylib.Fade(convert(RGBA{N0f8}, d.style.stroke), d.style.alpha)
        rec = Raylib.RayRectangle(Float32(x), Float32(y), Float32(w), Float32(h))
        Raylib.DrawRectangleLinesEx(rec, d.style.strokewidth, line)
    end
end




function draw(d::Circle)
    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawCircle(d.center[1], d.center[2], d.radius, fill)
    if !isnothing(d.style.stroke)
        line = Raylib.Fade(convert(RGBA{N0f8}, d.style.stroke), d.style.alpha)
        circle = Raylib.DrawCircleLines(d.center[1], d.center[2], d.radius, fill)
    end
end


function draw(d::Line)
    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawLine(d.pos1[1], d.pos1[2], d.pos2[1], d.pos2[2], fill)

    if !isnothing(d.style.stroke)
        @warn "Line.style.stroke is not `nothing`. Ignoring: `Line` cannot have stroke."
    end
    @warn "Line"

end