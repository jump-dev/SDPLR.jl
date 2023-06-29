module SDPLR

using SDPLR_jll

function solve_sdpa_file(file)
    return run(`$(SDPLR_jll.sdplr()) $file`)
end

end # module
