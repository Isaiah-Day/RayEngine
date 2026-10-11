using Platfomer

function (@main)(ARGS)    # Julia 1.11+ alternative, see below
    Platformer.run!()
    return 0
end
