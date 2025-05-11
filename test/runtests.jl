# Copyright (c) 2017: Benoît Legat and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module TestSDPLR

using Test
import LinearAlgebra
import MathOptInterface as MOI
import LowRankOpt as LRO
import Random
import SDPLR

function test_runtests()
    model = MOI.instantiate(
        SDPLR.Optimizer,
        with_bridge_type = Float64,
        with_cache_type = Float64,
    )
    MOI.set(model, MOI.Silent(), true)
    MOI.set(model, MOI.RawOptimizerAttribute("timelim"), 10)
    config = MOI.Test.Config(
        rtol = 1e-1,
        atol = 1e-1,
        exclude = Any[
            MOI.ConstraintBasisStatus,
            MOI.VariableBasisStatus,
            MOI.ObjectiveBound,
            MOI.SolverVersion,
        ],
        optimal_status = MOI.LOCALLY_SOLVED,
    )
    MOI.Test.runtests(
        model,
        config,
        exclude = [
            # Detecting infeasibility or unboundedness not supported
            "INFEAS",
            # These three are unbounded even if it's not in the name
            r"test_conic_SecondOrderCone_negative_post_bound_2$",
            r"test_conic_SecondOrderCone_negative_post_bound_3$",
            r"test_conic_SecondOrderCone_no_initial_bound$",
            # Incorrect `ConstraintDual` for `vc2` for MacOS in CI
            r"test_linear_integration$",
        ],
    )
    return
end

function test_LRO_runtests()
    T = Float64
    model = MOI.instantiate(
        SDPLR.Optimizer,
        with_bridge_type = T,
        with_cache_type = T,
    )
    LRO.Bridges.add_all_bridges(model, T)
    MOI.set(model, MOI.Silent(), true)
    MOI.set(model, MOI.RawOptimizerAttribute("timelim"), 10)
    config = MOI.Test.Config(
        rtol = 1e-1,
        atol = 1e-1,
        optimal_status = MOI.LOCALLY_SOLVED,
    )
    MOI.Test.runtests(model, config, test_module = LRO.Test)
    return
end

function test_RawOptimizerAttribute_UnsupportedAttribute()
    model = SDPLR.Optimizer()
    attr = MOI.RawOptimizerAttribute("FooBarBaz")
    @test !MOI.supports(model, attr)
    @test_throws MOI.UnsupportedAttribute(attr) MOI.get(model, attr)
    @test_throws MOI.UnsupportedAttribute(attr) MOI.set(model, attr, false)
    return
end

function test_RawOptimizerAttribute_PIECES_MAP_nothing()
    model = SDPLR.Optimizer()
    attr = MOI.RawOptimizerAttribute("lambdaupdate")
    @test MOI.supports(model, attr)
    @test MOI.get(model, attr) === nothing
    @test MOI.set(model, attr, 2.0) === nothing
    @test MOI.get(model, attr) === 2.0
    @test MOI.set(model, attr, nothing) === nothing
    @test MOI.get(model, attr) === nothing
    return
end

function test_Ainfo_entptr_in_mixed_order()
    model = SDPLR.Optimizer()
    # We add these blank constraitns to get empty vectors in .Ainfo_entpr
    f0 = zero(MOI.ScalarAffineFunction{Float64})
    MOI.add_constraint(model, f0, MOI.EqualTo(0.0))
    MOI.add_constraint(model, f0, MOI.EqualTo(0.0))
    set = MOI.PositiveSemidefiniteConeTriangle(2)
    x, _ = MOI.add_constrained_variables(model, set)
    MOI.add_constraint.(model, 1.0 .* x, MOI.EqualTo.([1.0, -1.0, 2.0]))
    y, _ = MOI.add_constrained_variables(model, set)
    MOI.add_constraint.(model, 1.0 .* y, MOI.EqualTo.([1.0, 2.0, 6.0]))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    f = sum(1.0 * x) + sum(1.0 * y)
    MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
    atol = 1e-4
    @test ≈(MOI.get.(model, MOI.VariablePrimal(), x), [1.0, -1.0, 2.0]; atol)
    @test ≈(MOI.get.(model, MOI.VariablePrimal(), y), [1.0, 2.0, 6.0]; atol)
    return
