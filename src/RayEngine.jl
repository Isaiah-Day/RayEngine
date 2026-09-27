module RayEngine

const TIMER = Ref{Union{Timer,Nothing}}(nothing)

export bind_keyboard, bind_mouse
export Screen, Theme, debug_loop, draw
export Keyboard, Mouse
export Vec
export Style
export Rect, Circle, Line, getPos

using Raylib
using ColorTypes
using Observables
using Colors


const Vec = Array{<:Number,1}

include("theme.jl")
include("input.jl")
include("drawables.jl")

@kwdef struct Screen
    width::Signed=800
    height::Signed=800

    keyboard::Observable{Keyboard}=Keyboard()
    theme::Theme=Theme()
end

include("draw.jl")


function _draw_all_drawables(g::Screen)
    symbols = names(Main; all = true, imported = false)
    @info symbols
    drawables = filter(symbols) do sym
        str = string(sym)
        !startswith(str, '#') &&
            !startswith(str, '@') &&
            sym !== nameof(@__MODULE__) &&
            typeof(getglobal(Main, sym)) <: Drawable
    end

    clear!(g)
    for drawable in drawables
        draw(g, getglobal(Main, drawable))
    end

end


function debug_loop(s; update = 0.2)
    TIMER[] = Timer(update; interval = update) do t
        _draw_all_drawables(s)
    end
end

stop_debug_loop() = (close(TIMER[]); TIMER[] = nothing)




end # module RayEngine
