using Test
import SDPLR
@testset "Solve vibra with sdplr executable" begin
    SDPLR.solve_sdpa_file("vibra1.dat-s")
end
@testset "Solve vibra with sdplrlib" begin
    ret = SDPLR.solve(
        blksz,
        blktype,
        b,
        CAent,
        CArow,
        CAcol,
        CAinfo_entptr,
        CAinfo_type,
        SDPLR.Parameters(),
        R,
        lambda,
        maxranks,
        ranks,
        pieces,
    )
    @test iszero(ret)
end
