# This file modifies code from SDPAFamily.jl (https://github.com/ericphanson/SDPAFamily.jl/), which is available under an MIT license (see LICENSE).

import MathOptInterface as MOI

mutable struct Optimizer <: MOI.AbstractOptimizer
    objective_constant::Float64
    objective_sign::Int
    blksz::Vector{Cptrdiff_t}
    blktype::Vector{Cchar}
    b::Vector{Cdouble}
    CAent::Vector{Cdouble}
    CArow::Vector{Csize_t}
    CAcol::Vector{Csize_t}
    CAinfo_entptr::Vector{Vector{Csize_t}}
    CAinfo_type::Vector{Vector{Cchar}}
    silent::Bool
    params::Parameters
    Rmap::Vector{Int}
    R::Union{Nothing,Vector{Cdouble}}
    lambda::Vector{Cdouble}
    ranks::Vector{Csize_t}
    pieces::Union{Nothing,Vector{Cdouble}}
    function Optimizer()
        return new(
            0.0,
            1,
            Cptrdiff_t[],
            Cchar[],
            Cdouble[],
            Cdouble[],
            Csize_t[],
            Csize_t[],
            Vector{Csize_t}[],
            Vector{Cchar}[],
            false,
            Parameters(),
            Int[],
            nothing,
            Cdouble[],
            Csize_t[],
            nothing,
        )
    end
end

function MOI.supports(::Optimizer, param::MOI.RawOptimizerAttribute)
    return hasfield(Parameters, Symbol(param.name))
end
function MOI.set(optimizer::Optimizer, param::MOI.RawOptimizerAttribute, value)
    if !MOI.supports(optimizer, param)
        throw(MOI.UnsupportedAttribute(param))
    end
    setfield!(optimizer.params, Symbol(param.name), value)
    return
end
function MOI.get(optimizer::Optimizer, param::MOI.RawOptimizerAttribute)
    if !MOI.supports(optimizer, param)
        throw(MOI.UnsupportedAttribute(param))
    end
    getfield!(optimizer.params, Symbol(param.name))
    return
end

MOI.supports(::Optimizer, ::MOI.Silent) = true
function MOI.set(optimizer::Optimizer, ::MOI.Silent, value::Bool)
    optimizer.silent = value
    return
end

MOI.get(optimizer::Optimizer, ::MOI.Silent) = optimizer.silent

MOI.get(::Optimizer, ::MOI.SolverName) = "SDPLR"

function MOI.add_variable(model::Optimizer)
    prev = 0
    push!(model.b, 0.0)
    for blk in eachindex(model.blktype)
        cur = model.CAinfo_entptr[blk]
        if !isempty(cur)
            prev = last(cur)
        end
        push!(cur, prev)
        # This doesn't matter since the `entptr` is the same as the previous one
        push!(model.CAinfo_type[blk], model.blktype[k])
    end
    return MOI.VariableIndex(length(model.b))
end

const SupportedSets = Union{MOI.Nonnegatives,MOI.PositiveSemidefiniteConeTriangle}

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorAffineFunction{Cdouble}},
    ::Type{<:SupportedSets},
)
    return true
end

function _isless(t1::MOI.VectorAffineTerm, t2::MOI.VectorAffineTerm)
    if t1.scalar_term.variable.value == t2.scalar_term.variable.value
        return isless(t1.output_index, t2.output_index)
    else
        return isless(t1.scalar_term.variable.value, t2.scalar_term.variable.value)
    end
end

function _fill_until(model::Optimizer, i)
    while length(model.CAinfo_type[end]) <= i
        push!(model.CAinfo_type[end], model.blktype[end])
        push!(model.CAinfo_entptr[end], length(model.CAent))
    end
    return
end

_size(set::MOI.Nonnegatives) = set.dimension
_size(set::MOI.PositiveSemidefiniteConeTriangle) = set.side_dimension

_type(::MOI.Nonnegatives) = Cchar('d')
_type(::MOI.PositiveSemidefiniteConeTriangle) = Cchar('s')

_row_col(index, ::MOI.Nonnegatives) = index, index
function _row_col(index, ::MOI.PositiveSemidefiniteConeTriangle)
    return MOI.Utilities.reverse_trimap(index)
end

function _add_entry(model::Optimizer, entry, i, index, set)
    _fill_until(model, i)
    push!(model.CAent, entry)
    row, col = _row_col(index, set)
    push!(model.CArow, row)
    push!(model.CAcol, col)
    return
end

function MOI.add_constraint(
    model::Optimizer,
    func::MOI.VectorAffineFunction{Cdouble},
    set::Union{MOI.Nonnegatives,MOI.PositiveSemidefiniteConeTriangle},
)
    push!(model.blksz, _size(set))
    push!(model.blktype, _type(set))
    push!(model.CAinfo_entptr, Csize_t[])
    push!(model.CAinfo_type, Cchar[])
    _fill_until(model, 0)
    for i in eachindex(func.constants)
        c = func.constants[i]
        if !iszero(c)
            push!(model.CAent, c)
            push!(model.CArow, i)
            push!(model.CAcol, i)
        end
    end
    i = -1
    index = 0
    entry = 0.0
    for term in sort(func.terms, lt = _isless)
        if i != term.scalar_term.variable.value ||
            index != term.output_index
            _add_entry(model, entry, i, index, set)
            i = term.scalar_term.variable.value
            index = term.output_index
            entry = 0.0
        end
        entry += term.scalar_term.coefficient
    end
    if i != -1
        _add_entry(model, entry, i, index, set)
    end
    _fill_until(model, length(model.b))
    return MOI.ConstraintIndex{typeof(func),typeof(set)}(length(model.blksz))
end

