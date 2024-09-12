# SDPLR

[![Build Status](https://github.com/blegat/SDPLR.jl/workflows/CI/badge.svg?branch=master)](https://github.com/blegat/SDPLR.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/blegat/SDPLR.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/blegat/SDPLR.jl)

[SDPLR.jl](https://github.com/blegat/SDPLR.jl) is a wrapper for the
[SDPLR](https://github.com/sburer/sdplr) semidefinite programming solver.

## License

`SDPLR.jl` is licensed under the [MIT License](https://github.com/blegat/SDPLR.jl/blob/master/LICENSE.md).

The underlying solver, [SDPLR](https://github.com/sburer/sdplr), is
licensed under the GPL v2 license.

## Installation

Install SDPLR.jl using `Pkg.add`:
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

The algorithm is parametrized by the attributes that can be used both with `JuMP.set_attributes` and `JuMP.get_attributes`
and have the following types and default values:
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

The following attributes can be also be used both with `JuMP.set_attributes` and `JuMP.get_attributes`, but they are also
modified by `optimize!`:
* `majiter`
* `iter`
* `lambdaupdate`
* `totaltime`
* `sigma`

When they are `set`, it provides the initial value of the algorithm.
With `get`, they provide the value at the end of the algorithm.
`totaltime` is the total time in second. For the other attributes,
their meaning is best described by the following pseudo-code.

Given values of `R`, `lambda` and `sigma`, let
`vio = [dot(A[i], R * R') - b[i]) for i in 1:m]` (`vio[0]` is `dot(C, R * R')` in the C implementation, but we ignore this entry here),
`val = dot(C, R * R') - dot(vio, lambda) + sigma/2 * norm(vio)^2`,
`y = -lambda - sigma * vio`,
`S = C + sum(A[i] * y[i] for i in 1:m)` and
the gradient is `G = 2S * R`.
Note that `norm(G)` used in SDPLR when comparing with `rho_c` which has a 2-scaling difference
from `norm(S * R)` used in the paper.

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
