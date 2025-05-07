# SDPLR

[![Build Status](https://github.com/jump-dev/SDPLR.jl/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/jump-dev/SDPLR.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/jump-dev/SDPLR.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jump-dev/SDPLR.jl)

[SDPLR.jl](https://github.com/jump-dev/SDPLR.jl) is a wrapper for the
[SDPLR](https://github.com/sburer/sdplr) semidefinite programming solver.

## Affiliation

This wrapper is maintained by the JuMP community and is not an official project
of [`@sburer`](https://github.com/sburer).

## Getting help

If you need help, please ask a question on the [JuMP community forum](https://jump.dev/forum).

If you have a reproducible example of a bug, please [open a GitHub issue](https://github.com/jump-dev/SDPLR.jl/issues/new).

## License

`SDPLR.jl` is licensed under the [MIT License](https://github.com/jump-dev/SDPLR.jl/blob/master/LICENSE.md).

The underlying solver, [SDPLR](https://github.com/sburer/sdplr), is
licensed under the GPL v2 license.

## Installation

Install SDPLR as follows:
```julia
import Pkg
Pkg.add("SDPLR")
```

In addition to installing the SDPLR.jl package, this will also download and
install the SDPLR binaries. You do not need to install SDPLR separately.

To use a custom binary, read the [Custom solver binaries](https://jump.dev/JuMP.jl/stable/developers/custom_solver_binaries/)
section of the JuMP documentation.

## Use with JuMP

To use SDPLR with [JuMP](https://github.com/jump-dev/JuMP.jl), use
`SDPLR.Optimizer`:
```julia
using JuMP, SDPLR
model = Model(SDPLR.Optimizer)
```

## Example: modifying the rank and checking optimality

Most SDP solvers search for positive semidefinite (PSD) matrices of variables
over the **convex** cone of `n × n` PSD matrices `X`. On the other hand, SDPLR
searches for their rank-`r` factor `F` such that `X = F * F'`.

The advantage is that, as `F` is a `n × r` matrix, this decreases the number of
variables if `r < n`. The disadvantage is that the SDPLR is now solving a
nonconvex problem so it may converge to a solution that is not optimal.

The rule of thumb is: the larger `r` is, the more likely the solution you will
get is optimal but the smaller `r` is, the faster each iteration is
(but the number of iterations may increase for smaller `r` as shown in
[Section 7 of this paper](https://doi.org/10.1137/22M1516208)).

The default `r` is quite conservative (in the sense large) and you may want to
try a smaller one an only increase it if you don't get an optimal solution.
The following example (taken from the [JuMP documentation](https://jump.dev/JuMP.jl/stable/tutorials/conic/simple_examples/#Maximum-cut-via-SDP))
shows how to control this rank `r` and check whether the solution is optimal.

```julia-repl
julia> using LinearAlgebra, JuMP, SDPLR

julia> weights = [0 5 7 6; 5 0 0 1; 7 0 0 1; 6 1 1 0];

julia> N = LinearAlgebra.checksquare(weights)

julia> L = Diagonal(weights * ones(N)) - weights;

julia> model = Model(SDPLR.Optimizer);

julia> @variable(model, X[1:N, 1:N], PSD);

julia> @objective(model, Max, dot(L, X) / 4);

julia> @constraint(model, diag(X) .== 1);

julia> optimize!(model)

            ***   SDPLR 1.03-beta   ***

===================================================
 major   minor        val        infeas      time
---------------------------------------------------
    1       22  -1.75428069e+01  8.2e-01       0
    2       24  -1.82759022e+01  3.5e-01       0
    3       25  -1.79338413e+01  2.7e-01       0
    4       27  -1.80024572e+01  1.2e-01       0
    5       29  -1.79952170e+01  4.4e-02       0
    6       31  -1.79986685e+01  1.2e-02       0
    7       32  -1.79998916e+01  1.8e-03       0
    8       33  -1.79999794e+01  1.6e-04       0
    9       36  -1.79999993e+01  1.5e-05       0
   10       37  -1.79999994e+01  4.7e-07       0
===================================================

DIMACS error measures: 4.68e-07 0.00e+00 0.00e+00 1.40e-05 -5.98e-06 -8.32e-06

julia> assert_is_solved_and_feasible(model)

julia> objective_value(model)
18.00000016028532
```

We can see below that the factorization `F` is of rank 3:

```julia-repl
julia> F = MOI.get(model, SDPLR.Factor(), VariableInSetRef(X))
4×3 Matrix{Float64}:
  0.750149   0.558936  -0.353365
 -0.749709  -0.559317   0.353696
 -0.750098  -0.558986   0.353394
 -0.750538  -0.558704   0.352905
```

`JuMP.value(X)` is internally computed from the factor so this will always hold:

```julia-repl
julia> F * F' ≈ value(X)
true
```

The termination status is `LOCALLY_SOLVED` because the solution is a local
optimum of the nonconvex formulation and hence not necessarily a global optimum.

```julia-repl
julia> termination_status(model)
LOCALLY_SOLVED::TerminationStatusCode = 4
```

We can verify that the solution is globally optimal by checking that the dual
solution is feasible (meaning PSD). The `-5e-5` eigenvalue is negative but is
small enough to be ignored so the dual solution is PSD up to tolerances.

```julia-repl
julia> eigvals(dual(VariableInSetRef(X)))
4-element Vector{Float64}:
 -5.5297120327451185e-5
  0.7090766636490886
  1.2560254012624266
  6.03473204677525
```

Let's try with rank 2 now:

```julia-repl
julia> set_attribute(model, "maxrank", (m, n) -> 2)

julia> optimize!(model)

            ***   SDPLR 1.03-beta   ***

===================================================
 major   minor        val        infeas      time
---------------------------------------------------
    1       20  -1.76083202e+01  7.2e-01       0
    2       21  -1.82954416e+01  2.1e-01       0
    3       22  -1.80917018e+01  2.3e-01       0
    4       24  -1.80200881e+01  1.0e-01       0
    5       26  -1.79962343e+01  4.3e-02       0
    6       27  -1.79984880e+01  1.2e-02       0
    7       29  -1.79998597e+01  2.1e-03       0
    8       30  -1.79999762e+01  1.4e-04       0
    9       31  -1.79999773e+01  3.5e-05       0
   10       32  -1.79999776e+01  7.7e-06       0
===================================================

DIMACS error measures: 7.74e-06 0.00e+00 0.00e+00 0.00e+00 8.76e-05 1.93e-04


julia> objective_value(model)
18.000124713180156

julia> F = MOI.get(model, SDPLR.Factor(), VariableInSetRef(X))
4×2 Matrix{Float64}:
 -0.39698   -0.917833
  0.399991   0.916523
  0.398418   0.917206
  0.39305    0.919521

julia> eigvals(dual(VariableInSetRef(X)))
4-element Vector{Float64}:
 0.0008412385307274264
 0.7102448337160858
 1.2569605953450345
 6.035318464366805
```

The objective value is `18` again so we know it's optimal. However, if we didn't
have yet an optimal solution, we could also verify the global optimality by
verifying that the eigenvalues of the dual matrix are positive.

Let's try with rank 1 now:

```julia-repl
julia> set_attribute(model, "maxrank", (m, n) -> 1)

julia> optimize!(model)

            ***   SDPLR 1.03-beta   ***

===================================================
 major   minor        val        infeas      time
---------------------------------------------------
    1        0   3.88597323e-01  9.8e-01       0
    2       16  -1.81253890e+01  3.5e-01       0
    3       18  -1.81074541e+01  2.1e-01       0
    4       20  -1.80170389e+01  1.1e-01       0
    5       22  -1.79964156e+01  4.3e-02       0
    6       23  -1.79985211e+01  1.2e-02       0
    7       24  -1.79999403e+01  1.8e-03       0
    8       25  -1.79999930e+01  3.3e-04       0
    9       26  -1.80000000e+01  5.6e-06       0
===================================================

DIMACS error measures: 5.58e-06 0.00e+00 0.00e+00 0.00e+00 2.93e-05 5.15e-05


julia> objective_value(model)
18.00008569596812

julia> F = MOI.get(model, SDPLR.Factor(), VariableInSetRef(X))
4×1 Matrix{Float64}:
  1.0000046270533638
 -1.0000025416399554
 -0.9999982261859701
 -1.000000352897998

julia> eigvals(dual(VariableInSetRef(X)))
4-element Vector{Float64}:
 0.00029282484813959026
 0.7096115224412582
 1.2565481700036387
 6.034718894384703
```

The eigenvalues of the dual solution are again positive which certifies the
global optimality of the primal solution.

## MathOptInterface API

The SDPLR optimizer supports the following constraints and attributes.

List of supported objective functions:

 * [`MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}`](@ref)

List of supported variable types:

 * [`MOI.Nonnegatives`](@ref)
 * [`MOI.PositiveSemidefiniteConeTriangle`](@ref)

List of supported constraint types:

 * [`MOI.ScalarAffineFunction{Float64}`](@ref) in [`MOI.EqualTo{Float64}`](@ref)

List of supported model attributes:

 * [`MOI.ObjectiveSense()`](@ref)

## Attributes

The algorithm is parametrized by the attributes that can be used both with
`JuMP.set_attribute` and `JuMP.get_attribute` and have the following types and
default values:
```julia
rho_f::Cdouble = 1.0e-5
rho_c::Cdouble = 1.0e-1
sigmafac::Cdouble = 2.0
rankreduce::Csize_t = 0
timelim::Csize_t = 3600
printlevel::Csize_t = 1
dthresh_dim::Csize_t = 10
dthresh_dens::Cdouble = 0.75
numbfgsvecs::Csize_t = 4
rankredtol::Cdouble = 2.2204460492503131e-16
gaptol::Cdouble = 1.0e-3
checkbd::Cptrdiff_t = -1
typebd::Cptrdiff_t = 1
maxrank::Function = default_maxrank
```

The following attributes can be also be used both with `JuMP.set_attribute` and
`JuMP.get_attribute`, but they are also modified by `optimize!`:

* `majiter`
* `iter`
* `lambdaupdate`
* `totaltime`
* `sigma`

When they are `set`, it provides the initial value of the algorithm. With `get`,
they provide the value at the end of the algorithm. `totaltime` is the total
time in seconds. For the other attributes, their meaning is best described by
the following pseudo-code.

Given values of `R`, `lambda` and `sigma`, let
`vio = [dot(A[i], R * R') - b[i]) for i in 1:m]` (`vio[0]` is `dot(C, R * R')`
in the C implementation, but we ignore this entry here),
`val = dot(C, R * R') - dot(vio, lambda) + sigma/2 * norm(vio)^2`,
`y = -lambda - sigma * vio`,
`S = C + sum(A[i] * y[i] for i in 1:m)` and the gradient is `G = 2S * R`. Note
that `norm(G)` used in SDPLR when comparing with `rho_c` which has a 2-scaling
difference from `norm(S * R)` used in the paper.

The SDPLR solvers implements the following algorithm.

```julia
sigma = inv(sum(size(A[i], 1) for i in 1:m))
origval = val
while majiter++ < 100_000
    lambdaupdate = 0
    localiter = 100
    while localiter > 10
        lambdaupdate += 1
        localiter = 0
        if norm(G) / (norm(C) + 1) <= rho_c / sigma
            break
        end
        while norm(G) / (norm(C) + 1) - rho_c / sigma > eps()
            localiter += 1
            iter += 1
            D = lbfgs(G)
            R += linesearch(D) * D
            if norm(vio) / (norm(b) + 1) <= rho_f || totaltime >= timelim || iter >= 10_000_000
                return
            end
        end
        lambda -= sigma * vio
    end
    if val - 1e10 * abs(origval) > eps()
        return
    end
    if norm(vio) / (norm(b) + 1) <= rho_f || totaltime >= timelim || iter >= 10_000_000
        return
    end
    sigma *= 2
    while norm(G) / (norm(C) + 1) < rho_c / sigma
        sigma *= 2
    end
    lambdaupdate = 0
end
```
