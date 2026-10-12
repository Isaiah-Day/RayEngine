# RayEngine headless test suite.
# Drives simulate! / the ECS / input / resources / bus only — never opens a window.

using Test
using RayEngine
using Observables
using Colors
import Raylib

# ───────────────────────── Fixtures ─────────────────────────

mutable struct TPos
    x::Float64
end

mutable struct TVel
    dx::Float64
end

struct TTag end

mutable struct TCounter
    n::Float64
end

mutable struct TRes
    n::Int
end

struct TParams
    show_debug::Observable{Bool}
end

struct TState
    status::Observable{Symbol}
    scene::Observable{Symbol}
end

# Systems (named, top-level, so nameof() is meaningful and Revise can hot-reload)

function sys_move!(eng, dt)
    each(eng.world, TPos, TVel) do e, p, v
        p.x += v.dx * dt
    end
end

function sys_fixed_count!(eng, dt)
    resource(eng.resources, TCounter).n += 1
end

function sys_update_count!(eng, dt)
    resource(eng.resources, TCounter).n += 10
end

function sys_res_count!(eng, dt)
    resource(eng.resources, TRes).n += 1
end

function sys_boom!(eng, dt)
    error("boom")
end

function sys_unpause!(eng, dt)
    if key_pressed(eng.input, 80)          # :P
        resume!(eng)
    end
end

function sys_goto!(eng, dt)
    goto_scene!(eng, :towers)
end

function sys_fixed_latch!(eng, dt)
    if key_pressed_fixed(eng.input, 65)
        resource(eng.resources, TCounter).n += 1
    end
end

mutable struct SpawnRec
    e::Any
end

function sys_spawn!(eng, dt)
    rec = resource(eng.resources, SpawnRec)
    rec.e = spawn!(eng.commands, eng.world, TPos(2.0))
end

function RayEngine.load_scene!(eng::RayEngine.Engine, ::Val{:towers})
    spawn!(eng.world, TPos(1.0))
    spawn!(eng.world, TPos(2.0))
end

"Headless engine with fixture types; stages are zero-arg functions returning tuples."
function make_engine(;
    fixed = (),
    update = (),
    input = (),
    render = (),
    overlay = (),
    config = EngineConfig(fixed_dt = 0.1),
)
    eng = Engine(
        TParams(Observable(false)),
        TState(Observable(:running), Observable(:none));
        config = config,
        input = () -> input,
        fixed_update = () -> fixed,
        update = () -> update,
        render = () -> render,
        overlay = () -> overlay,
    )
    set_resource!(eng.resources, TCounter(0.0))
    set_resource!(eng.resources, TRes(0))
    return eng
end

cnt(eng) = resource(eng.resources, TCounter).n
rcnt(eng) = resource(eng.resources, TRes).n

# ───────────────────────── Tests ─────────────────────────

@testset "RayEngine" begin

