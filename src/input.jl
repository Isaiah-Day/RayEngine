# Polled once per frame into a plain struct. Systems read it, never Raylib directly.

const NKEYS = 350
const NBUTTONS = 7

mutable struct InputState
    down::BitVector
    pressed::BitVector
    released::BitVector
    fixed_pressed::BitVector     # edges latched until a fixed step consumes them
    mouse_pos::NTuple{2,Float32}
    mouse_delta::NTuple{2,Float32}
    wheel::Float32
    mouse_down::BitVector
    mouse_pressed::BitVector
    mouse_released::BitVector
end

InputState() = InputState(
    falses(NKEYS),
    falses(NKEYS),
    falses(NKEYS),
    falses(NKEYS),
    (0.0f0, 0.0f0),
    (0.0f0, 0.0f0),
    0.0f0,
    falses(NBUTTONS),
    falses(NBUTTONS),
    falses(NBUTTONS),
)

function poll_input!(inp::InputState)
    for k = 0:(NKEYS-1)
        i = k + 1
        inp.down[i] = Raylib.IsKeyDown(k)
        inp.pressed[i] = Raylib.IsKeyPressed(k)
        inp.released[i] = Raylib.IsKeyReleased(k)
    end
    inp.fixed_pressed .|= inp.pressed

    m = Raylib.GetMousePosition()
    inp.mouse_pos = (Float32(m.x), Float32(m.y))
    d = Raylib.GetMouseDelta()
    inp.mouse_delta = (Float32(d.x), Float32(d.y))
    inp.wheel = Float32(Raylib.GetMouseWheelMove())
    for b = 0:(NBUTTONS-1)
        inp.mouse_down[b+1] = Raylib.IsMouseButtonDown(b)
        inp.mouse_pressed[b+1] = Raylib.IsMouseButtonPressed(b)
        inp.mouse_released[b+1] = Raylib.IsMouseButtonReleased(b)
    end
    return nothing
end

# Accessors hide the 0→1 index shift. `k` may be a Raylib key constant or an Int.
key_down(i::InputState, k) = i.down[Int(k)+1]
key_pressed(i::InputState, k) = i.pressed[Int(k)+1]
key_released(i::InputState, k) = i.released[Int(k)+1]
key_pressed_fixed(i::InputState, k) = i.fixed_pressed[Int(k)+1]   # use inside :fixed_update
button_down(i::InputState, b) = i.mouse_down[Int(b)+1]
button_pressed(i::InputState, b) = i.mouse_pressed[Int(b)+1]
button_released(i::InputState, b) = i.mouse_released[Int(b)+1]
axis(i::InputState, neg, pos) = Float32(key_down(i, pos)) - Float32(key_down(i, neg))

"Fake a key press (tests, input replay)."
function press!(i::InputState, k)
    n = Int(k) + 1
    i.down[n] = true
    i.pressed[n] = true
    i.fixed_pressed[n] = true
    return i
end
