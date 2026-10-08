@kwdef struct Theme
    background::Color=colorant"white"
end



@kwdef struct Style
    color::Color = colorant"black"   # from Colors.jl
    alpha::Number = 1.0
    stroke::Union{Color,Nothing} = nothing
    strokewidth::Number = 0
end

@kwdef struct Shader
    # NOT IMPLEMENTED, DO NOT IMPLEMENT
end
