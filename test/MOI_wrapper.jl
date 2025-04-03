# Copyright (c) 2017: Benoît Legat and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module TestMOI

using Test
import MathOptInterface as MOI
import SDPLR

function test_runtests()
    optimizer = SDPLR.Optimizer()
    MOI.set(optimizer, MOI.Silent(), true)
    MOI.set(optimizer, MOI.RawOptimizerAttribute("timelim"), 10)
    model = MOI.Bridges.full_bridge_optimizer(
        MOI.Utilities.CachingOptimizer(
            MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
            optimizer,
        ),
        Float64,
    )
    config = MOI.Test.Config(
        rtol = 1e-1,
        atol = 1e-1,
        exclude = Any[
            MOI.ConstraintBasisStatus,
            MOI.VariableBasisStatus,
            MOI.ConstraintName,
            MOI.VariableName,
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
    set = MOI.PositiveSemidefiniteConeTriangle(2)
    x, c = MOI.add_constrained_variables(model, set)
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

TestMOI.runtests()
