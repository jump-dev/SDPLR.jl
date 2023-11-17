using Test
import SDPLR
import Random
@testset "Solve simple with sdplrlib" begin
    include("simple.jl")
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
    @test length(R) == 4
    U = reshape(R, 2, 2)
    @test U * U' ≈ ones(2, 2) rtol = 1e-3
    @test lambda ≈ [2.0] atol = 1e-3
    @test ranks == Csize_t[2]
end
