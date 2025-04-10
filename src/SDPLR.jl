# Copyright (c) 2017: Benoît Legat and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

module SDPLR

import MathOptInterface as MOI
import SDPLR_jll

include("bounds.jl")

function solve_sdpa_file(file)
    return run(`$(SDPLR_jll.sdplr()) $file`)
end

# Default values taken from `SDPLR-1.03-beta/source/params.c`
Base.@kwdef mutable struct Parameters
    #inputtype = 1
    rho_f::Cdouble = 1.0e-5
    rho_c::Cdouble = 1.0e-1
    sigmafac::Cdouble = 2.0
    rankreduce::Csize_t = 0
    timelim::Csize_t = 3600
    printlevel::Csize_t = 1
    dthresh_dim::Csize_t = 10
    dthresh_dens::Cdouble = 0.75
    numbfgsvecs::Csize_t = 4
    rankredtol::Cdouble = eps(Cdouble)
    gaptol::Cdouble = 1.0e-3
    checkbd::Cptrdiff_t = -1
    typebd::Cptrdiff_t = 1
    # Given the number of constraints `m` involving the `n × n` matrix,
    # `maxrank(m, n)` should return the rank to use for the
    # factorization of the matrix.
    maxrank::Function = default_maxrank
end

# See `macros.h`
datablockind(data, block, numblock) = data * numblock + block

@kwdef struct Model
    blksz::Vector{Cptrdiff_t}
    blktype::Vector{Cchar}
    b::Vector{Cdouble}
    CAent::Vector{Cdouble}
    CArow::Vector{Csize_t}
    CAcol::Vector{Csize_t}
    CAinfo_entptr::Vector{Csize_t}
    CAinfo_type::Vector{Cchar}
end

function checkdims(model::Model)
    numblk = length(model.blksz)
    @assert length(model.blktype) == numblk
    m = length(model.b)
    @assert length(model.CAinfo_entptr) == (m + 1) * numblk + 1
    @assert length(model.CAinfo_type) == (m + 1) * numblk
    @assert length(model.CAent) == length(model.CArow) == length(model.CAcol)
    @assert model.CAinfo_entptr[1] == 0
    @assert model.CAinfo_entptr[end] == length(model.CArow)
    k = 0
    for _ in eachindex(model.b)
        for blk in eachindex(model.blksz)
            k += 1
            @assert model.CAinfo_entptr[k] <= model.CAinfo_entptr[k+1]
            for j in ((model.CAinfo_entptr[k]+1):model.CAinfo_entptr[k+1])
                @assert 1 <= model.CArow[j] <= model.blksz[blk]
                @assert 1 <= model.CAcol[j] <= model.blksz[blk]
                if model.CAinfo_type[k] == Cchar('s')
                    @assert model.blktype[blk] == Cchar('s') || model.blktype[blk] == Cchar('d')
                    @assert model.CArow[j] <= model.CAcol[j]
                elseif model.CAinfo_type[k] == Cchar('d')
                    @assert model.blktype[blk] == Cchar('d')
                    @assert model.CArow[j] == model.CAcol[j]
                else
                    @assert model.CAinfo_type[k] == Cchar('l')
                    @assert model.blktype[blk] == Cchar('s')
                end
            end
        end
    end
    return m, numblk
end

function write_sdplr(model::Model, filename::String)
    m, numblk = checkdims(model)
    open(filename, "w") do io
        println(io, m)
        println(io, numblk)
        println(io, join(model.blksz .* map(t -> t == 'd' ? -1 : 1, model.blktype), ' '))
        println(io, join(model.b, ' '))
        println(io, -1) # Currently ignored
        for constraint in 0:m
            for blk in eachindex(model.blksz)
                print(io, constraint)
                print(io, ' ')
                print(io, blk)
                print(io, ' ')
                cur = numblk * constraint + blk
                t = model.CAinfo_type[cur]
                range = 1 .+ (model.CAinfo_entptr[cur]:(model.CAinfo_entptr[cur + 1] - 1))
                if t == 'l'
                    print(io, 'l')
                    print(io, ' ')
                    print(io, div(length(range), model.blksz[blk] + 1))
                    for i in range
                        println(io, model.CAent[i])
                    end
                else
                    print(io, 's')
                    print(io, ' ')
                    print(io, length(range))
                    for i in range
                        print(io, model.CArow[i])
                        print(io, ' ')
                        print(io, model.CAcol[i])
                        print(io, ' ')
                        println(io, model.CAent[i])
                    end
                end
            end
        end
    end
end

