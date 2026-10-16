# GLSL version raylib compiles against on the desktop GL 3.3 core profile.
const GLSL_VERSION = 330

# raylib's default vertex shader (see rlgl.h, GRAPHICS_API_OPENGL_33). 
# Used because null values are not accepted for shaders.
const DEFAULT_VERTEX_SHADER = "#version 330\n" *
    "in vec3 vertexPosition;\n" *
    "in vec2 vertexTexCoord;\n" *
    "in vec4 vertexColor;\n" *
    "out vec2 fragTexCoord;\n" *
    "out vec4 fragColor;\n" *
    "uniform mat4 mvp;\n" *
    "void main() {\n" *
    "    fragTexCoord = vertexTexCoord;\n" *
    "    fragColor = vertexColor;\n" *
    "    gl_Position = mvp*vec4(vertexPosition, 1.0);\n" *
    "}\n"


struct ShaderValueRef <: Ref{Nothing}
    ptr::Ptr{Nothing}
end
Base.unsafe_convert(::Type{Ptr{Nothing}}, r::ShaderValueRef) = r.ptr

# Compiled shaders are tracked so they can be unloaded while the GL context is still
# alive.
const _SHADERS = Set{Shader}()
const _WHITE_TEXTURE = Ref{Union{Nothing,Raylib.RayTexture}}(nothing)


"Prepend an explicit `#version` when the source does not bring its own."
function _with_version(src::AbstractString)
    return occursin(r"^\s*#version", src) ? String(src) : "#version $(GLSL_VERSION)\n" * src
end


"A 1x1 white texture, created on first use; stretched over a shape to get 0..1 UVs."
function white_texture()
    tex = _WHITE_TEXTURE[]
    if isnothing(tex)
        img = Raylib.GenImageColor(1, 1, convert(RGBA{N0f8}, colorant"white"))
        tex = Raylib.LoadTextureFromImage(img)
        Raylib.UnloadImage(img)
        _WHITE_TEXTURE[] = tex
    end
    return tex::Raylib.RayTexture
end


"Compile `sh` (or recompile it after a source/mtime change) and return its handle."
function compile!(sh::Shader)
    src = sh.is_path ? read(sh.frag, String) : sh.frag
    vert = isempty(sh.vert) ? DEFAULT_VERTEX_SHADER : sh.vert

    old = sh.handle
    !isnothing(old) && try
        Raylib.UnloadShader(old)
    catch
    end

    handle = Raylib.LoadShaderFromMemory(_with_version(vert), _with_version(src))
    # raylib 4.0 has no `IsShaderReady`; on a compile error it silently falls back to its
    # default shader and logs a warning, so a nonzero id is all we can check.
    if handle.id == 0
        error("shader failed to compile (raylib returned no program)")
    end

    sh.handle = handle
    empty!(sh.locs)
    push!(_SHADERS, sh)
    if sh.is_path
        sh.mtime = mtime(sh.frag)
    end
    return handle
end


"Return a compiled handle for `sh`, recompiling if the source has since changed."
function shader_handle(sh::Shader)
    if isnothing(sh.handle)
        return compile!(sh)
    end
    if sh.is_path
        try
            mtime(sh.frag) != sh.mtime && return compile!(sh)
        catch
        end
    end
    return sh.handle
end


"Map a Julia uniform value to `(uniformType, payload)` for `SetShaderValue`."
function shader_uniform_data(v)
    if v isa Color
        c = convert(RGBA{N0f8}, v)
        return (Cint(Raylib.SHADER_UNIFORM_VEC4), (Float32(c.r), Float32(c.g), Float32(c.b), Float32(c.alpha)))
    elseif v isa Bool
        return (Cint(Raylib.SHADER_UNIFORM_INT), Cint(v))
    elseif v isa Integer
        return (Cint(Raylib.SHADER_UNIFORM_INT), Cint(v))
    elseif v isa Real
        return (Cint(Raylib.SHADER_UNIFORM_FLOAT), Float32(v))
    end

    t = Tuple(v)
    n = length(t)
    1 <= n <= 4 || error("shader uniforms support tuples/vectors of 1-4 elements, got $n")
    if all(x -> x isa Integer, t)
        data = ntuple(i -> Cint(t[i]), n)
        types = (
            Raylib.SHADER_UNIFORM_INT,
            Raylib.SHADER_UNIFORM_IVEC2,
            Raylib.SHADER_UNIFORM_IVEC3,
            Raylib.SHADER_UNIFORM_IVEC4,
        )
        return (Cint(types[n]), data)
    end
    data = ntuple(i -> Float32(t[i]), n)
    types = (
        Raylib.SHADER_UNIFORM_FLOAT,
        Raylib.SHADER_UNIFORM_VEC2,
        Raylib.SHADER_UNIFORM_VEC3,
        Raylib.SHADER_UNIFORM_VEC4,
    )
    return (Cint(types[n]), data)
end


function _upload_uniform(handle, loc::Integer, value)
    utype, data = shader_uniform_data(value)
    ref = Ref(data)
    GC.@preserve data ref begin
        ptr = Ptr{Nothing}(Base.unsafe_convert(Ptr{typeof(data)}, ref))
        Raylib.SetShaderValue(handle, Cint(loc), ShaderValueRef(ptr), utype)
    end
    return nothing
end


"Cached `GetShaderLocation`; missing uniforms resolve to -1 and are skipped."
function uniform_location(sh::Shader, handle, name::Symbol)
    haskey(sh.locs, name) && return sh.locs[name]
    loc = Cint(Raylib.GetShaderLocation(handle, String(name)))
    sh.locs[name] = loc
    return loc
end


"Upload built-ins + user uniforms, then run `f()` with the shader bound."
function with_shader(f, sh::Shader; size::Tuple = (0.0, 0.0))
    handle = shader_handle(sh)

    builtins = (
        :u_time => Float32(Raylib.GetTime()),
        :u_size => (Float32(size[1]), Float32(size[2])),
    )
    for (name, value) in builtins
        haskey(sh.uniforms, name) && continue      # an explicit value wins
        loc = uniform_location(sh, handle, name)
        loc >= 0 && _upload_uniform(handle, loc, value)
    end
    for (name, value) in sh.uniforms
        loc = uniform_location(sh, handle, name)
        loc >= 0 || continue
        _upload_uniform(handle, loc, value)
    end

    Raylib.BeginShaderMode(handle)
    try
        return f()
    finally
        Raylib.EndShaderMode()
    end
end


"Unload every compiled shader and the shared white texture. Call while the window lives."
function unload_all_shaders!()
    for sh in _SHADERS
        h = sh.handle
        if !isnothing(h)
            try
                Raylib.UnloadShader(h)
            catch
            end
            sh.handle = nothing
            empty!(sh.locs)
        end
    end
    empty!(_SHADERS)

    tex = _WHITE_TEXTURE[]
    if !isnothing(tex)
        try
            Raylib.UnloadTexture(tex)
        catch
        end
        _WHITE_TEXTURE[] = nothing
    end
    return nothing
end
