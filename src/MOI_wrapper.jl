# This file modifies code from SDPAFamily.jl (https://github.com/ericphanson/SDPAFamily.jl/), which is available under an MIT license (see LICENSE).

import MathOptInterface as MOI

const SupportedSets =
    Union{MOI.Nonnegatives,MOI.PositiveSemidefiniteConeTriangle}

mutable struct Optimizer <: MOI.AbstractOptimizer
    objective_constant::Float64
    objective_sign::Int
    blksz::Vector{Cptrdiff_t}
    blktype::Vector{Cchar}
    varmap::Vector{Tuple{Int,Int,Int}} # Variable Index vi -> blk, i, j
    b::Vector{Cdouble}
    Cent::Vector{Cdouble}
    Crow::Vector{Csize_t}
    Ccol::Vector{Csize_t}
    Cinfo_entptr::Vector{Csize_t}
    Cinfo_type::Vector{Cchar}
    Aent::Vector{Cdouble}
    Arow::Vector{Csize_t}
    Acol::Vector{Csize_t}
    Ainfo_entptr::Vector{Vector{Csize_t}}
    Ainfo_type::Vector{Vector{Cchar}}
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
            Tuple{Int,Int,Int}[],
            Cdouble[],
            Cdouble[],
            Csize_t[],
            Csize_t[],
            Csize_t[],
            Cchar[],
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
    s = Symbol(param.name)
    setfield!(optimizer.params, s, convert(fieldtype(Parameters, s), value))
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

function MOI.supports_add_constrained_variables(::Optimizer, ::Type{MOI.Reals})
    return false
end

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{<:SupportedSets},
)
    return true
end

function _new_block(model::Optimizer, set::MOI.Nonnegatives)
    push!(model.blksz, MOI.dimension(set))
    push!(model.blktype, Cchar('d'))
    blk = length(model.blksz)
    for i in 1:MOI.dimension(set)
        push!(model.varmap, (blk, i, i))
    end
    return
end

function _new_block(model::Optimizer, set::MOI.PositiveSemidefiniteConeTriangle)
    push!(model.blksz, set.side_dimension)
    push!(model.blktype, Cchar('s'))
    blk = length(model.blksz)
    for j in 1:set.side_dimension
        for i in 1:j
            push!(model.varmap, (blk, i, j))
        end
    end
    return
end

function MOI.add_constrained_variables(model::Optimizer, set::SupportedSets)
    offset = length(model.varmap)
    _new_block(model, set)
    ci = MOI.ConstraintIndex{MOI.VectorOfVariables,typeof(set)}(offset + 1)
    for i in eachindex(model.Ainfo_entptr)
        _fill_until(
            model,
            length(model.blksz),
            model.Ainfo_entptr[i],
            model.Ainfo_type[i],
            _prev(model, i),
        )
    end
    _fill_until(
        model,
        length(model.blksz),
        model.Cinfo_entptr,
        model.Cinfo_type,
        length(model.Cent),
    )
    return [MOI.VariableIndex(i) for i in offset .+ (1:MOI.dimension(set))], ci
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{Cdouble}},
    ::Type{MOI.EqualTo{Cdouble}},
)
    return true
end

function _isless(t1::MOI.VectorAffineTerm, t2::MOI.VectorAffineTerm)
    if t1.scalar_term.variable.value == t2.scalar_term.variable.value
        return isless(t1.output_index, t2.output_index)
    else
        return isless(
            t1.scalar_term.variable.value,
            t2.scalar_term.variable.value,
        )
    end
end

function _prev(model::Optimizer, i)
    prev = 0
    for j in i:-1:1
        if !isempty(model.Ainfo_entptr[j])
            prev = last(model.Ainfo_entptr[j])
        end
    end
    return prev
end

function _fill_until(
    model::Optimizer,
    numblk,
    entptr::Vector{Csize_t},
    type::Vector{Cchar},
    prev,
)
    @assert length(type) == length(entptr)
    while length(type) < numblk
        blk = length(type) + 1
        push!(type, model.blktype[blk])
        push!(entptr, prev)
    end
    @assert length(type) == numblk
    @assert length(entptr) == numblk
    return
end

function _fill!(
    model,
    ent,
    row,
    col,
    entptr::Vector{Csize_t},
    type::Vector{Cchar},
    func,
)
    for t in MOI.Utilities.canonical(func).terms
        blk, i, j = model.varmap[t.variable.value]
        _fill_until(model, blk, entptr, type, length(ent))
        coef = t.coefficient
        if i != j
            coef /= 2
        end
        push!(ent, coef)
        push!(row, i)
        push!(col, j)
    end
    _fill_until(model, length(model.blksz), entptr, type, length(ent))
    @assert length(entptr) == length(model.blksz)
    @assert length(type) == length(model.blksz)
end

function MOI.add_constraint(
    model::Optimizer,
    func::MOI.ScalarAffineFunction{Cdouble},
    set::MOI.EqualTo{Cdouble},
)
    push!(model.Ainfo_entptr, Csize_t[])
    push!(model.Ainfo_type, Cchar[])
    _fill!(
        model,
        model.Aent,
        model.Arow,
        model.Acol,
        model.Ainfo_entptr[end],
        model.Ainfo_type[end],
        func,
    )
    push!(model.b, MOI.constant(set) - MOI.constant(func))
    return MOI.ConstraintIndex{typeof(func),typeof(set)}(length(model.b))
