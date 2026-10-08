using Test
using Observables
using RayEngine
using RayEngine: simulate!, overlay_lines, clear!

# ───────────── test fixtures ─────────────
mutable struct TPos; x::Float64; y::Float64; end
mutable struct TVel; x::Float64; y::Float64; end
mutable struct Counter; input::Int; fixed::Int; update::Int; presses::Int; end
mutable struct Boom; armed::Bool; end

Base.@kwdef struct TParams
    gravity::Observable{Float64} = Observable(9.8)
    show_debug::Observable{Bool} = Observable(false)
end
Base.@kwdef struct TState
    status::Observable{Symbol} = Observable(:running)
    scene::Observable{Symbol}  = Observable(:none)
    score::Observable{Int}     = Observable(0)
end

const SYSTEMS = SystemRegistry()

@system :input function t_input!(w::World, ctx)
    resource(ctx, Counter).input += 1
end
@system :fixed_update function t_fixed!(w::World, ctx)
    c = resource(ctx, Counter)
    c.fixed += 1
    key_pressed_fixed(ctx.input, 65) && (c.presses += 1)
end
@system :update function t_update!(w::World, ctx)
    resource(ctx, Counter).update += 1
end
@system :update function t_boom!(w::World, ctx)
    resource(ctx, Boom).armed && error("boom")
end

RayEngine.load_scene!(eng, ::Val{:t_scene}) = (spawn!(eng, TPos(1, 2), TVel(0, 0)); nothing)

function make_engine(; kw...)
    cfg = EngineConfig(; fixed_dt=1/60, max_fixed_steps=5, kw...)
    eng = Engine(TParams(), TState(); config=cfg)
    set_resource!(eng.resources, Counter(0, 0, 0, 0))
    set_resource!(eng.resources, Boom(false))
    install!(eng, SYSTEMS)
    eng
end
counter(eng) = resource(eng.resources, Counter)

# ───────────── ECS ─────────────
@testset "ECS" begin
    w = World()
    a = spawn!(w, TPos(1, 1), TVel(1, 0))
    b = spawn!(w, TPos(2, 2))
    c = spawn!(w, TPos(3, 3), TVel(0, 1))
    @test entity_count(w) == 3
    @test get_component(w, b, TPos).x == 2
    @test get_component(w, b, TVel) === nothing

    n = Ref(0)
    each(w, TPos, TVel) do e, p, v
        n[] += 1
        p.x += v.x                       # in-place mutation
    end
    @test n[] == 2
    @test get_component(w, a, TPos).x == 2

    # swap-remove keeps the index map consistent
    remove!(w, a, TPos)
    @test !has_component(w, a, TPos)
    @test get_component(w, c, TPos).x == 3
    @test get_component(w, b, TPos).x == 2

    # despawn invalidates handles; slots are recycled with a new generation
    @test despawn!(w, b)
    @test !is_alive(w, b)
    @test get_component(w, b, TPos) === nothing
    @test !despawn!(w, b)
    d = spawn!(w, TPos(9, 9))
    @test d.id == b.id && d.gen != b.gen
    @test !is_alive(w, b) && is_alive(w, d)
    @test_throws ArgumentError add!(w, b, TPos(0, 0))

    @test Set(first.(components(w, c))) == Set([TPos, TVel])
    clear!(w)
    @test entity_count(w) == 0 && !is_alive(w, c)
end

# ───────────── Commands ─────────────
@testset "CommandBuffer" begin
    w = World(); cb = CommandBuffer()
    e = spawn!(cb, w, TPos(1, 1), TVel(0, 0))
    @test is_alive(w, e)                              # id reserved immediately
    @test get_component(w, e, TPos) === nothing       # components land at apply time
    add!(cb, e, Counter(0, 0, 0, 0))
    apply!(cb, w)
    @test get_component(w, e, TPos).x == 1
    @test get_component(w, e, Counter) !== nothing

    remove!(cb, e, TVel); despawn!(cb, e); add!(cb, e, TVel(5, 5))   # FIFO; late add is skipped
    apply!(cb, w)
    @test !is_alive(w, e)
    @test get_component(w, e, TVel) === nothing
end