@testset "ECS" begin
    w = World()
    @test entity_count(w) == 0

    e1 = spawn!(w, TPos(1.0), TVel(2.0))
    e2 = spawn!(w, TPos(3.0))
    @test entity_count(w) == 2
    @test is_alive(w, e1) && is_alive(w, e2)
    @test get_component(w, e1, TPos).x == 1.0
    @test get_component(w, e1, TVel).dx == 2.0
    @test has_component(w, e1, TPos)
    @test !has_component(w, e1, TTag)
    @test get_component(w, e2, TVel) === nothing

    # replace component in place
    add!(w, e1, TPos(9.0))
    @test get_component(w, e1, TPos).x == 9.0

    # 1-type query
    n = Ref(0)
    each(w, TPos) do e, p
        n[] += 1
        @test p isa TPos
    end
    @test n[] == 2

    # 2-type query skips entities missing the second component
    n2 = Ref(0)
    each(w, TPos, TVel) do e, p, v
        n2[] += 1
    end
    @test n2[] == 1

    # 3-type query
    spawn!(w, TPos(5.0), TVel(1.0), TTag())
    n3 = Ref(0)
    each(w, TPos, TVel, TTag) do e, p, v, t
        n3[] += 1
    end
    @test n3[] == 1

    # query can mutate in place
    each(w, TPos) do e, p
        p.x += 1.0
    end
    @test get_component(w, e2, TPos).x == 4.0

    # swap-remove keeps the rest intact
    remove!(w, e2, TPos)
    @test !has_component(w, e2, TPos)
    @test entity_count(w) == 3
    each(w, TPos) do e, p
        @test p.x != 3.0
    end

    # despawn bumps the generation: stale handles die
    @test is_alive(w, e1)
    @test despawn!(w, e1)
    @test !is_alive(w, e1)
    @test !despawn!(w, e1)              # already gone
    @test entity_count(w) == 2

    # free ids are recycled with a higher generation
    es = [spawn!(w, TPos(1.0)) for _ in 1:2]
    RayEngine.clear!(w)
    @test entity_count(w) == 0
    @test all(e -> !is_alive(w, e), es)
    new = spawn!(w, TPos(1.0))
    @test is_alive(w, new)
    @test new.gen > 1
    @test all(e -> !is_alive(w, e), es)   # old handles stay invalid after recycle

    # spawning with no components is legal
    bare = spawn!(w)
    @test is_alive(w, bare)
    @test get_component(w, bare, TPos) === nothing

    # components() lists what an entity has; bad id gives empty
    e = spawn!(w, TPos(1.0), TTag())
    comps = components(w, e)
    @test length(comps) == 2
    @test any(c -> first(c) === TPos, comps)
    @test isempty(components(w, Entity(999, 1)))

    # add! on a dead entity throws
    dead = spawn!(w, TPos(1.0))
    despawn!(w, dead)
    @test_throws ArgumentError add!(w, dead, TPos(2.0))
end

@testset "CommandBuffer" begin
    w = World()
    cb = CommandBuffer()

    # spawn! reserves the id now; components land on apply!
    e = spawn!(cb, w, TPos(1.0))
    @test is_alive(w, e)
    @test get_component(w, e, TPos) === nothing
    @test entity_count(w) == 1
    apply!(cb, w)
    @test get_component(w, e, TPos).x == 1.0

    # add!/remove!/despawn! deferred the same way
    add!(cb, e, TVel(2.0))
    apply!(cb, w)
    @test get_component(w, e, TVel).dx == 2.0

    remove!(cb, e, TVel)
    apply!(cb, w)
    @test !has_component(w, e, TVel)

    despawn!(cb, e)
    apply!(cb, w)
    @test !is_alive(w, e)

    # commands queued *during* apply wait for the next apply!
    e1 = spawn!(cb, w)
    push!(cb.queue, w -> (e2 = spawn!(cb, w); despawn!(cb, e2)))
    apply!(cb, w)
    @test entity_count(w) == 2            # e1 landed; e2 reserved but still queued
    apply!(cb, w)                         # e2 spawned then despawned this batch
    @test entity_count(w) == 1

    # empty apply is a no-op
    apply!(cb, w)
    @test entity_count(w) == 1
end

@testset "Resources" begin
    r = Resources()
    @test !has_resource(r, Int)
    set_resource!(r, 42)
    @test has_resource(r, Int)
    @test resource(r, Int) == 42
    @test resource(r, Int) isa Int        # typed access, not Any

    # persist flag
    set_resource!(r, "keep"; persist = true)
    @test String in r.persist
    set_resource!(r, 7)
    @test !(Int in r.persist)
    @test String in r.persist

    # lookup of a missing type errors
    @test_throws KeyError resource(r, Float64)
end

