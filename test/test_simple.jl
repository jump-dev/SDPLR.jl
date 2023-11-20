using Test
import SDPLR
import Random
import MathOptInterface as MOI

# This is `test_conic_PositiveSemidefiniteConeTriangle_VectorOfVariables`
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

@testset "MOI wrapper" begin
    atol = rtol = 1e-3
    model = SDPLR.Optimizer()
    X, cX = MOI.add_constrained_variables(
        model,
        MOI.PositiveSemidefiniteConeTriangle(2),
    )
    c = MOI.add_constraint(model, 1.0 * X[2], MOI.EqualTo(1.0))
    MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    obj = 1.0 * X[1] + 1.0 * X[3]
    MOI.set(model, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
    MOI.optimize!(model)
    @test MOI.get(model, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
    @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
    Xv = ones(Float64, 3)
    @test MOI.get(model, MOI.VariablePrimal(), X) ≈ Xv atol = atol rtol = rtol
    attr = MOI.ConstraintDual()
    @test MOI.get(model, attr, c) ≈ 2 atol = atol rtol = rtol
end
