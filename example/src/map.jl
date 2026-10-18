# CPU port of `background.fs`.
#
# The shader paints the force field; these functions *sample* it, so the physics
# can use exactly the colours the player sees. If you change the GLSL, change
# this file too (and vice versa).
#
# `sample_field` is allocation-free: it is called once per fixed step for the
# player and once per arrow in the debug force grid. Tuning constants live in
# setup.jl, which is included first.

# GLSL: cos(radians(amt)) — `amt` is degrees.
@inline _cosRange(amt::Float64, range::Float64, minimum::Float64) =
    (((1.0 + cos(deg2rad(amt))) * 0.5) * range) + minimum

"""
    sample_field(x, y, t; ux=MAP_SIZE[1], uy=MAP_SIZE[2], zoom=FIELD_ZOOM_SCALE)
        -> (r, g, b)

Fragment `background.fs` evaluated for the pixel `(x, y)` at field snapshot time
`t`. `ux, uy` are the size of the drawn background; `zoom < 1` magnifies the
field and pulls the vignette in with it, keeping the edges live.

Returns linear-ish 0..1 channels. No allocations.
"""
@inline function sample_field(x::Real, y::Real, t::Real;
                              ux::Real = MAP_SIZE[1], uy::Real = MAP_SIZE[2],
                              zoom::Real = FIELD_ZOOM_SCALE)
    uvx = (Float64(x) / Float64(ux) - 0.5) * Float64(zoom) + 0.5
    uvy = (Float64(y) / Float64(uy) - 0.5) * Float64(zoom) + 0.5
    px = 2.0 * uvx - 1.0
    py = 2.0 * uvy - 1.0
    time = Float64(t)

    ct = _cosRange(time * 5.0, 3.0, 1.1)
    xBoost = _cosRange(time * 0.2, 5.0, 5.0)
    yBoost = _cosRange(time * 0.1, 10.0, 5.0)
    fScale = _cosRange(time * 15.5, 1.25, 0.5)

    # Constant parts of the two sine arguments (GLSL recomputes them per i).
    ax = time * cos(ct) * 0.5 / 20.0
    ay = time * ct * 0.3 / 40.0

    @inbounds for i in 1:(FIELD_ITERATIONS - 1)
        fi = Float64(i)
        # Both components read the *old* p (GLSL: newp = p; newp.x += ... p.y; newp.y += ... p.x).
        ox, oy = px, py
        px = ox + 0.25 / fi * sin(fi * oy + ax + 0.005 * fi) * fScale + xBoost
        py = oy + 0.25 / fi * sin(fi * ox + ay + 0.03 * (fi + 15.0)) * fScale + yBoost
    end

    # vec3 col = vec3(0.5*sin(3.0*p.x)+0.5, 0.5*sin(3.0*p.y)+0.5, sin(p.x+p.y));
    # col *= brightness;     brightness = 0.975
    r = (0.5 * sin(3.0 * px) + 0.5) * 0.975
    g = (0.5 * sin(3.0 * py) + 0.5) * 0.975
    b = sin(px + py) * 0.975

    # Vignette: (1-5*(uv.y-.5)^2)*(1-5*(uv.x-.5)^2), then col *= 1.5 * vignette.
    vignette = (1.0 - 5.0 * (uvy - 0.5)^2) * (1.0 - 5.0 * (uvx - 0.5)^2)
    s = 1.5 * vignette
    return (clamp(r * s, 0.0, 1.0), clamp(g * s, 0.0, 1.0), clamp(b * s, 0.0, 1.0))
end

"The colour at pixel `p`; a thin convenience wrapper around `sample_field`."
map_color(p::AbstractVector; t::Real = FIELD_TIME_OFFSET, zoom::Real = FIELD_ZOOM_SCALE,
          ux::Real = MAP_SIZE[1], uy::Real = MAP_SIZE[2]) =
    RGB(sample_field(p[1], p[2], t; ux = ux, uy = uy, zoom = zoom)...)

# ───────────── colour → force ─────────────

"""
    field_force(rgb, gain) -> (ax, ay)

Read a sampled colour as three thrusters:

  * red  pushes **left**   (-x)
  * green pushes **right** (+x)
  * blue pushes **up**     (-y, i.e. negative screen y)

so sideways force is `g - r` and the second component is the screen-down
acceleration `(r + g)/2 - b` (blue therefore gives a negative, upward value).
Consequences worth knowing: white hovers in place, yellow only pushes down,
black (the vignetted corners) is a dead zone. `gain` converts colour units to
pixels/s².
"""
@inline function field_force(c::NTuple{3,<:Real}, gain::Real)
    r, g, b = Float64(c[1]), Float64(c[2]), Float64(c[3])
    return ((g - r) * gain, ((r + g) * 0.5 - b) * gain)
end