@testset "InputState" begin
    i = InputState()
    @test !key_down(i, 65)
    @test !key_pressed(i, 65)
    @test !key_released(i, 65)

    press!(i, 65)                          # ':A'
    @test key_down(i, 65)
    @test key_pressed(i, 65)
    @test key_pressed_fixed(i, 65)
    @test !key_released(i, 65)

    # axis = pos held − neg held
    @test axis(i, 65, 68) == -1.0f0        # 65 held, 68 not
    @test axis(i, 68, 65) == 1.0f0
    press!(i, 68)
    @test axis(i, 68, 65) == 0.0f0

    # mouse state starts empty
    @test !button_down(i, 0)
    @test i.mouse_pos == (0.0f0, 0.0f0)
    @test i.wheel == 0.0f0

    # Raylib key constants work as indices
    press!(i, Raylib.KEY_SPACE)
    @test key_down(i, Raylib.KEY_SPACE)
end

@testset "Bus and listen!" begin
    b = Bus()
    @test channel(b, Int)[] === nothing
    emit!(b, 5)
    @test channel(b, Int)[] == 5
    emit!(b, 7)                            # same channel reused per type
    @test channel(b, Int)[] == 7
    @test channel(b, Int) === channel(b, Int)

    eng = make_engine()
    n = Ref(0)

    # listen! under a key replaces, never stacks
    listen!(x -> n[] += 1, eng, :k, eng.state.status)
    listen!(x -> n[] += 100, eng, :k, eng.state.status)
    eng.state.status[] = :paused
    @test n[] == 100

    unlisten!(eng, :k)
    eng.state.status[] = :running
    @test n[] == 100

    # unlisten_all! clears every key
    listen!(x -> n[] += 1, eng, :a, eng.state.status)
    listen!(x -> n[] += 1, eng, :b, eng.state.scene)
    unlisten_all!(eng)
    @test isempty(eng.dev.listeners)
    eng.state.status[] = :paused
    @test n[] == 100
end

@testset "Engine: default constructor" begin
    e0 = Engine()
    @test e0.state.status[] == :stopped
    simulate!(e0, 1 / 60)
    @test e0.clock.frame == 1
    @test e0.clock.elapsed ≈ 1 / 60
    @test entity_count(e0.world) == 0
    pause!(e0)
    @test e0.state.status[] == :paused
    resume!(e0)
    @test e0.state.status[] == :running
end

@testset "Engine: simulate!" begin
    # fixed steps: 0.25 s @ 0.1 fixed_dt ⇒ 2 fixed steps, 1 update
    eng = make_engine(fixed = (sys_fixed_count!,), update = (sys_update_count!,))
    simulate!(eng, 0.25)
    @test cnt(eng) == 12                   # 2 × +1 fixed, 1 × +10 update
    @test eng.clock.frame == 1
    @test eng.clock.elapsed ≈ 0.25

    # movement runs per fixed step
    eng = make_engine(fixed = (sys_move!, sys_fixed_count!), update = (sys_update_count!,))
    e = spawn!(eng.world, TPos(0.0), TVel(2.0))
    simulate!(eng, 0.1)
    @test get_component(eng.world, e, TPos).x ≈ 0.2   # 1 fixed step × 0.1 × 2.0

    # zero dt runs nothing
    eng2 = make_engine(fixed = (sys_fixed_count!,))
    simulate!(eng2, 0.0)
    @test cnt(eng2) == 0

    # backlog cap: 1.0 s clamped to max_frame_dt, 5 steps max, accumulator dropped
    eng3 = make_engine(fixed = (sys_fixed_count!,),
                       config = EngineConfig(fixed_dt = 0.01, max_fixed_steps = 5))
    simulate!(eng3, 1.0)
    @test cnt(eng3) == 5
    simulate!(eng3, 0.001)                 # no residual catch-up
    @test cnt(eng3) == 5
end

