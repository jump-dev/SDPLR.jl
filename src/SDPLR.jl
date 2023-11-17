module SDPLR

using SDPLR_jll

function solve_sdpa_file(file)
    return run(`$(SDPLR_jll.sdplr()) $file`)
end

# Default values taken from `SDPLR-1.03-beta/source/params.c`
Base.@kwdef struct Parameters
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
    rankredtol::Cdouble = 2.2204460492503131e-16
    gaptol::Cdouble = 1.0e-3
    checkbd::Cptrdiff_t = -1
    typebd::Cptrdiff_t = 1
end

# See `macros.h`
datablockind(data, block, numblock) = data * numblock + block

function default_R(blktype::Vector{Cchar}, blksz, maxranks)
    # See `getstorage` in `main.c`
    nr = sum(eachindex(blktype)) do k
        if blktype[k] == Cchar('s')
            return blksz[k] * maxranks[k]
        else
            @assert blktype[k] == Cchar('d')
            return blksz[k]
        end
    end
    # In `main.c`, it does `(rand() / RAND_MAX) - (rand() - RAND_MAX)`` to take the difference between
    # two numbers between 0 and 1. Here, Julia's `rand()`` is already between 0 and 1 so we don't have
    # to divide by anything.
    return rand(nr) - rand(nr)
end

function default_maxranks(blktype, blksz, CAinfo_entptr, m)
    numblk = length(blktype)
    # See `getstorage` in `main.c`
    return map(eachindex(blktype)) do k
        if blktype[k] == Cchar('s')
            cons = count(1:m) do i
                ind = datablockind(i, k, numblk)
                return CAinfo_entptr[ind+1] > CAinfo_entptr[ind]
            end
            return Csize_t(min(isqrt(2cons) + 1, blksz[k]))
        else
            @assert blktype[k] == Cchar('d')
            return Csize_t(1)
        end
    end
end

"""
SDPA format (see `MOI.FileFormats.SDPA.Model`) with
matrices `C`, `A_1`, ..., `A_m`, `X` that are block
diagonal with `numblk` blocks and `b` is a length-`m`
vector.

Each block `1 <= k <= numblk` is has dimension `blksz[k] × blksz[k]`.
The `k`th block of `X` is computed as `R * R'` where `R` is of size
`blksz[k] × maxranks[k]` if `blktype[k]` is `Cchar('s')` and
`Diagonal(R)` where `R` is a vector of size `blksz[k]` if `blktype[k]`
is `Cchar('d')`.

The `CA...` arguments specify the `C` and `A_i` matrices.
"""
function solve(
    blksz::Vector{Cptrdiff_t},
    blktype::Vector{Cchar},
    b::Vector{Cdouble},
    CAent::Vector{Cdouble},
    CArow::Vector{Csize_t},
    CAcol::Vector{Csize_t},
    CAinfo_entptr::Vector{Csize_t},
    CAinfo_type::Vector{Cchar};
    params::Parameters = Parameters(),
    maxranks::Vector{Csize_t} = default_maxranks(
        blktype,
        blksz,
        CAinfo_entptr,
        length(b),
    ),
    ranks::Vector{Csize_t} = copy(maxranks),
    R::Vector{Cdouble} = default_R(blktype, blksz, maxranks),
    lambda::Vector{Cdouble} = zeros(length(b)),
    pieces::Vector{Cdouble} = Cdouble[0, 0, 0, 0, 0, 0, inv(sum(blksz)), 1],
)
    numblk = length(blksz)
    @assert length(blktype) == numblk
    m = length(b)
    @assert length(CAinfo_entptr) == (m + 1) * numblk + 1
    @assert length(CAinfo_type) == (m + 1) * numblk
    @assert length(CAent) == length(CArow) == length(CAcol)
    @assert length(lambda) == m
    @assert length(maxranks) == numblk
    @assert length(ranks) == numblk
    @assert length(pieces) == 8
    @assert CAinfo_entptr[1] == 0
    @assert CAinfo_entptr[end] == length(CArow)
    k = 0
    for _ in eachindex(b)
        for blk in eachindex(blksz)
            k += 1
            @assert CAinfo_entptr[k] <= CAinfo_entptr[k+1]
            for j in ((CAinfo_entptr[k]+1):CAinfo_entptr[k+1])
                @assert blktype[blk] == CAinfo_type[k]
                @assert 1 <= CArow[j] <= blksz[blk]
                @assert 1 <= CAcol[j] <= blksz[blk]
                if CAinfo_type[k] == Cchar('s')
                    @assert CArow[j] <= CAcol[j]
                else
                    @assert CAinfo_type[k] == Cchar('d')
                    @assert CArow[j] == CAcol[j]
                end
            end
        end
    end
    GC.@preserve blksz blktype b CAent CArow CAcol CAinfo_entptr CAinfo_type R lambda maxranks ranks pieces begin
        ret = @ccall SDPLR.SDPLR_jll.libsdplr.sdplrlib(
            m::Csize_t,
            numblk::Csize_t,
            blksz::Ptr{Cptrdiff_t},
            blktype::Ptr{Cchar},
            b::Ptr{Cdouble},
            CAent::Ptr{Cdouble},
            CArow::Ptr{Csize_t},
            CAcol::Ptr{Csize_t},
            CAinfo_entptr::Ptr{Csize_t},
            CAinfo_type::Ptr{Cchar},
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
            R::Ptr{Cdouble},
            lambda::Ptr{Cdouble},
            maxranks::Ptr{Csize_t},
            ranks::Ptr{Csize_t},
            pieces::Ptr{Cdouble},
        )::Csize_t
    end
    return ret, R, lambda, ranks, pieces
end

include("MOI_wrapper.jl")

end # module
