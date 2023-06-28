module SDPLR

using SDPLR_jll

function solve_sdpa_file(file)
    run(`$(SDPLR_jll.sdplr_path) $file`)
end

end # module
