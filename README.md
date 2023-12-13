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

 * [`MOI.Reals`](@ref)

List of supported constraint types:

 * [`MOI.VectorAffineFunction{Float64}`](@ref) in [`MOI.Nonnegatives`](@ref)
 * [`MOI.VectorAffineFunction{Float64}`](@ref) in [`MOI.PositiveSemidefiniteConeTriangle`](@ref)
