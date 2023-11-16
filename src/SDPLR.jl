module SDPLR

using SDPLR_jll

function solve_sdpa_file(file)
    return run(`$(SDPLR_jll.sdplr()) $file`)
end

function solve(
    blksz::Vector{Cptrdiff_t},
    blktype::Vector{Cchar},
    b::Vector{Cdouble},
    CAent::Vector{Cdouble},
    CArow::Vector{Csize_t},
    CAcol::Vector{Csize_t},
    CAinfo_entptr::Vector{Csize_t},
    CAinfo_type::Vector{Cchar},
    numbfgsvecs::Integer,
    rho_f::Cdouble,
    rho_c::Cdouble,
    sigmafac::Cdouble,
    rankreduce::Integer,
    gaptol::Cdouble,
    checkbd::Integer,
    typebd::Integer,
    dthresh_dim::Integer,
    dthresh_dens::Cdouble,
    timelim::Integer,
    rankredtol::Cdouble,
    printlevel::Integer,
    R::Vector{Cdouble},
    lambda::Vector{Cdouble},
    maxranks::Vector{Csize_t},
    ranks::Vector{Csize_t},
    pieces::Vector{Cdouble},
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
        numbfgsvecs::Csize_t,
        rho_f::Cdouble,
        rho_c::Cdouble,
        sigmafac::Cdouble,
        rankreduce::Csize_t,
        gaptol::Cdouble,
        checkbd::Cptrdiff_t,
        typebd::Csize_t,
        dthresh_dim::Csize_t,
        dthresh_dens::Cdouble,
        timelim::Csize_t,
        rankredtol::Cdouble,
        printlevel::Csize_t,
        R::Ptr{Cdouble},
        lambda::Ptr{Cdouble},
        maxranks::Ptr{Csize_t},
        ranks::Ptr{Csize_t},
        pieces::Ptr{Cdouble},
    )::Csize_t
    return ret
end

end # module