function default_R(blktype::Vector{Cchar}, blksz, maxranks)
    # See `getstorage` in `main.c`
    Rsizes = map(eachindex(blktype)) do k
        if blktype[k] == Cchar('s')
            return blksz[k] * maxranks[k]
        else
            @assert blktype[k] == Cchar('d')
            return blksz[k]
        end
    end
    Rmap = [0; cumsum(Rsizes)]
    # In `main.c`, it does `(rand() / RAND_MAX) - (rand() - RAND_MAX)`` to take the difference between
    # two numbers between 0 and 1. Here, Julia's `rand()`` is already between 0 and 1 so we don't have
    # to divide by anything.
    nr = last(Rmap)
    # In `main.c`, it does `(rand() / RAND_MAX) - (rand() - RAND_MAX)`` to take the difference between
    # two numbers between 0 and 1. Here, Julia's `rand()`` is already between 0 and 1 so we don't have
    # to divide by anything.
    return Rmap, rand(nr) - rand(nr)
end

function default_maxranks(maxrank, blktype, blksz, CAinfo_entptr, m)
    numblk = length(blktype)
    # See `getstorage` in `main.c`
    return map(eachindex(blktype)) do k
        if blktype[k] == Cchar('s')
            # Because we do `1:m` and not `0:m`, we do not count the objective.
            # `maxrank` will increment our count by `1` assuming that it is
            # always part of the objective.
            cons = count(1:m) do i
                ind = datablockind(i, k, numblk)
                return CAinfo_entptr[ind+1] > CAinfo_entptr[ind]
            end
            return Csize_t(maxrank(cons, blksz[k]))
        else
            @assert blktype[k] == Cchar('d')
            return Csize_t(1)
        end
    end
end

function default_pieces(blksz)
    return Cdouble[0, 0, 0, 0, 0, 0, inv(sum(blksz)), 1]
end

"""
SDPA format (see `MOI.FileFormats.SDPA.Model`) with
matrices `C`, `A_1`, ..., `A_m`, `X` that are block
diagonal with `numblk` blocks and `b` is a length-`m`
vector.

Each block `1 <= k <= numblk` has dimension `blksz[k] × blksz[k]`.
The `k`th block of `X` is computed as `R * R'` where `R` is of size
`blksz[k] × maxranks[k]` if `blktype[k]` is `Cchar('s')` and
`Diagonal(R)` where `R` is a vector of size `blksz[k]` if `blktype[k]`
is `Cchar('d')`.

The `CA...` arguments specify the `C` and `A_i` matrices.
"""
function solve(
    model::Model;
    params::Parameters = Parameters(),
    maxranks::Vector{Csize_t} = default_maxranks(
        params.maxrank,
        model.blktype,
        model.blksz,
        model.CAinfo_entptr,
        length(model.b),
    ),
    ranks::Vector{Csize_t} = copy(maxranks),
    R::Vector{Cdouble} = default_R(model.blktype, model.blksz, maxranks)[2],
    lambda::Vector{Cdouble} = zeros(Cdouble, length(model.b)),
    pieces::Vector{Cdouble} = default_pieces(model.blksz),
)
    m, numblk = checkdims(model)
    @assert length(lambda) == m
    @assert length(maxranks) == numblk
    @assert length(ranks) == numblk
    @assert length(pieces) == 8
    GC.@preserve model R lambda maxranks ranks pieces begin
        ret = @ccall SDPLR_jll.libsdplr.sdplrlib(
            m::Csize_t,
            numblk::Csize_t,
            model.blksz::Ptr{Cptrdiff_t},
            model.blktype::Ptr{Cchar},
            model.b::Ptr{Cdouble},
            model.CAent::Ptr{Cdouble},
            model.CArow::Ptr{Csize_t},
            model.CAcol::Ptr{Csize_t},
            model.CAinfo_entptr::Ptr{Csize_t},
            model.CAinfo_type::Ptr{Cchar},
            params.numbfgsvecs::Csize_t,
            params.rho_f::Cdouble,
            params.rho_c::Cdouble,
            params.sigmafac::Cdouble,
            params.rankreduce::Csize_t,
            params.gaptol::Cdouble,
            params.checkbd::Cptrdiff_t,
            params.typebd::Csize_t,
            params.dthresh_dim::Csize_t,
            params.dthresh_dens::Cdouble,
            params.timelim::Csize_t,
            params.rankredtol::Cdouble,
            params.printlevel::Csize_t,
            # We can see in `source/main.c` that `R - 1` and `lambda - 1`
            # are passed to `sdplrlib` so we also need to shift by `-1`
            # by using `pointer(_, 0)`.
            pointer(R, 0)::Ptr{Cdouble},
            pointer(lambda, 0)::Ptr{Cdouble},
            maxranks::Ptr{Csize_t},
            ranks::Ptr{Csize_t},
            pieces::Ptr{Cdouble},
        )::Csize_t
    end
    return ret, R, lambda, ranks, pieces
end

include("MOI_wrapper.jl")

end # module
