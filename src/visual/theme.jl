"""
    Shader(frag; vert = "", is_path = false, kwargs...)

A fragment shader used as a shape's fill.

`frag` is GLSL source, or a path to a `.fs` file when `is_path = true`. `vert` is the
matching vertex shader source and defaults to the built-in passthrough vertex
shader.

All kwargs become inputs to the shader; `set_uniform!(sh, name, value)` overwrites them.
`u_time` (seconds since the window opened) and `u_size` (the drawn
shape's pixel size) are also given unless the same names are set explicitly.

A `Shader` is just data until it is first drawn.
"""
mutable struct Shader
    vert::String
    frag::String
    is_path::Bool
    uniforms::Dict{Symbol,Any}
    handle::Union{Nothing,Raylib.RayShader}
    locs::Dict{Symbol,Cint}
    version::Int # bumped by set_source! to force a recompile
    mtime::Float64 # last-seen source mtime (path shaders only)
end

function Shader(frag::AbstractString; vert::AbstractString = "", is_path::Bool = false, kwargs...)
    return Shader(
        String(vert),
        String(frag),
        is_path,
        Dict{Symbol,Any}(kwargs),
        nothing,
        Dict{Symbol,Cint}(),
        0,
        0.0,
    )
end

"A `Shader` loaded from a `.fs` file; the file is re-read when its mtime changes."
file_shader(path::AbstractString; kwargs...) =
    Shader(path; is_path = true, kwargs...)

    
"Replace the fragment (and optionally vertex) source, forcing a recompile on next draw."
function set_source!(sh::Shader, frag::AbstractString; vert::AbstractString = sh.vert, is_path::Bool = false)
    sh.frag = String(frag)
    sh.vert = String(vert)
    sh.is_path = is_path
    sh.version += 1
    return sh
end

"""
    set_uniform!(sh, name, value) -> sh

Set (or overwrite) a named uniform. `value` may be `Real`, `Integer`, `Bool`, a
`ColorTypes.Color`, or a tuple/vector of 1–4 `Real`/`Integer`. Floats map to
`float`/`vec2..4`, integers to `int`/`ivec2..4`, and colors to a normalized `vec4`.
"""
function set_uniform!(sh::Shader, name::Symbol, value)
    sh.uniforms[name] = value
    return sh
end

set_uniform!(sh::Shader, pairs::Pair...) = (foreach(p -> set_uniform!(sh, p.first, p.second), pairs); sh)



@kwdef struct Theme
    background::Color=colorant"white"
end


@kwdef struct Style
    color::Color = colorant"black"   # from Colors.jl
    alpha::Number = 1.0
    stroke::Union{Color,Nothing} = nothing
    strokewidth::Number = 0
    shader::Union{Shader,Nothing} = nothing # when set, replaces `color` as the fill
end