# ───────────── Reactive ─────────────
@testset "Bus and listen!" begin
    eng = make_engine()
    got = Int[]
    for _ in 1:3     # re-running must not stack listeners
        listen!(eng, :t, eng.state.score) do s
            push!(got, s)
        end
    end
    eng.state.score[] = 7
    @test got == [7]
    unlisten!(eng, :t)
    eng.state.score[] = 8
    @test got == [7]

    seen = Any[]
    listen!(eng, :ev, channel(eng.bus, String)) do s
        s === nothing || push!(seen, s)
    end
    emit!(eng.bus, "hit"); emit!(eng.bus, "hit")
    @test seen == ["hit", "hit"]
    unlisten_all!(eng)
    emit!(eng.bus, "x")
    @test length(seen) == 2
end

# ───────────── Loop semantics (headless) ─────────────
@testset "fixed timestep" begin
    eng = make_engine()
    simulate!(eng, 2.5/60)
    c = counter(eng)
    @test c.fixed == 2 && c.update == 1 && c.input == 1
    @test eng.clock.accumulator ≈ 0.5/60 atol=1e-12

    # backlog beyond the cap is dropped, not carried forever
    eng = make_engine()
    simulate!(eng, 1.0)
    @test counter(eng).fixed == 5
    @test eng.clock.accumulator == 0.0
end

@testset "pause and step" begin
    eng = make_engine()
    pause!(eng)
    simulate!(eng, 1/60)
    c = counter(eng)
    @test c.input == 1 && c.fixed == 0 && c.update == 0     # input still runs when paused

    step!(eng, 2)
    simulate!(eng, 1/60); simulate!(eng, 1/60)
    @test c.fixed == 2 && c.update == 2                       # exactly one fixed step per stepped frame
    simulate!(eng, 1/60)
    @test c.fixed == 2                                         # steps used up

    resume!(eng)
    simulate!(eng, 1/60)
    @test c.fixed == 3
    stop!(eng)
end

@testset "fixed-step input latch" begin
    eng = make_engine()
    press!(eng.input, 65)
    simulate!(eng, 0.001)                  # fast frame: no fixed step yet
    @test counter(eng).fixed == 0 && key_pressed_fixed(eng.input, 65)
    simulate!(eng, 2.5/60)                 # two fixed steps: only the first may see the edge
    @test counter(eng).presses == 1
    @test !key_pressed_fixed(eng.input, 65)
end

@testset "fault isolation" begin
    eng = make_engine()
    resource(eng.resources, Boom).armed = true
    @test_logs (:error, r"t_boom!") match_mode=:any simulate!(eng, 1/60)
    @test eng.dev.last_error[] isa CapturedException
    @test !RayEngine._find_system(eng, :t_boom!).enabled
    c = counter(eng).update
    simulate!(eng, 1/60)                                      # keeps going, no new error
    @test counter(eng).update == c + 1                        # t_update! still ran

    resource(eng.resources, Boom).armed = false
    enable!(eng, :t_boom!)
    @test eng.dev.last_error[] === nothing
    simulate!(eng, 1/60)
    @test RayEngine._find_system(eng, :t_boom!).enabled
end

@testset "scenes" begin
    eng = make_engine()
    eng.state.scene[] = :t_scene
    reset_scene!(eng)
    @test entity_count(eng.world) == 1
    reset_scene!(eng)
    @test entity_count(eng.world) == 1
    @test has_resource(eng.resources, Counter)               # resources survive resets

    goto_scene!(eng, :t_scene)                               # deferred to the next frame
    simulate!(eng, 1/60)
    @test entity_count(eng.world) == 1
end

@testset "snapshot / restore" begin
    eng = make_engine()
    set_resource!(eng.resources, TVel(1, 2); persist=true)
    e = spawn!(eng, TPos(5, 6))
    eng.params.gravity[] = 1.6
    eng.state.score[] = 42
    path = tempname()
    snapshot!(eng, path)

    eng.params.gravity[] = 99.0
    eng.state.score[] = 0
    despawn!(eng, e)
    set_resource!(eng.resources, TVel(0, 0); persist=true)
    restore!(eng, path)

    @test eng.params.gravity[] == 1.6
    @test eng.state.score[] == 42
    @test is_alive(eng.world, e) && get_component(eng.world, e, TPos).y == 6
    @test resource(eng.resources, TVel).y == 2
    rm(path)
end

@testset "overlay and systems listing" begin
    eng = make_engine()
    simulate!(eng, 1/60)
    lines = overlay_lines(eng)
    @test any(startswith("entities:"), lines)
    @test any(occursin("t_fixed!", l) for l in lines)
end
