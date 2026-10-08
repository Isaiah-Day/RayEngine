# A scene is a loader method. reset_scene!(eng) clears the world and reruns it, keeping
# params, resources and listeners. Edit this, save, then press R (or call reset_scene!(eng)).

function MyEngine.load_scene!(eng, ::Val{:arena})
    arena = resource(eng.resources, Arena)
    rng = resource(eng.resources, Xoshiro)
    spawn!(
        eng,
        Position(arena.w / 2, arena.h - 100),
        Velocity(0, 0),
        Circle(24, 230, 57, 70),
        Player(),
    )
    for _ = 1:5
        spawn!(
            eng,
            Position(arena.w * rand(rng, Float32), 100 + 200 * rand(rng, Float32)),
            Velocity(300 * (rand(rng, Float32) - 0.5f0), 0),
            Circle(12 + 10 * rand(rng, Float32), 60, 120, 220),
        )
    end
    eng.state.score[] = 0
    return nothing
end
