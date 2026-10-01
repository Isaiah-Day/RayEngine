mutable struct Screen
    width::Signed
    height::Signed
    title::String

    keyboard::Observable{Keyboard}
    theme::Theme

    objects::Vector{Drawable}

    function Screen(;width=800, height=800, title="RayEngine", keyboard=Keyboard(), theme=Theme())
        s = new(width, height, title, keyboard, theme, [])
        Raylib.InitWindow(s.width, s.height, s.title)
        return s
    end
end

function clear!(s::Screen)
    s.objects = []
end