@testset "Engine: paused and step!" begin
    eng = make_engine(fixed = (sys_fixed_count!,), update = (sys_update_count!,))

    pause!(eng)
    simulate!(eng, 0.5)
    @test cnt(eng) == 0                    # nothing advances while paused
    @test eng.clock.frame == 1

    # input stage still runs while paused (hotkeys can unpause)
    eng2 = make_engine(input = (sys_unpause!,))
    pause!(eng2)
    press!(eng2.input, 80)                 # :P
    simulate!(eng2, 0.1)
    @test eng2.state.status[] == :running

    # step! = exactly one fixed step per simulate!
    eng3 = make_engine(fixed = (sys_fixed_count!,), update = (sys_update_count!,))
    step!(eng3, 3)
    @test eng3.state.status[] == :paused
    simulate!(eng3, 0.0)
    @test cnt(eng3) == 11                  # 1 fixed + 1 update (dt = fixed_dt)
    simulate!(eng3, 0.0)
    simulate!(eng3, 0.0)
    @test cnt(eng3) == 33
    @test eng3.dev.pending_steps == 0
end

@testset "Engine: fixed input latch" begin
    eng = make_engine(fixed = (sys_fixed_latch!,))
    press!(eng.input, 65)
    simulate!(eng, 0.1)                    # one fixed step consumes the edge
    @test cnt(eng) == 1
    simulate!(eng, 0.1)
    @test cnt(eng) == 1                    # latch cleared, no double-count
end

@testset "Engine: fault isolation" begin
    eng = make_engine(update = (sys_res_count!, sys_boom!, sys_res_count!))

    simulate!(eng, 0.1)
    @test rcnt(eng) == 2                   # systems before and after the throw still ran
    @test sys_boom! in eng.disabled
    @test eng.dev.last_error[] !== nothing
    @test eng.state.status[] == :running   # engine keeps running

    # inspection lists the disabled system
    listed = [(st, nameof(f)) for (st, fs) in RayEngine.stage_systems(eng) for f in fs]
    @test (:update, :sys_boom!) in listed

    # enable by name clears the error and the disabled set
    enable!(eng, :sys_boom!)
    @test isempty(eng.disabled)
    @test eng.dev.last_error[] === nothing

    # disable by name
    disable!(eng, :sys_res_count!)
    simulate!(eng, 0.1)
    @test rcnt(eng) == 2                   # both copies skipped
    enable!(eng, :sys_res_count!)
end

@testset "Engine: commands applied between stages" begin
    eng = make_engine(update = (sys_spawn!,))
    rec = SpawnRec(nothing)
    set_resource!(eng.resources, rec)
    @test entity_count(eng.world) == 0
    simulate!(eng, 0.1)
    @test entity_count(eng.world) == 1
    @test is_alive(eng.world, rec.e)
    @test get_component(eng.world, rec.e, TPos).x == 2.0
end

@testset "Engine: render! is headless-safe" begin
    eng = make_engine(render = (sys_res_count!,))
    render!(eng, 1 / 60)
    @test rcnt(eng) == 1
    @test eng.params.show_debug[] == false
end

@testset "Scenes and resets" begin
    eng = make_engine()
    @test eng.state.scene[] == :none

    # scene switch is staged: applied at the start of the next simulate!
    goto_scene!(eng, :towers)
    @test eng.state.scene[] == :none       # not yet
    simulate!(eng, 0.01)
    @test eng.state.scene[] == :towers
    @test entity_count(eng.world) == 2

    # goto_scene! from inside a system
    eng2 = make_engine(update = (sys_goto!,))
    simulate!(eng2, 0.01)                  # system queues the switch
    simulate!(eng2, 0.01)                  # applied
    @test eng2.state.scene[] == :towers
    @test entity_count(eng2.world) == 2

    # reset keeps resources and listeners; world reloads
    set_resource!(eng.resources, 99)
    n = Ref(0)
    listen!(x -> n[] += 1, eng, :st, eng.state.status)
    eng.state.status[] = :paused
    @test n[] == 1
    reset_scene!(eng)
    @test entity_count(eng.world) == 2     # rerun load_scene!
    @test resource(eng.resources, Int) == 99
    @test haskey(eng.dev.listeners, :st)
    eng.state.status[] = :running
    @test n[] == 2

    # unknown scene errors
    eng4 = make_engine()
    eng4.state.scene[] = :nope
    @test_throws ErrorException reset_scene!(eng4)
end