end

function _reshape(x, N)
    X = Matrix{eltype(x)}(undef, N, N)
    k = 0
    for j in 1:N
        for i in 1:j
            k += 1
            X[j, i] = X[i, j] = x[k]
        end
    end
    return LinearAlgebra.Symmetric(X)
end

function test_maxcut()
    tol = 1e-3
    weights = [0 5 7 6; 5 0 0 1; 7 0 0 1; 6 1 1 0]
    N = size(weights, 1)
    L = LinearAlgebra.Diagonal(weights * ones(N)) - weights
    model = MOI.instantiate(
        SDPLR.Optimizer,
        with_bridge_type = Float64,
        with_cache_type = Float64,
    )
    MOI.set(model, MOI.Silent(), true)
    x, cX = MOI.add_constrained_variables(
        model,
        MOI.PositiveSemidefiniteConeTriangle(N),
    )
    X = _reshape(x, N)
    obj = 0.25 * LinearAlgebra.dot(L, X)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    MOI.add_constraint.(model, LinearAlgebra.diag(X), MOI.EqualTo(1.0))
    for r in 3:-1:1
        if r != 3
            MOI.set(model, MOI.RawOptimizerAttribute("maxrank"), (m, n) -> r)
        end
        MOI.optimize!(model)
        @test MOI.get(model, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
        @test MOI.get(model, MOI.ObjectiveValue()) ≈ 18 rtol = tol
        F = MOI.get(model, SDPLR.Factor(), cX)
        @test F * F' ≈ MOI.get.(model, MOI.VariablePrimal(), X)
        y = MOI.get(model, MOI.ConstraintDual(), cX)
        @test LinearAlgebra.eigmin(_reshape(y, N)) > -tol
    end
end

function test_factor()
    model = MOI.instantiate(
        SDPLR.Optimizer,
        with_bridge_type = Float64,
        with_cache_type = Float64,
    )
    MOI.set(model, MOI.Silent(), true)
    set = MOI.PositiveSemidefiniteConeTriangle(2)
    x, cX = MOI.add_constrained_variables(model, set)
    MOI.add_constraint(model, 1.0 * x[1] + 1.0 * x[2], MOI.EqualTo(1.0))
    y, cY = MOI.add_constrained_variables(model, MOI.Nonnegatives(1))
    MOI.add_constraint(model, 1.0 * x[2] - 1.0 * y[1], MOI.EqualTo(0.0))
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
    F_X = MOI.get(model, SDPLR.Factor(), cX)
    F_y = MOI.get(model, SDPLR.Factor(), cY)
    X = [x[1] x[2]; x[2] x[3]]
    @test F_X * F_X' ≈ MOI.get.(model, MOI.VariablePrimal(), X)
    @test F_y * F_y' ≈ MOI.get.(model, MOI.VariablePrimal(), y)
    return
end

function _build_simple_sparse_model()
    model = SDPLR.Optimizer()
    X, _ = MOI.add_constrained_variables(
        model,
        MOI.PositiveSemidefiniteConeTriangle(2),
    )
    c = MOI.add_constraint(model, 1.0 * X[2], MOI.EqualTo(1.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    obj = 1.0 * X[1] + 1.0 * X[3]
    MOI.set(model, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
    return model, X, c
end

function _build_simple_rankone_model()
    model = SDPLR.Optimizer()
    A1 = LRO.positive_semidefinite_factorization([-1.0; 1.0;;])
    A2 = LRO.positive_semidefinite_factorization([1.0; 1.0;;])
    set = LRO.SetDotProducts{LRO.WITH_SET}(
        MOI.PositiveSemidefiniteConeTriangle(2),
        LRO.TriangleVectorization.([A1, A2]),
    )
    @test set isa SDPLR._SetDotProd
    @test MOI.supports_add_constrained_variables(model, typeof(set))
    dot_prods_X, _ = MOI.add_constrained_variables(model, set)
    dot_prods = dot_prods_X[1:2]
    X = dot_prods_X[3:end]
    c = MOI.add_constraint(
        model,
        -1/4 * dot_prods[1] + 1/4 * dot_prods[2],
        MOI.EqualTo(1.0),
    )
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    obj = 1.0 * X[1] + 1.0 * X[3]
    MOI.set(model, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
    return model, X, c
end

function _build_simple_lowrank_model()
    model = SDPLR.Optimizer()
    A = LRO.Factorization(
        [
            -1.0 1.0
            1.0 1.0
        ],
        [-1 / 4, 1 / 4],
    )
    set = LRO.SetDotProducts{LRO.WITH_SET}(
        MOI.PositiveSemidefiniteConeTriangle(2),
        [LRO.TriangleVectorization(A)],
    )
    @test set isa SDPLR._SetDotProd
    @test set isa SDPLR._SetDotProd{Matrix{Float64},Vector{Float64}}
    @test MOI.supports_add_constrained_variables(model, typeof(set))
    X, _ = MOI.add_constrained_variables(model, set)
    c = MOI.add_constraint(model, 1.0 * X[1], MOI.EqualTo(1.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    obj = 1.0 * X[2] + 1.0 * X[4]
    MOI.set(model, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
    return model, X[2:4], c
end

function _test_simple_model(model, X, c)
    atol = rtol = 1e-2
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
    @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
    Xv = ones(Float64, 3)
    @test MOI.get(model, MOI.VariablePrimal(), X) ≈ Xv atol = atol rtol = rtol
    attr = MOI.ConstraintDual()
    @test MOI.get(model, attr, c) ≈ 2 atol = atol rtol = rtol
    sigma = MOI.get(model, MOI.RawOptimizerAttribute("sigma"))
    σ = round(Int, sigma)
    @test σ ≈ sigma
    return
end

function test_simple_sparse_MOI_wrapper()
    model, X, c = _build_simple_sparse_model()
    MOI.optimize!(model)
    _test_simple_model(model, X, c)
    return
end

function test_simple_lowrank_MOI_wrapper()
    model, X, c = _build_simple_lowrank_model()
    MOI.optimize!(model)
    _test_simple_model(model, X, c)
    return
end

function test_simple_rankone_MOI_wrapper()
    model, X, c = _build_simple_rankone_model()
    MOI.optimize!(model)
    _test_simple_model(model, X, c)
    return
end

function _test_limit(attr, val, term)
    model, _, _ = _build_simple_sparse_model()
    MOI.set(model, MOI.RawOptimizerAttribute(attr), val)
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == term
    @test MOI.get(model, MOI.PrimalStatus()) == MOI.UNKNOWN_RESULT_STATUS
    @test MOI.get(model, MOI.DualStatus()) == MOI.UNKNOWN_RESULT_STATUS
end

function test_majiter()
    _test_limit("majiter", SDPLR.MAX_MAJITER, MOI.ITERATION_LIMIT)
    _test_limit("majiter", SDPLR.MAX_MAJITER - 1, MOI.ITERATION_LIMIT)
    return
end

function test_iter()
    _test_limit("iter", SDPLR.MAX_ITER, MOI.ITERATION_LIMIT)
    _test_limit("iter", SDPLR.MAX_ITER - 1, MOI.ITERATION_LIMIT)
    return
end

function test_timelim()
    _test_limit("timelim", 0, MOI.TIME_LIMIT)
    return
end

function totaltime()
    _test_limit("totaltime", SDPLR.Parameters().timelim, MOI.TIME_LIMIT)
    _test_limit("totaltime", SDPLR.Parameters().timelim - eps(), MOI.TIME_LIMIT)
    return
end

function test_continuity_between_solve()
    model, X, c = _build_simple_sparse_model()
    MOI.set(model, MOI.RawOptimizerAttribute("majiter"), SDPLR.MAX_MAJITER - 2)
    @test MOI.get(model, MOI.RawOptimizerAttribute("majiter")) ==
          SDPLR.MAX_MAJITER - 2
    MOI.optimize!(model)
    @test MOI.get(model, MOI.RawOptimizerAttribute("majiter")) >=
          SDPLR.MAX_MAJITER
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
    for i in 1:5
        MOI.set(
            model,
            MOI.RawOptimizerAttribute("majiter"),
            SDPLR.MAX_MAJITER - 2,
        )
        @test MOI.get(model, MOI.RawOptimizerAttribute("majiter")) ==
              SDPLR.MAX_MAJITER - 2
        MOI.optimize!(model)
    end
    _test_simple_model(model, X, c)
    return
end

function test_bounds()
    PATAKI = [
        1 1 1 1 1 1 1
        1 1 1 1 1 1 1
        2 2 2 2 2 2 2
        2 2 2 2 2 2 2
        2 2 2 2 2 2 2
        3 3 3 3 3 3 3
        3 3 3 3 3 3 3
    ]
    BARVINOK = [
        1 1 1 1 1 1 1
        1 1 1 1 1 1 1
        2 2 1 1 1 1 1
        2 2 2 2 2 2 2
        2 2 2 2 2 2 2
        3 3 3 2 2 2 2
        3 3 3 3 3 3 3
    ]
    DEFAULT_MAXRANK = [
        1 2 2 2 2 2 2
        1 2 3 3 3 3 3
        1 2 3 3 3 3 3
        1 2 3 3 3 3 3
        1 2 3 4 4 4 4
        1 2 3 4 4 4 4
        1 2 3 4 4 4 4
    ]
    τ(r) = MOI.dimension(MOI.PositiveSemidefiniteConeTriangle(r))
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

function _test_solve_simple_with_sdplrlib(;
    CAinfo_entptr,
    CAent,
    CArow,
    CAcol,
    CAinfo_type,
)
    blksz = Cptrdiff_t[2]
    blktype = Cchar['s']
    b = Cdouble[1]
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
    @test U * U' ≈ ones(2, 2) rtol = 1e-2
    @test lambda ≈ [2.0] atol = 1e-2
    @test ranks == Csize_t[2]
    return
end

function test_solve_simple_sparse_with_sdplrlib()
    _test_solve_simple_with_sdplrlib(
        CAinfo_entptr = Csize_t[0, 2, 3],
        CAent = Cdouble[1, 1, 0.5],
        CArow = Csize_t[1, 2, 1],
        CAcol = Csize_t[1, 2, 2],
        CAinfo_type = Cchar['s', 's'],
    )
    return
end

function test_solve_simple_lowrank_with_sdplrlib()
    _test_solve_simple_with_sdplrlib(
        CAinfo_entptr = Csize_t[0, 2, 8],
        CAent = Cdouble[1, 1, -0.25, 0.25, -1, 1, 1, 1],
        CArow = Csize_t[1, 2, 1, 2, 1, 2, 1, 2],
        CAcol = Csize_t[1, 2, 1, 2, 1, 1, 2, 2],
        CAinfo_type = Cchar['s', 'l'],
    )
    return
end

function test_solve_vibra_with_sdplr_executable()
    SDPLR.solve_sdpa_file("vibra1.dat-s")
    return
end

function test_solve_vibra_with_sdplrlib()
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

# Test of LowRankOpt's test `test_conic_PositiveSemidefinite_RankOne_polynomial` in low-level SDPLR version
function test_solve_conic_PositiveSemidefinite_RankOne_polynomial()
    blksz = [2, 2]
    blktype = Cchar['d', 's']
    b = [-3.0, 1.0]
    CAent = [-1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, -1.0, 1.0, -1.0, 1.0, 1.0]
    CArow = Csize_t[1, 2, 1, 2, 1, 1, 2, 1, 2, 1, 1, 2]
    CAcol = Csize_t[1, 2, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1]
    CAinfo_entptr = Csize_t[0, 2, 2, 4, 7, 9, 12]
    CAinfo_type = Cchar['d', 's', 'd', 'l', 'd', 'l']
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
    U = reshape(R[3:end], 2, 2)
    @test U * U' ≈ [1 -1; -1 1] rtol = 1e-3
    @test lambda ≈ [0, 1] atol = 1e-3
    @test pieces[1:5] == [7, 20, 1, 0, 0]
    @test pieces[7:8] == [16, 1]
    @test ranks == [1, 2]
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

TestSDPLR.runtests()