end

MOI.supports_incremental_interface(::Optimizer) = true

function MOI.copy_to(dest::Optimizer, src::MOI.ModelLike)
    return MOI.Utilities.default_copy_to(dest, src)
end

function MOI.optimize!(model::Optimizer)
    CAent = vcat(model.Cent, model.Aent)
    CArow = vcat(model.Crow, model.Arow)
    CAcol = vcat(model.Ccol, model.Acol)
    @assert length(model.Cinfo_entptr) == length(model.blksz)
    @assert length(model.Cinfo_type) == length(model.blksz)
    for i in eachindex(model.Ainfo_entptr)
        @assert length(model.Ainfo_entptr[i]) == length(model.blksz)
        @assert length(model.Ainfo_type[i]) == length(model.blksz)
    end
    CAinfo_entptr = reduce(
        vcat,
        vcat([model.Cinfo_entptr], model.Ainfo_entptr),
        init = Csize_t[],
    )
    for i in (length(model.Cinfo_entptr)+1):length(CAinfo_entptr)
        CAinfo_entptr[i] += length(model.Cent)
    end
    push!(CAinfo_entptr, length(CAent))
    CAinfo_type =
        reduce(vcat, vcat([model.Cinfo_type], model.Ainfo_type), init = Cchar[])
    maxranks = default_maxranks(
        model.blktype,
        model.blksz,
        CAinfo_entptr,
        length(model.b),
    )
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
    params = deepcopy(model.params)
    if model.silent
        params.printlevel = 0
    end
    R = rand(nr) - rand(nr)
    _, model.R, model.lambda, model.ranks, model.pieces = solve(
        model.blksz,
        model.blktype,
        model.b,
        CAent,
        CArow,
        CAcol,
        CAinfo_entptr,
        CAinfo_type,
        params = params,
        maxranks = maxranks,
        R = R,
    )
    return
end

function MOI.get(optimizer::Optimizer, ::MOI.RawStatusString)
    majiter, iter, λupdate, CG, curr_CG, totaltime, σ, overallsc =
        optimizer.pieces
    return "majiter = $majiter, iter = $iter, λupdate = $λupdate, CG = $CG, curr_CG = $curr_CG, totaltime = $totaltime, σ = $σ, overallsc = $overallsc"
end
function MOI.get(optimizer::Optimizer, ::MOI.SolveTimeSec)
    return optimizer.pieces[6]
end

function MOI.is_empty(optimizer::Optimizer)
    return isempty(optimizer.b) && isempty(optimizer.varmap)
end

function MOI.empty!(optimizer::Optimizer)
    optimizer.objective_constant = 0.0
    optimizer.objective_sign = 1
    empty!(optimizer.blksz)
    empty!(optimizer.blktype)
    empty!(optimizer.varmap)
    empty!(optimizer.b)
    empty!(optimizer.Cent)
    empty!(optimizer.Crow)
    empty!(optimizer.Ccol)
    empty!(optimizer.Cinfo_entptr)
    empty!(optimizer.Cinfo_type)
    empty!(optimizer.Aent)
    empty!(optimizer.Arow)
    empty!(optimizer.Acol)
    empty!(optimizer.Ainfo_entptr)
    empty!(optimizer.Ainfo_type)
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

function MOI.set(
    model::Optimizer,
    ::MOI.ObjectiveSense,
    sense::MOI.OptimizationSense,
)
    sign = sense == MOI.MAX_SENSE ? -1 : 1
    if model.objective_sign != sign
        model.b .*= -1
        model.objective_sign = sign
    end
    return
end

function MOI.set(
    model::Optimizer,
    ::MOI.ObjectiveFunction,
    func::MOI.ScalarAffineFunction{Cdouble},
)
    model.objective_constant = MOI.constant(func)
    empty!(model.Cent)
    empty!(model.Crow)
    empty!(model.Ccol)
    empty!(model.Cinfo_entptr)
    empty!(model.Cinfo_type)
    _fill!(
        model,
        model.Cent,
        model.Crow,
        model.Ccol,
        model.Cinfo_entptr,
        model.Cinfo_type,
        func,
    )
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

function MOI.get(
    optimizer::Optimizer,
    attr::MOI.VariablePrimal,
    vi::MOI.VariableIndex,
)
    MOI.check_result_index_bounds(optimizer, attr)
    blk, i, j = optimizer.varmap[vi.value]
    I = (optimizer.Rmap[blk]+1):optimizer.Rmap[blk+1]
    if optimizer.blktype[blk] == Cchar('s')
        d = optimizer.blksz[blk]
        U = reshape(optimizer.R[I], d, div(length(I), d))
        return U[i, :]' * U[j, :]
    else
        @assert optimizer.blktype[blk] == Cchar('d')
        return optimizer.R[I[i]]
    end
end

function MOI.get(
    optimizer::Optimizer,
    attr::MOI.ConstraintDual,
    ci::MOI.ConstraintIndex{
        MOI.ScalarAffineFunction{Cdouble},
        MOI.EqualTo{Cdouble},
    },
)
    MOI.check_result_index_bounds(optimizer, attr)
    return optimizer.lambda[ci.value]
end
