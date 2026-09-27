# Credit goes to GameZero.jl for this incredible design, modified for Char and Observables.jl



struct Keyboard
    pressed::Array{Char,1}
end

Keyboard() = Observable(Keyboard(Array{Char,1}()))



function Base.getproperty(k::Keyboard, s::Symbol)
    sc=only(string(s))
    if sc in 'A':'Z'
        sc = lowercase(sc)
    end
    s=Symbol(sc)
    try
        return # TODO get whether key is down or not
    catch
        @error "Unknown key: $s"
        return nothing
    end
end



# TODO do the same for mouse, probably with an enum