MOI.supports_incremental_interface(::Optimizer) = true

function MOI.copy_to(dest::Optimizer, src::MOI.ModelLike)
    return MOI.Utilities.default_copy_to(dest, src)
end

function MOI.optimize!(model::Optimizer)
    CAinfo_entptr = reduce(vcat, model.CAinfo_entptr, init = Csize_t[])
    push!(CAinfo_entptr, length(model.CAent))
    maxranks = default_maxranks(model.blktype, model.blksz, CAinfo_entptr, length(model.b))
    Rsizes = map(eachindex(model.blktype)) do k
        if model.blktype[k] == Cchar('s')
            return model.blksz[k] * maxranks[k]
        else
            @assert model.blktype[k] == Cchar('d')
            return model.blksz[k]
        end
    end
    model.Rmap = [0; cumsum(Rsizes)]
    # In `main.c`, it does `(rand() / RAND_MAX) - (rand() - RAND_MAX)`` to take the difference between
    # two numbers between 0 and 1. Here, Julia's `rand()`` is already between 0 and 1 so we don't have
    # to divide by anything.
    nr = last(model.Rmap)
    R = rand(nr) - rand(nr)
    _, model.R, model.lambda, model.ranks, model.pieces = solve(
        model.blksz, model.blktype, model.b, model.CAent,
        model.CArow, model.CAcol, CAinfo_entptr,
        reduce(vcat, model.CAinfo_type, init = Cchar[]);
        params = model.params,
        maxranks = maxranks, R = R,
    )
    return
end

function MOI.get(optimizer::Optimizer, ::MOI.RawStatusString)
    majiter, iter, λupdate, CG, curr_CG, totaltime, σ, overallsc = optimizer.pieces
    return "majiter = $majiter, iter = $iter, λupdate = $λupdate, CG = $CG, curr_CG = $curr_CG, totaltime = $totaltime, σ = $σ, overallsc = $overallsc"
end
function MOI.get(optimizer::Optimizer, ::MOI.SolveTimeSec)
    return optimizer.pieces[6]
end

function MOI.is_empty(optimizer::Optimizer)
    return iszero(optimizer.b)
end

function MOI.empty!(optimizer::Optimizer)
    optimizer.objective_constant = 0.0
    optimizer.objective_sign = 1
    empty!(optimizer.blksz)
    empty!(optimizer.blktype)
    empty!(optimizer.b)
    empty!(optimizer.CAent)
    empty!(optimizer.CArow)
    empty!(optimizer.CAcol)
    empty!(optimizer.CAinfo_entptr)
    empty!(optimizer.CAinfo_type)
    empty!(optimizer.Rmap)
    optimizer.R = nothing
    empty!(optimizer.lambda)
    empty!(optimizer.ranks)
    optimizer.pieces = nothing
    return
end

function MOI.supports(
    ::Optimizer,
    ::Union{
        MOI.ObjectiveSense,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Cdouble}},
    },
)
    return true
end

function MOI.set(model::Optimizer, ::MOI.ObjectiveSense, sense::MOI.OptimizationSense)
    sign = sense == MOI.MAX_SENSE ? -1 : 1
    if model.objective_sign != sign
        rmul!(model.b, -1)
        model.objective_sign = sign
    end
    return
end

function MOI.set(model::Optimizer, ::MOI.ObjectiveFunction, func::MOI.ScalarAffineFunction{Cdouble})
    model.objective_constant = MOI.constant(func)
    for i in eachindex(model.b)
        model.b[i] = 0.0
    end
    for t in func.terms
        model.b[t.variable.value] += model.objective_sense * t.coefficient
    end
    return
end

function MOI.get(model::Optimizer, ::MOI.TerminationStatus)
    if isnothing(model.pieces)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        return MOI.LOCALLY_SOLVED
    end
end

function MOI.get(m::Optimizer, attr::MOI.PrimalStatus)
    if attr.result_index > MOI.get(m, MOI.ResultCount())
        return MOI.NO_SOLUTION
    end
    return MOI.FEASIBLE_POINT
end

function MOI.get(m::Optimizer, attr::MOI.DualStatus)
    if attr.result_index > MOI.get(m, MOI.ResultCount())
        return MOI.NO_SOLUTION
    end
    return MOI.FEASIBLE_POINT
end

function MOI.get(model::Optimizer, ::MOI.ResultCount)
    if MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        return 0
    else
        return 1
    end
end

function MOI.get(m::Optimizer, attr::MOI.ObjectiveValue)
    MOI.check_result_index_bounds(m, attr)
    return m.objsign * m.primalobj + m.objective_constant
end

function MOI.get(m::Optimizer, attr::MOI.DualObjectiveValue)
    MOI.check_result_index_bounds(m, attr)
    return m.objsign * m.dualobj + m.objective_constant
end

function MOI.get(
    optimizer::Optimizer,
    attr::MOI.VariablePrimal,
    vi::MOI.VariableIndex,
)
    MOI.check_result_index_bounds(optimizer, attr)
    return optimizer.lambda[vi.value]
end

_reshape(x, d, ::Type{MOI.Nonnegatives}) = x
function _reshape(x, d, ::Type{MOI.PositiveSemidefiniteConeTriangle})
    U = reshape(x, d, div(length(x), d))
    X = U * U'
    return [X[i, j] for j in 1:d for i in 1:j]
end

function MOI.get(
    optimizer::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{MOI.VectorAffineFunction{Cdouble},S},
) where {S<:SupportedSets}
    MOI.check_result_index_bounds(optimizer, attr)
    block = ci.value
    return _reshape(
        optimizer.R[optimizer.Rmap[block]:optimizer.Rmap[block + 1]],
        optimizer.blksz[block],
        S,
    )
end
