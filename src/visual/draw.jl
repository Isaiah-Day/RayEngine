using FixedPointNumbers




function draw!(s::Screen)
    Raylib.BeginDrawing()

    for drawable in s.objects
        _draw!(s, drawable)
    end

    Raylib.EndDrawing()
end


function Base.push!(s::Screen, d::Drawable)
    push!(s.objects, d)
end



function _draw!(s::Screen, d::Rect)
    x = min(d.pos1[1], d.pos2[1])
    y = min(d.pos1[2], d.pos2[2])
    w = abs(d.pos1[1] - d.pos2[1])
    h = abs(d.pos1[2] - d.pos2[2])

    Raylib.BeginDrawing()
    fill = Raylib.Fade(convert(RGBA{N0f8}, d.style.color), d.style.alpha)
    Raylib.DrawRectangle(x, y, w, h, fill)

    if !isnothing(d.style.stroke)
        line = Raylib.Fade(convert(RGBA{N0f8}, d.style.stroke), d.style.alpha)
        rec = Raylib.RayRectangle(Float32(x), Float32(y), Float32(w), Float32(h))
        Raylib.DrawRectangleLinesEx(rec, d.style.strokewidth, line)
    end
    Raylib.EndDrawing()
end


function fill!(s::Screen, c::Color)
    # TODO: fill s
end
