# Shaders
## What the engine provides
A `Shader` is data until first drawn:

```julia
sh = file_shader("squares.fs")
sh = Shader("void main() { finalColor = vec4(1.0); }")
```

- `file_shader(path)` re-reads the file when its mtime changes, so edits hot-reload on the next `draw`.
- The engine prepends `#version 330` unless the source starts with its own `#version`.
- These uniforms are uploaded automatically:
  - `u_time :: float`: seconds since the window opened.
  - `u_size :: vec2`: the drawn Rect's size in pixels.


### Fragment

Write a `main()` that reads `fragTexCoord` and writes `finalColor`:

```glsl
in vec2 fragTexCoord;      // 0..1 across the shape
out vec4 finalColor;

uniform float u_time;
uniform vec2 u_size;

void main() {
    finalColor = vec4(fragTexCoord, 0.5, 1.0);
}
```

The default **vertex** shader (raylib's) also outputs a `fragColor` varying carrying
the draw tint. A fragment shader may declare `in vec4 fragColor;` if it wants it, but
the engine treats a set shader as replacing `Style.color`, so most shaders ignore it.

## Shader log

Most of what raylib prints is bookkeeping, not errors.

### `[ID n]`

OpenGL object handles. Shaders compile into shader *objects*, then link into a
*program*:

- `[ID 4] Vertex shader compiled successfully` — the vertex shader object.
- `[ID 5] Failed to compile fragment shader code` — the fragment shader object
  (the real problem).
- `[ID 6] Failed to link shader program` — the program built from 4+5; cannot link
  because 5 is broken.
- `[ID 3]` — raylib's **default shader**, which it falls back to when a custom
  shader fails.

### Why every shader is probed for the same names

raylib compiles against a fixed "default shader interface". After linking it looks
up a hard-coded list of attribute/uniform names and stores their locations (or `-1`).
A custom shader that omits them produces `Failed to find ...` lines — harmless.

Attributes (per-vertex `in` in the vertex shader):

| Name | Meaning |
|---|---|
| `vertexPosition` | object-space vertex position |
| `vertexTexCoord` | primary UV, 0..1 |
| `vertexTexCoord2` | second UV set (lightmaps) |
| `vertexNormal` | surface normal, for lighting |
| `vertexTangent` | tangent, for normal mapping |
| `vertexColor` | per-vertex tint; in 2D this carries the draw tint |

Uniforms:

| Name | Meaning |
|---|---|
| `mvp` | model·view·projection matrix — transforms `vertexPosition` to clip space |
| `matView` / `matProjection` / `matModel` | the separate view, projection, world matrices |
| `matNormal` | normal matrix (inverse-transpose of the model matrix) |
| `colDiffuse` | diffuse/base color; raylib uses it as the draw tint |
| `texture0` | primary `sampler2D` (raylib binds its white texture to unit 0) |
| `texture1`, `texture2` | extra texture units (multi-texture, lightmaps) |

`Shader uniform (texture0) set at location: 0` means the sampler lives at texture
unit 0. Attribute "locations" are vertex-array bind points; uniform "locations" are
program uniform-table indices.




## Porting ShaderToy

Shadertoy sources use `mainImage(out vec4, in vec2)` plus
the `iTime`/`iResolution` globals. Convert them to the interface above:

1. Add the interface and rename the entry point:
   ```glsl
   in vec2 fragTexCoord;
   out vec4 finalColor;
   uniform float u_time;
   uniform vec2 u_size;

   void main() {
       vec2 fragCoord = fragTexCoord * u_size;   // recover pixel coords
       // ...original mainImage body...
       finalColor = vec4(color, 1.0);
   }
   ```
2. `iTime` → `u_time`.
3. `iResolution` → `u_size` (it is `vec2`, not `vec3`; use `u_size.xy` / `u_size.x`).
4. Any `mainImage(out vec4 fragColor, ...)` parameter becomes a local; write to
   `finalColor` instead.

`iMouse`, `iFrame`, `iChannel0..3`, `iDate`, etc. are **not** provided by the engine;
supply them as your own uniforms or constants.

`squares.fs` in the repo root is a worked example: it began as a Shadertoy shader and
now uses `fragTexCoord`/`finalColor`/`u_time`/`u_size`.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Use of undeclared identifier 'iTime'` and a cascade of others | still a Shadertoy source; port it (above) |
| `Failed to link shader program` | a fragment/vertex object failed to compile first; fix that error |
| Shape draws plain color | silent fallback, search the log for `Failed to compile` |
| `Style.shader` ignored | non-`Rect` shapes warn once and fall back to `Style.color` |