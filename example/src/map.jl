# map.jl = background.fs in Julia.
#
# sample_field is the shader: pixel (x, y) on a ux×uy rect, snapshot time t
# (= u_shift), zoom (= u_zoom). map([x, y]) is the opening still frame.

"cosRange() from background.fs; amt is in degrees (GLSL radians())."
_cosRange(amt, range, minimum) = ((1.0 + cos(deg2rad(amt))) * 0.5) * range + minimum

"""
    sample_field(x, y, t; ux, uy, zoom) -> NTuple{3,Float64}

Field colour (r, g, b) at pixel (x, y) of a ux×uy rect for snapshot time t.
Defaults match the game: ux/uy = MAP_SIZE, zoom = FIELD_ZOOM_SCALE.
"""
function sample_field(x, y, t; ux = MAP_SIZE[1], uy = MAP_SIZE[2], zoom = FIELD_ZOOM_SCALE)
    fx, fy = Float64(x), Float64(y)

    # fragTexCoord = (x/ux, y/uy); uv = (fragTexCoord - 0.5)*zoom + 0.5; p = 2uv - 1
    uv = ((fx / ux - 0.5) * zoom + 0.5, (fy / uy - 0.5) * zoom + 0.5)
    p = (2.0 * uv[1] - 1.0, 2.0 * uv[2] - 1.0)

    ct = _cosRange(t * 5.0, 3.0, 1.1)
    xBoost = _cosRange(t * 0.2, 5.0, 5.0)
    yBoost = _cosRange(t * 0.1, 10.0, 5.0)
    fScale = _cosRange(t * 15.5, 1.25, 0.5)

    # Wobble loop (iterations = 40); both terms read the old p.
    for i in 1:(FIELD_ITERATIONS - 1)
        _i = Float64(i)
        px = p[1] + 0.25 / _i * sin(_i * p[2] + t * cos(ct) * 0.5 / 20.0 + 0.005 * _i) * fScale + xBoost
        py = p[2] + 0.25 / _i * sin(_i * p[1] + t * ct * 0.3 / 40.0 + 0.03 * Float64(i + 15)) * fScale + yBoost
        p = (px, py)
    end

    # col = vec3(0.5 sin(3p) + 0.5, ...) * brightness, then *= 1.5 * vignette
    col = (0.5 * sin(3.0 * p[1]) + 0.5, 0.5 * sin(3.0 * p[2]) + 0.5, sin(p[1] + p[2]))
    col = (col[1] * 0.975, col[2] * 0.975, col[3] * 0.975)

    vig = 5.0
    vignette = (1.0 - vig * (uv[2] - 0.5)^2) * (1.0 - vig * (uv[1] - 0.5)^2)
    col = (col[1] * 1.5 * vignette, col[2] * 1.5 * vignette, col[3] * 1.5 * vignette)

    # GL clamps to [0, 1]
    return (clamp(col[1], 0.0, 1.0), clamp(col[2], 0.0, 1.0), clamp(col[3], 0.0, 1.0))
end

"""
    map([x, y]) -> RGB{Float64}

Opening still frame at pixel [x, y] (t = FIELD_TIME_OFFSET).
"""
map(p::AbstractVector) = RGB{Float64}(sample_field(p[1], p[2], FIELD_TIME_OFFSET)...)

"""
    field_force(c, gain) -> (ax, ay)

Colour to acceleration: +x green, −x red, −y blue (up).
"""
function field_force(c::Tuple, gain::Real)
    return ((Float64(c[2]) - Float64(c[1])) * gain, (Float64(c[2]) - Float64(c[3])) * gain)
end
function field_force(c::Color, gain::Real)
    return ((Float64(c.g) - Float64(c.r)) * gain, (Float64(c.g) - Float64(c.b)) * gain)
end