@testset "Snapshots" begin
    mktemp() do path, io
        close(io)
        eng = make_engine()
        set_resource!(eng.resources, "keep"; persist = true)
        set_resource!(eng.resources, 7)
        e = spawn!(eng.world, TPos(3.5), TVel(1.0))
        eng.state.scene[] = :main
        simulate!(eng, 0.05)
        snap_clock = (eng.clock.elapsed, eng.clock.frame)
        @test snapshot!(eng, path) == path

        eng2 = make_engine()
        restore!(eng2, path)
        @test entity_count(eng2.world) == 1
        e2 = entities(eng2.world)[1]
        @test get_component(eng2.world, e2, TPos).x == 3.5
        @test get_component(eng2.world, e2, TVel).dx == 1.0
        @test resource(eng2.resources, String) == "keep"   # persisted
        @test !has_resource(eng2.resources, Int)           # non-persisted
        @test eng2.state.scene[] == :main
        @test eng2.params.show_debug[] == eng.params.show_debug[]
        @test eng2.clock.elapsed == snap_clock[1]
        @test eng2.clock.frame == snap_clock[2]
    end
end

@testset "Visual shapes (headless)" begin
    r = Rect([0, 0], [10, 4])
    @test getPos(Val(:left), r) == 0.0
    @test getPos(Val(:right), r) == 10.0

    c = Circle([5, 5], 2.0)
    @test getPos(Val(:left), c) == 3.0
    @test getPos(Val(:right), c) == 7.0
    @test getPos(Val(:down), c) == 3.0
    @test getPos(Val(:up), c) == 7.0

    l = Line(0, 0, 10, 5, 2.0)
    @test l.width == 2.0
    @test getPos(Val(:left), l) == 0.0
    @test getPos(Val(:right), l) == 10.0
    @test getPos(Val(:down), l) == 0.0
    @test getPos(Val(:up), l) == 5.0

    l2 = Line([1, 2], [3, -4], 1.0 )
    @test getPos(Val(:right), l2) == 3.0
    @test getPos(Val(:down), l2) == -4.0

    p = Pixel([3, 4])
    @test getPos(Val(:left), p) == 3.0
    @test getPos(Val(:right), p) == 3.0
    @test getPos(Val(:down), p) == 4.0
    @test getPos(Val(:up), p) == 4.0
    @test Pixel(1, 2).pos == [1, 2]

    s = LinearSpline([[0, 0], [10, 5], [4, 8]])
    @test s.width == 1.0
    @test getPos(Val(:left), s) == 0.0
    @test getPos(Val(:right), s) == 10.0
    @test getPos(Val(:down), s) == 0.0
    @test getPos(Val(:up), s) == 8.0

    b = BezierSpline([0, 0], [10, 5], 2.0)
    @test b.width == 2.0
    @test getPos(Val(:left), b) == 0.0
    @test getPos(Val(:right), b) == 10.0
    @test getPos(Val(:down), b) == 0.0
    @test getPos(Val(:up), b) == 5.0

    e = Ellipse([5, 5], 3.0, 2.0)
    @test getPos(Val(:left), e) == 2.0
    @test getPos(Val(:right), e) == 8.0
    @test getPos(Val(:down), e) == 3.0
    @test getPos(Val(:up), e) == 7.0

    t = Triangle([0, 0], [10, 0], [5, 8])
    @test getPos(Val(:left), t) == 0.0
    @test getPos(Val(:right), t) == 10.0
    @test getPos(Val(:down), t) == 0.0
    @test getPos(Val(:up), t) == 8.0

    # draw methods exist; they need a live window, so don't call them headless
    @test hasmethod(draw, Tuple{Pixel})
    @test hasmethod(draw, Tuple{LinearSpline})
    @test hasmethod(draw, Tuple{BezierSpline})
    @test hasmethod(draw, Tuple{Ellipse})
    @test hasmethod(draw, Tuple{Triangle})

    @test Style() isa Style
    @test Theme() isa Theme
    @test Style(color = colorant"red", alpha = 0.5) isa Style
end

end # @testset "RayEngine"
