using Test
import SDPLR
import Random
@testset "Solve vibra with sdplr executable" begin
    SDPLR.solve_sdpa_file("vibra1.dat-s")
end
@testset "Solve vibra with sdplrlib" begin
    include("vibra.jl")
    # The `925` seed is taken from SDPLR's `main.c`
    Random.seed!(925)
    ret, R, lambda, ranks, pieces = SDPLR.solve(
        blksz,
        blktype,
        b,
        CAent,
        CArow,
        CAcol,
        CAinfo_entptr,
        CAinfo_type,
    )
    @test iszero(ret)
    @test length(R) == 477
    @test sum(lambda) ≈ -40.8133 rtol = 1e-2
    @test ranks == Csize_t[9, 9, 1]
end
