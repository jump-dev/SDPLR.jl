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
            # Get `Surprise! Got a quadratic function!` from SDPLR
            r"test_conic_NormInfinityCone_INFEASIBLE$",
            r"test_conic_NormOneCone_INFEASIBLE$",
            r"test_conic_RotatedSecondOrderCone_INFEASIBLE$",
            r"test_conic_linear_INFEASIBLE$",
            r"test_constraint_ScalarAffineFunction_EqualTo$",
            r"test_conic_linear_INFEASIBLE_2$",
            r"test_constraint_ScalarAffineFunction_Interval$",
            r"test_infeasible_MAX_SENSE$",
            r"test_infeasible_MAX_SENSE_offset$",
            r"test_infeasible_MIN_SENSE$",
            r"test_infeasible_MIN_SENSE_offset$",
            r"test_infeasible_affine_MAX_SENSE$",
            r"test_infeasible_affine_MAX_SENSE_offset$",
            r"test_infeasible_affine_MIN_SENSE$",
            r"test_infeasible_affine_MIN_SENSE_offset$",
            r"test_linear_HyperRectangle_VectorAffineFunction$",
            r"test_linear_HyperRectangle_VectorOfVariables$",
            r"test_linear_INFEASIBLE$",
            r"test_linear_INFEASIBLE_2$",
            r"test_linear_integration$",
            r"test_linear_integration_Interval$",
            r"test_modification_func_vectoraffine_nonneg$",
            r"test_solve_TerminationStatus_DUAL_INFEASIBLE$",
            # Error(sdplrlib): Got NaN from SDPLR
            r"test_conic_GeometricMeanCone_VectorAffineFunction_3$",
            r"test_conic_GeometricMeanCone_VectorAffineFunction$",
            r"test_conic_GeometricMeanCone_VectorOfVariables_2$",
            r"test_conic_GeometricMeanCone_VectorOfVariables$",
            r"test_conic_GeometricMeanCone_VectorOfVariables_3$",
            r"test_conic_PositiveSemidefiniteConeTriangle$",
            r"test_conic_RootDetConeSquare_VectorAffineFunction$",
            r"test_conic_RootDetConeSquare_VectorOfVariables$",
            r"test_conic_RootDetConeTriangle_VectorAffineFunction$",
            r"test_conic_RootDetConeTriangle_VectorOfVariables$",
            r"test_constraint_ScalarAffineFunction_duplicate$",
            r"test_constraint_ScalarAffineFunction_LessThan$",
            r"test_modification_func_scalaraffine_lessthan$",
            r"test_modification_func_scalaraffine_lessthan$",
            r"test_modification_const_vectoraffine_nonpos$",
            # MOI bug:
            # test_basic_VectorOfVariables_SecondOrderCone: Error During Test at /home/blegat/.julia/dev/MathOptInterface/src/Test/Test.jl:266
            #  Got exception outside of a @test
            #  InexactError: convert(MathOptInterface.VectorOfVariables, ┌                                              ┐
            #  │0.0 + 0.9999999999999999 MOI.VariableIndex(-1)│
            #  │0.0 + 0.9999999999999999 MOI.VariableIndex(-2)│
            #  │0.0 + 1.0 MOI.VariableIndex(-3)               │
            #  └                                              ┘)
            #  Stacktrace:
            #    [1] convert(#unused#::Type{MathOptInterface.VectorOfVariables}, f::MathOptInterface.VectorAffineFunction{Float64})
            #      @ MathOptInterface ~/.julia/dev/MathOptInterface/src/functions.jl:1266
            #    [2] get(model::MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.Utilities.CachingOptimizer{SDPLR.Optimizer, MathOptInterface.Utilities.UniversalFallback{MathOptInterface.Utilities.Model{Float64}}}}, #unused#::MathOptInterface.ConstraintFunction, b::MathOptInterface.Bridges.Constraint.FunctionConversionBridge{Float64, MathOptInterface.VectorAffineFunction{Float64}, MathOptInterface.VectorOfVariables, MathOptInterface.SecondOrderCone})
            #      @ MathOptInterface.Bridges.Constraint ~/.julia/dev/MathOptInterface/src/Bridges/Constraint/bridges/functionize.jl:293
            r"test_basic_VectorOfVariables_SecondOrderCone$",
            r"test_conic_SecondOrderCone_negative_post_bound_2$",
            r"test_conic_SecondOrderCone_negative_post_bound_3$",
            r"test_conic_SecondOrderCone_nonnegative_post_bound$",
            # test_basic_VectorOfVariables_Nonpositives: Error During Test at /home/blegat/.julia/dev/MathOptInterface/src/Test/test_basic_constraint.jl:276
            #  Test threw exception
            #  Expression: MOI.get(model, MOI.ConstraintSet(), c) == set
            #  StackOverflowError:
            #  Stacktrace:
            #       [1] call_in_context(b::MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.Utilities.CachingOptimizer{SDPLR.Optimizer, MathOptInterface.Utilities.UniversalFallback{MathOptInterface.Utilities.Model{Float64}}}}, ci::MathOptInterface.ConstraintIndex{MathOptInterface.VectorOfVariables, MathOptInterface.Nonpositives}, f::MathOptInterface.Bridges.var"#3#4"{typeof(MathOptInterface.get), MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.Utilities.CachingOptimizer{SDPLR.Optimizer, MathOptInterface.Utilities.UniversalFallback{MathOptInterface.Utilities.Model{Float64}}}}, MathOptInterface.ConstraintSet, Tuple{}})
            #         @ MathOptInterface.Bridges ~/.julia/dev/MathOptInterface/src/Bridges/bridge_optimizer.jl:309
            #       [2] call_in_context
            #         @ ~/.julia/dev/MathOptInterface/src/Bridges/bridge_optimizer.jl:332 [inlined]
            #       [3] get(b::MathOptInterface.Bridges.LazyBridgeOptimizer{MathOptInterface.Utilities.CachingOptimizer{SDPLR.Optimizer, MathOptInterface.Utilities.UniversalFallback{MathOptInterface.Utilities.Model{Float64}}}}, attr::MathOptInterface.ConstraintSet, ci::MathOptInterface.ConstraintIndex{MathOptInterface.VectorOfVariables, MathOptInterface.Nonpositives})
            #         @ MathOptInterface.Bridges ~/.julia/dev/MathOptInterface/src/Bridges/bridge_optimizer.jl:1467
            r"test_basic_VectorOfVariables_Nonpositives$",
            # Unable to bridge RotatedSecondOrderCone to PSD because the dimension is too small: got 2, expected >= 3.
            r"test_conic_SecondOrderCone_INFEASIBLE$",
            r"test_constraint_PrimalStart_DualStart_SecondOrderCone$",
            # To investigate
            r"test_conic_RotatedSecondOrderCone_out_of_order$",
            # Wrong answer
            r"test_NormSpectralCone_VectorOfVariables_with_transform$",
            r"test_HermitianPSDCone_min_t$",
            r"test_HermitianPSDCone_basic$",
            r"test_conic_NormInfinityCone_3$",
            r"test_conic_NormOneCone$",
            r"test_conic_PositiveSemidefiniteConeSquare_VectorAffineFunction_2$",
            r"test_conic_RootDetConeTriangle_VectorOfVariables$",
            r"test_conic_RootDetConeTriangle_VectorAffineFunction$",
            r"test_conic_RootDetConeTriangle$",
            r"test_conic_HermitianPositiveSemidefiniteConeTriangle_1$",
            r"test_conic_NormInfinityCone_VectorAffineFunction$",
            r"test_conic_NormInfinityCone_VectorOfVariables$",
            r"test_conic_NormNuclearCone$",
            r"test_conic_NormNuclearCone_2$",
            r"test_conic_NormSpectralCone$",
            r"test_conic_NormSpectralCone_2$",
            r"test_conic_PositiveSemidefiniteConeSquare_3$",
            r"test_conic_PositiveSemidefiniteConeSquare_VectorAffineFunction$",
            r"test_conic_PositiveSemidefiniteConeSquare_VectorOfVariables$",
            r"test_conic_PositiveSemidefiniteConeSquare_VectorOfVariables_2$",
            r"test_conic_PositiveSemidefiniteConeTriangle_3$",
            r"test_conic_PositiveSemidefiniteConeTriangle_VectorAffineFunction$",
            r"test_conic_PositiveSemidefiniteConeTriangle_VectorAffineFunction_2$",
            r"test_conic_PositiveSemidefiniteConeTriangle_VectorOfVariables$",
            r"test_conic_PositiveSemidefiniteConeTriangle_VectorOfVariables_2$",
            r"test_conic_RootDetConeSquare$",
            r"test_conic_RootDetConeTriangle$",
            r"test_conic_RotatedSecondOrderCone_VectorAffineFunction$",
            r"test_conic_RotatedSecondOrderCone_VectorOfVariables$",
            r"test_conic_ScaledPositiveSemidefiniteConeTriangle_VectorAffineFunction$",
            r"test_conic_SecondOrderCone_Nonnegatives$",
            r"test_conic_SecondOrderCone_Nonpositives$",
            r"test_conic_SecondOrderCone_VectorAffineFunction$",
            r"test_conic_SecondOrderCone_VectorOfVariables$",
            r"test_conic_SecondOrderCone_negative_initial_bound$",
            r"test_conic_SecondOrderCone_negative_post_bound$",
            r"test_conic_SecondOrderCone_negative_post_bound_2$",
            r"test_conic_SecondOrderCone_no_initial_bound$",
            r"test_conic_SecondOrderCone_nonnegative_initial_bound$",
            r"test_conic_SecondOrderCone_nonnegative_post_bound$",
            r"test_conic_SecondOrderCone_out_of_order$",
            r"test_NormSpectralCone_VectorOfVariables_without_transform$",
            r"test_NormSpectralCone_VectorAffineFunction_without_transform$",
            r"test_NormSpectralCone_VectorAffineFunction_with_transform$",
            r"test_NormNuclearCone_VectorOfVariables_without_transform$",
            r"test_NormNuclearCone_VectorOfVariables_with_transform$",
            r"test_NormNuclearCone_VectorAffineFunction_without_transform$",
            r"test_NormNuclearCone_VectorAffineFunction_with_transform$",
            r"test_conic_linear_VectorAffineFunction$",
            r"test_conic_linear_VectorAffineFunction_2$",
            r"test_conic_linear_VectorOfVariables$",
            r"test_conic_linear_VectorOfVariables_2$",
            r"test_conic_GeometricMeanCone_VectorAffineFunction_2$",
            r"test_conic_NormOneCone_VectorAffineFunction$",
            r"test_conic_RotatedSecondOrderCone_INFEASIBLE_2$",
            r"test_constraint_ScalarAffineFunction_GreaterThan$",
            r"test_conic_NormOneCone_VectorOfVariables$",
            r"test_constraint_ScalarAffineFunction_LessThan$",
            r"test_constraint_ScalarAffineFunction_duplicate$",
            r"test_linear_FEASIBILITY_SENSE$",
            r"test_modification_delete_variables_in_a_batch$",
            r"test_modification_const_vectoraffine_zeros$",
            r"test_quadratic_constraint_minimize$",
            r"test_solve_result_index$",
            r"test_variable_solve_with_lowerbound$",
            r"test_variable_solve_with_upperbound$",
            # Wrong answer on CI
            r"test_quadratic_duplicate_terms$",
            r"test_quadratic_integration$",
            # Unclassified
            r"test_constraint_VectorAffineFunction_duplicate",
            r"test_linear_DUAL_INFEASIBLE",
            r"test_linear_DUAL_INFEASIBLE_2",
            r"test_linear_Interval_inactive",
            r"test_linear_LessThan_and_GreaterThan",
            r"test_linear_VariablePrimalStart_partial",
            r"test_linear_VectorAffineFunction",
            r"test_linear_VectorAffineFunction_empty_row",
            r"test_linear_add_constraints",
            r"test_linear_complex_Zeros",
            r"test_linear_complex_Zeros_duplicate",
            r"test_linear_inactive_bounds",
            r"test_linear_integration_2",
            r"test_linear_integration_delete_variables",
            r"test_linear_integration_modification",
            r"test_linear_modify_GreaterThan_and_LessThan_constraints",
            r"test_linear_open_intervals",
            r"test_linear_transform",
            r"test_linear_variable_open_intervals",
            r"test_model_ListOfVariablesWithAttributeSet",
            r"test_model_LowerBoundAlreadySet",
            r"test_model_ScalarFunctionConstantNotZero",
            r"test_model_UpperBoundAlreadySet",
            r"test_model_delete",
            r"test_modification_affine_deletion_edge_cases",
            r"test_modification_coef_scalar_objective",
            r"test_modification_coef_scalaraffine_lessthan",
            r"test_modification_const_scalar_objective",
            r"test_modification_delete_variable_with_single_variable_obj",
            r"test_modification_multirow_vectoraffine_nonpos",
            r"test_modification_set_scalaraffine_lessthan",
            r"test_modification_set_singlevariable_lessthan",
            r"test_modification_transform_singlevariable_lessthan",
            r"test_objective_FEASIBILITY_SENSE_clears_objective",
            r"test_objective_ObjectiveFunction_VariableIndex",
            r"test_objective_ObjectiveFunction_constant",
            r"test_objective_ObjectiveFunction_duplicate_terms",
            r"test_objective_qp_ObjectiveFunction_edge_cases",
            r"test_objective_qp_ObjectiveFunction_zero_ofdiag",
            r"test_quadratic_constraint_basic",
            r"test_quadratic_constraint_integration",
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
