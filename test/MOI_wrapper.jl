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
        atol = 1e-1,
        exclude = Any[
            MOI.ConstraintBasisStatus,
            MOI.VariableBasisStatus,
            MOI.ConstraintName,
            MOI.VariableName,
            MOI.ObjectiveBound,
            MOI.ConstraintPrimal, # TODO
            MOI.ConstraintDual, # TODO
            MOI.SolverVersion,
        ],
        optimal_status = MOI.LOCALLY_SOLVED,
    )
    MOI.Test.runtests(
        model,
        config,
        exclude = [
            # Needs https://github.com/jump-dev/MathOptInterface.jl/pull/2358
            r"test_basic_VectorOfVariables_Nonpositives$",
            # Needs https://github.com/jump-dev/MathOptInterface.jl/pull/2360
            r"test_basic_VectorOfVariables_SecondOrderCone$",
            # Needs https://github.com/jump-dev/MathOptInterface.jl/pull/2359
            r"test_constraint_PrimalStart_DualStart_SecondOrderCone$",
            # Needs https://github.com/jump-dev/MathOptInterface.jl/pull/2357
            r"test_model_ListOfVariablesWithAttributeSet$",
            r"test_model_LowerBoundAlreadySet$",
            r"test_model_UpperBoundAlreadySet$",
            r"test_model_ScalarFunctionConstantNotZero$",
            r"test_model_delete$",
            # Detecting infeasibility or unboundedness not supported
            "INFEASIBLE",
            "infeasible",
            # FIXME investigate
            r"test_conic_SecondOrderCone_nonnegative_post_bound$",
            r"test_conic_SecondOrderCone_negative_post_bound_2$",
            r"test_conic_SecondOrderCone_negative_post_bound_3$",
            r"test_conic_SecondOrderCone_no_initial_bound$",
            r"test_linear_add_constraints$",
            r"test_modification_affine_deletion_edge_cases$",
            # Surprise! Got a quadratic function!, needs https://github.com/sburer/sdplr/pull/2
            r"test_constraint_ScalarAffineFunction_GreaterThan$",
            r"test_constraint_ScalarAffineFunction_EqualTo$",
            r"test_constraint_ScalarAffineFunction_Interval$",
            r"test_linear_LessThan_and_GreaterThan$",
            r"test_linear_modify_GreaterThan_and_LessThan_constraints$",
            r"test_modification_const_vectoraffine_zeros$",
            r"test_linear_VectorAffineFunction$",
        ],
    )
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
