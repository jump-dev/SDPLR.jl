using Test
import SDPLR
using LinearAlgebra
import MathOptInterface as MOI

# README example

function _reshape(x, N)
    X = Matrix{eltype(x)}(undef, N, N)
    k = 0
    for j in 1:N
        for i in 1:j
            k += 1
            X[j, i] = X[i, j] = x[k]
        end
    end
    return Symmetric(X)
end

function test_maxcut(weights; tol = 1e-4)
    N = size(weights, 1)
    L = Diagonal(weights * ones(N)) - weights
    model = MOI.instantiate(SDPLR.Optimizer, with_bridge_type = Float64, with_cache_type = Float64)
    MOI.set(model, MOI.Silent(), true)
    x, cX = MOI.add_constrained_variables(model, MOI.PositiveSemidefiniteConeTriangle(N))
    X = _reshape(x, N)
    obj = 0.25 * dot(L, X)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    MOI.add_constraint.(model, diag(X), MOI.EqualTo(1.0))
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
        @test minimum(eigvals(_reshape(y, N))) > -tol
    end
end

@testset "maxcut" begin
    test_maxcut([0 5 7 6; 5 0 0 1; 7 0 0 1; 6 1 1 0])
end
