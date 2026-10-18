in vec2 fragTexCoord;
out vec4 finalColor;

uniform float u_shift;   // field snapshot time (the game jumps this occasionally)
uniform float u_zoom;    // < 1 magnifies the field inward, away from black edges

float cosRange(float amt, float range, float minimum) {
    return ((1.0 + cos(radians(amt))) * 0.5) * range + minimum;
}

void main() {
    const int iterations = 40;
    const float brightness = 0.975;
    const float vigAmt = 5.0;

    float time = u_shift;
    vec2 uv = (fragTexCoord - 0.5) * u_zoom + 0.5;
    vec2 p = 2.0 * uv - 1.0;

    float ct = cosRange(time * 5.0, 3.0, 1.1);
    float xBoost = cosRange(time * 0.2, 5.0, 5.0);
    float yBoost = cosRange(time * 0.1, 10.0, 5.0);
    float fScale = cosRange(time * 15.5, 1.25, 0.5);

    for (int i = 1; i < iterations; i++) {
        float fi = float(i);
        vec2 next = p;
        next.x += 0.25 / fi * sin(fi * p.y + time * cos(ct) * 0.5 / 20.0 + 0.005 * fi) * fScale + xBoost;
        next.y += 0.25 / fi * sin(fi * p.x + time * ct * 0.3 / 40.0 + 0.03 * float(i + 15)) * fScale + yBoost;
        p = next;
    }

    vec3 col = vec3(
        0.5 * sin(3.0 * p.x) + 0.5,
        0.5 * sin(3.0 * p.y) + 0.5,
        sin(p.x + p.y)
    ) * brightness;

    float vignette = (1.0 - vigAmt * (uv.y - 0.5) * (uv.y - 0.5))
                   * (1.0 - vigAmt * (uv.x - 0.5) * (uv.x - 0.5));
    col *= 1.5 * vignette;

    finalColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
