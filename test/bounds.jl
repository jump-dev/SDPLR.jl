# Copyright (c) 2017: Benoît Legat and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module TestBounds

using Test
import SDPLR
import MathOptInterface as MOI

const PATAKI = [
    1 1 1 1 1 1 1
    1 1 1 1 1 1 1
    2 2 2 2 2 2 2
    2 2 2 2 2 2 2
    2 2 2 2 2 2 2
    3 3 3 3 3 3 3
    3 3 3 3 3 3 3
]
const BARVINOK = [
    1 1 1 1 1 1 1
    1 1 1 1 1 1 1
    2 2 1 1 1 1 1
    2 2 2 2 2 2 2
    2 2 2 2 2 2 2
    3 3 3 2 2 2 2
    3 3 3 3 3 3 3
]
const DEFAULT_MAXRANK = [
    1 2 2 2 2 2 2
    1 2 3 3 3 3 3
    1 2 3 3 3 3 3
    1 2 3 3 3 3 3
    1 2 3 4 4 4 4
    1 2 3 4 4 4 4
    1 2 3 4 4 4 4
]

τ(r) = MOI.dimension(MOI.PositiveSemidefiniteConeTriangle(r))

function test_bounds()
    for m in 1:7
        for n in 1:7
            @test SDPLR.pataki(m, n) == PATAKI[m, n]
            @test SDPLR.barvinok(m, n) == BARVINOK[m, n]
            @test SDPLR.default_maxrank(m, n) == DEFAULT_MAXRANK[m, n]
        end
    end
    for m in 1:100
        @test isqrt(2m) ==
              MOI.Utilities.side_dimension_for_vectorized_dimension(m)
        @test isqrt(2m) - 1 <= SDPLR.pataki(m)
        @test isqrt(2m) - 1 <= SDPLR.pataki(m + 1)
        @test SDPLR.pataki(m) <= isqrt(2m)
        @test SDPLR.pataki(m + 1) <= isqrt(2m)
        r = SDPLR.pataki(m)
        @test τ(r) ≤ m
        @test τ(r + 1) > m
    end
    for m in 1:10
        for n in 1:10
            @test min(SDPLR.pataki(m, n) + 1, n) ==
                  min(SDPLR.barvinok(m + 1, n) + 1, n)
        end
    end
    return
end

function runtests()
    for name in names(@__MODULE__; all = true)
        if startswith("$(name)", "test_")
            @testset "$(name)" begin
                getfield(@__MODULE__, name)()
            end
        end
    end
    return
end

end  # module

TestBounds.runtests()
