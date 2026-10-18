MAP_SIZE = [1280.0, 720.0]

_cosRange(amt::Real, range::Real, minimum::Real) = (((1.0 + cos(deg2rad(amt))) * 0.5) * range) + minimum


function map_color(p::AbstractVector)
    return map(p, MAP_SIZE[1], MAP_SIZE[2])
end

function map_color(p::AbstractVector, ux::Real, uy::Real)
    fx, fy = Float64(p[1]), Float64(p[2])
    ux, uy = Float64(ux), Float64(uy)

    # GLSL: vec2 uv = fragTexCoord;   (fragTexCoord in 0..1 == pixel/size here)
    uv = [fx / ux, fy / uy]

    # GLSL: vec2 p = 2.0*fragTexCoord - 1.0;   (center to -1..1)
    p = [2.0 * uv[1] - 1.0, 2.0 * uv[2] - 1.0]

    # GLSL: float time = 5;   (u_time declared but unused)
    time = 5.0

    ct = _cosRange(time * 5.0, 3.0, 1.1)
    xBoost = _cosRange(time * 0.2, 5.0, 5.0)
    yBoost = _cosRange(time * 0.1, 10.0, 5.0)
    fScale = _cosRange(time * 15.5, 1.25, 0.5)

    # GLSL: for (int i = 1; i < zoom; i++)  (zoom = 40)
    for i in 1:39
        _i = Float64(i)
        # Both terms read the *old* p (GLSL: newp = p; newp.x += ...(uses p.y);
        # newp.y += ...(uses p.x); p = newp;)
        px = p[1] + 0.25 / _i * sin(_i * p[2] + time * cos(ct) * 0.5 / 20.0 + 0.005 * _i) * fScale + xBoost
        py = p[2] + 0.25 / _i * sin(_i * p[1] + time * ct * 0.3 / 40.0 + 0.03 * Float64(i + 15)) * fScale + yBoost
        p = [px, py]
    end

    # GLSL: vec3 col = vec3(0.5*sin(3.0*p.x)+0.5, 0.5*sin(3.0*p.y)+0.5, sin(p.x+p.y));
    #       col *= brightness;   (brightness = 0.975)
    col = [0.5 * sin(3.0 * p[1]) + 0.5, 0.5 * sin(3.0 * p[2]) + 0.5, sin(p[1] + p[2])]
    col = [col[1] * 0.975, col[2] * 0.975, col[3] * 0.975]

    # GLSL: float vigAmt = 5.0;
    #       float vignette = (1.-vigAmt*(uv.y-.5)^2)*(1.-vigAmt*(uv.x-.5)^2);
    #       col *= 1.5 * vignette;
    vig = 5.0
    vignette = (1.0 - vig * (uv[2] - 0.5)^2) * (1.0 - vig * (uv[1] - 0.5)^2)
    col = [col[1] * 1.5 * vignette, col[2] * 1.5 * vignette, col[3] * 1.5 * vignette]

    # GL outputs are clamped to [0, 1] (the .fs's min(col, 255) is a no-op here),
    # and N0f8 conversion throws on out-of-range values, so clamp explicitly.
    return RGB(
        clamp(col[1], 0.0, 1.0),
        clamp(col[2], 0.0, 1.0),
        clamp(col[3], 0.0, 1.0),
    )
end