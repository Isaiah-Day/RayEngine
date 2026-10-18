using Test
using WeirdForce
using RayEngine
using Raylib
using WeirdForce: sample_field, field_force, PlayerBody, Goal,
    FIELD_SHIFT_EVERY, FIELD_TIME_OFFSET

@testset "field sampler" begin
    for (x, y) in ((0.0, 0.0), (640.0, 360.0), (1279.0, 719.0))
        c = sample_field(x, y, 5.0)
        @test all(0.0 <= v <= 1.0 for v in c)
    end

    # `t = 5` is the still frame the original shader shipped with; shifts move it.
    @test sample_field(300, 300, 5.0) == sample_field(300, 300, 5.0)
    @test sample_field(300, 300, 5.0) != sample_field(300, 300, 5.5)

    # R → −x, G → +x, B → −y (up), white hovers.
    @test field_force((1.0, 0.0, 0.0), 100.0)[1] ≈ -100.0
    @test field_force((0.0, 1.0, 0.0), 100.0)[1] ≈ 100.0
    @test field_force((0.0, 0.0, 1.0), 100.0)[2] ≈ -100.0
    @test field_force((1.0, 1.0, 1.0), 100.0) == (0.0, 0.0)
end

@testset "manual thrust is a nudge" begin
    eng = WeirdForce.run!(headless = true, frames = 1)
    pb = get_component(eng.world, eng.state.player, PlayerBody)
    @test eng.params.thrust < eng.params.field_gain

    # W pushes up (negative screen y); S pushes down.
    pb.vel .= 0.0
    fill!(eng.input.down, false)
    eng.input.down[Int(Raylib.KEY_W) + 1] = true
    WeirdForce.player_thrust(eng, 1 / 60)
    @test pb.vel[2] < 0.0
    @test pb.vel[1] == 0.0

    pb.vel .= 0.0
    fill!(eng.input.down, false)
    eng.input.down[Int(Raylib.KEY_S) + 1] = true
    WeirdForce.player_thrust(eng, 1 / 60)
    @test pb.vel[2] > 0.0

    # Diagonals are normalised: no free extra thrust.
    pb.vel .= 0.0
    fill!(eng.input.down, false)
    eng.input.down[Int(Raylib.KEY_W) + 1] = true
    eng.input.down[Int(Raylib.KEY_D) + 1] = true
    WeirdForce.player_thrust(eng, 1 / 60)
    @test hypot(pb.vel[1], pb.vel[2]) ≈ eng.params.thrust / 60

    fill!(eng.input.down, false)
end

@testset "headless run, capture, reset" begin
    eng = WeirdForce.run!(headless = true, frames = 2)
    @test isempty(eng.disabled)
    @test eng.dev.last_error[] === nothing

    pb = get_component(eng.world, eng.state.player, PlayerBody)
    g = get_component(eng.world, eng.state.goal, Goal)
    @test pb !== nothing
    @test g !== nothing
    @test eng.state.captured[] == 0

    # Teleport onto the beacon: one fixed step should capture and advance the tour.
    pb.pos .= g.pos
    simulate!(eng, 1 / 60)
    @test eng.state.captured[] == 1
    @test get_component(eng.world, eng.state.goal, Goal).index == 2
    @test eng.state.message == "BEACON 1 / $(length(eng.params.goals))"

    # R restarts the run (input stage, so it also works while paused).
    press!(eng.input, Raylib.KEY_R)
    simulate!(eng, 1 / 60)
    fill!(eng.input.down, false)
    fill!(eng.input.pressed, false)
    fill!(eng.input.fixed_pressed, false)
    @test eng.state.captured[] == 0
    @test isempty(eng.state.message)
    @test eng.state.field_time == FIELD_TIME_OFFSET
    @test eng.state.shifts == 0
    @test eng.params.shift_every == FIELD_SHIFT_EVERY
    @test get_component(eng.world, eng.state.goal, Goal).index == 1
    @test isempty(eng.disabled)
end

@testset "tour escalation" begin
    eng = WeirdForce.run!(headless = true, frames = 1)
    n = length(eng.params.goals)
    for i in 1:n
        pb = get_component(eng.world, eng.state.player, PlayerBody)
        g = get_component(eng.world, eng.state.goal, Goal)
        pb.pos .= g.pos
        simulate!(eng, 1 / 60)
    end
    @test eng.state.captured[] == n
    @test eng.state.message == "TOUR COMPLETE - THE FIELD QUICKENS"
    @test eng.params.shift_every < FIELD_SHIFT_EVERY
    @test eng.state.shifts >= 1
    @test eng.state.field_time > FIELD_TIME_OFFSET

    # and the next capture begins a fresh tour
    pb = get_component(eng.world, eng.state.player, PlayerBody)
    g = get_component(eng.world, eng.state.goal, Goal)
    @test g.index == 1
    pb.pos .= g.pos
    simulate!(eng, 1 / 60)
    @test eng.state.captured[] == n + 1
    @test eng.state.message == "BEACON 1 / $n"
end

@testset "field shift on a timer" begin
    eng = WeirdForce.run!(headless = true, frames = 1)
    t0 = eng.state.field_time
    @test eng.state.shifts == 0

    for _ in 1:ceil(Int, (eng.params.shift_every + 1.0) * 60)
        simulate!(eng, 1 / 60)
    end

    @test eng.state.shifts >= 1
    @test eng.state.field_time > t0
    @test eng.state.shift_clock > 0.0
    @test isempty(eng.disabled)
end
