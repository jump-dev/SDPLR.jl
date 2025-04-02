import MathOptInterface as MOI

const MAX_MAJITER = 100_000
const MAX_ITER = 10_000_000

const PIECES_MAP = Dict{String,Int}(
    "majiter" => 1,
    "iter" => 2,
    "lambdaupdate" => 3,
    "CG" => 4,
    "curr_CG" => 5,
    "totaltime" => 6,
    "sigma" => 7,
    "overallsc" => 8,
)

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
    # Solution
    Rmap::Vector{Int}
    maxranks::Vector{Csize_t}
    ranks::Vector{Csize_t}
    R::Vector{Cdouble}
    lambda::Vector{Cdouble}
    pieces::Union{Nothing,Vector{Cdouble}}
    set_pieces::Dict{Int,Cdouble}
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
            Csize_t[],
            Csize_t[],
            Cdouble[],
            Cdouble[],
            nothing,
            Dict{Int,Cdouble}(),
        )
    end
end

function MOI.supports(::Optimizer, param::MOI.RawOptimizerAttribute)
    return haskey(PIECES_MAP, param.name) ||
           hasfield(Parameters, Symbol(param.name))
end
function MOI.set(optimizer::Optimizer, param::MOI.RawOptimizerAttribute, value)
    if !MOI.supports(optimizer, param)
        throw(MOI.UnsupportedAttribute(param))
    end
    if haskey(PIECES_MAP, param.name)
        idx = PIECES_MAP[param.name]
        if isnothing(value)
            delete!(optimizer.set_pieces, idx)
        else
            optimizer.set_pieces[idx] = value
            if !isnothing(optimizer.pieces)
                optimizer.pieces[idx] = value
            end
        end
    else
        s = Symbol(param.name)
        if s == :maxrank
            reset_solution!(optimizer)
        end
        setfield!(optimizer.params, s, convert(fieldtype(Parameters, s), value))
    end
    return
end
function MOI.get(optimizer::Optimizer, param::MOI.RawOptimizerAttribute)
    if !MOI.supports(optimizer, param)
        throw(MOI.UnsupportedAttribute(param))
    end
    if haskey(PIECES_MAP, param.name)
        idx = PIECES_MAP[param.name]
        if isnothing(optimizer.pieces)
            return get(optimizer.set_pieces, idx, nothing)
        else
            return optimizer.pieces[idx]
        end
    else
        return getfield(optimizer.params, Symbol(param.name))
    end
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
    reset_solution!(model)
    offset = length(model.varmap)
    _new_block(model, set)
    ci = MOI.ConstraintIndex{MOI.VectorOfVariables,typeof(set)}(offset + 1)
    for i in eachindex(model.Ainfo_entptr)
        _fill_until(
            model,
            length(model.blksz),
            model.Ainfo_entptr[i],
            model.Ainfo_type[i],
            _next(model, i),
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

function _next(model::Optimizer, i)
    for j in (i+1):length(model.Ainfo_entptr)
        if !isempty(model.Ainfo_entptr[j])
            return first(model.Ainfo_entptr[j])
        end
    end
    return length(model.Aent)
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
    reset_solution!(model)
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
    params = deepcopy(model.params)
    if model.silent
        params.printlevel = 0
    end
    if isnothing(model.pieces)
        model.maxranks = default_maxranks(
            model.params.maxrank,
            model.blktype,
            model.blksz,
            CAinfo_entptr,
            length(model.b),
        )
        model.ranks = copy(model.maxranks)
        model.Rmap, model.R =
            default_R(model.blktype, model.blksz, model.maxranks)
        model.lambda = zeros(Cdouble, length(model.b))
        model.pieces = default_pieces(model.blksz)
        for (idx, val) in model.set_pieces
            model.pieces[idx] = val
        end
    end
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
        maxranks = model.maxranks,
        ranks = model.ranks,
        R = model.R,
        lambda = model.lambda,
        pieces = model.pieces,
    )
    return
end

function MOI.get(optimizer::Optimizer, ::MOI.RawStatusString)
    majiter, iter, λupdate, CG, curr_CG, totaltime, σ, overallsc =
        optimizer.pieces
    return "majiter = $majiter, iter = $iter, λupdate = $λupdate, CG = $CG, curr_CG = $curr_CG, totaltime = $totaltime, σ = $σ, overallsc = $overallsc"
end
function MOI.get(optimizer::Optimizer, ::MOI.SolveTimeSec)
    return MOI.get(optimizer, MOI.RawOptimizerAttribute("totaltime"))
end

function MOI.is_empty(optimizer::Optimizer)
    return isempty(optimizer.b) && isempty(optimizer.varmap)
end

function reset_solution!(optimizer::Optimizer)
    empty!(optimizer.Rmap)
    empty!(optimizer.maxranks)
    empty!(optimizer.ranks)
    empty!(optimizer.R)
    empty!(optimizer.lambda)
    optimizer.pieces = nothing
    return
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
    reset_solution!(optimizer)
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
    reset_solution!(model)
    sign = sense == MOI.MAX_SENSE ? -1 : 1
    if model.objective_sign != sign
        model.Cent .*= -1
        model.objective_sign = sign
    end
    return
end

function MOI.set(
    model::Optimizer,
    ::MOI.ObjectiveFunction,
    func::MOI.ScalarAffineFunction{Cdouble},
)
    reset_solution!(model)
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
    if model.objective_sign != 1
        model.Cent .*= -1
    end
    return
end

function MOI.get(model::Optimizer, ::MOI.TerminationStatus)
    if isnothing(model.pieces)
        return MOI.OPTIMIZE_NOT_CALLED
    elseif MOI.get(model, MOI.SolveTimeSec()) >=
           MOI.get(model, MOI.RawOptimizerAttribute("timelim"))
        return MOI.TIME_LIMIT
    elseif MOI.get(model, MOI.RawOptimizerAttribute("iter")) >= MAX_ITER ||
           MOI.get(model, MOI.RawOptimizerAttribute("majiter")) >= MAX_MAJITER
        return MOI.ITERATION_LIMIT
    else
        return MOI.LOCALLY_SOLVED
    end
end

function MOI.get(m::Optimizer, attr::Union{MOI.PrimalStatus,MOI.DualStatus})
    if attr.result_index > MOI.get(m, MOI.ResultCount())
        return MOI.NO_SOLUTION
    elseif MOI.get(m, MOI.TerminationStatus()) != MOI.LOCALLY_SOLVED
        return MOI.UNKNOWN_RESULT_STATUS
    else
        return MOI.FEASIBLE_POINT
    end
end

function MOI.get(model::Optimizer, ::MOI.ResultCount)
    if MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMIZE_NOT_CALLED
        return 0
    else
        return 1
    end
end

struct Factor <: MOI.AbstractConstraintAttribute end
MOI.is_set_by_optimize(::Factor) = true

function MOI.get(
    optimizer::Optimizer,
    ::Factor,
    ci::MOI.ConstraintIndex{MOI.VectorOfVariables,S},
) where {S<:SupportedSets}
    # The constraint index corresponds to the variable index of the `1, 1` entry
    blk, i, j = optimizer.varmap[ci.value]
    @assert i == j == 1
    I = (optimizer.Rmap[blk]+1):optimizer.Rmap[blk+1]
    r = optimizer.R[I]
    if S === MOI.PositiveSemidefiniteConeTriangle
        @assert optimizer.blktype[blk] == Cchar('s')
        d = optimizer.blksz[blk]
        return reshape(r, d, div(length(I), d))
    else
        @assert optimizer.blktype[blk] == Cchar('d')
        return r
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
        return optimizer.R[I[i]]^2
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
