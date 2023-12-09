module TestBounds

using Test
import SDPLR

using DataFrames

function test_bounds()
    pataki = [
        1  1  1  1  1  1  1
        1  1  1  1  1  1  1
        1  2  2  2  2  2  2
        1  2  2  2  2  2  2
        1  2  2  2  2  2  2
        1  2  3  3  3  3  3
        1  2  3  3  3  3  3
    ]
    barvinok = [
        1  1  1  1  1  1  1
        1  1  1  1  1  1  1
        1  2  1  1  1  1  1
        1  2  2  2  2  2  2
        1  2  2  2  2  2  2
        1  2  3  2  2  2  2
        1  2  3  3  3  3  3
    ]
    default_maxrank = [
        1  2  2  2  2  2  2
        1  2  3  3  3  3  3
        1  2  3  3  3  3  3
        1  2  3  3  3  3  3
        1  2  3  4  4  4  4
        1  2  3  4  4  4  4
        1  2  3  4  4  4  4
    ]
    for m in 1:7
        for n in 1:7
            @test SDPLR.pataki(m, n) == pataki[m, n]
            @test SDPLR.barvinok(m, n) == barvinok[m, n]
            @test SDPLR.default_maxrank(m, n) == default_maxrank[m, n]
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
