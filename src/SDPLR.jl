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
datablockind(data, block, numblock) = ((data + 1) - 1) * numblock + block

import Random
function default_R(blktype::Vector{Cchar}, blksz, maxranks)
    # See `getstorage` in `main.c`
    nr = sum(eachindex(blktype)) do k
        if blktype[k] == Cchar('s')
            return blksz[k] * maxranks[k]
        elseif blktype[k] == Cchar('d')
            return blksz[k]
        else
            return 0
        end
    end
    # In `main.c`, it does (rand() / RAND_MAX) - (rand() - RAND_MAX) to take the difference between
    # two numbers between 0 and 1. Here, Julia's rand() is already between 0 and 1 so we don't have
    # to divide.
    Random.seed!(925)
    return rand(nr) - rand(nr)
end

function default_maxranks(blktype, blksz, CAinfo_entptr)
    numblk = length(blktype)
    m = div(length(CAinfo_entptr) - 1, numblk) - 1
    # See `getstorage` in `main.c`
    return map(eachindex(blktype)) do k
        if blktype[k] == Cchar('s')
            cons = count(1:m) do i
                ind = datablockind(i, k, numblk)
                return CAinfo_entptr[ind+1] > CAinfo_entptr[ind]
            end
            return Csize_t(min(isqrt(2cons) + 1, blksz[k]))
        elseif blktype[k] == Cchar('d')
            return Csize_t(1)
        else
            return Csize_t(0)
        end
    end
end

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
    maxranks::Vector{Csize_t} = default_maxranks(blktype, blksz, CAinfo_entptr),
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
    return ret, R, lambda, ranks
end

end # module
