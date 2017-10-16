module SDPLR

const BIN = "../deps/usr/bin/sdplr"

function solvesdpafile(file)
    run(`$BIN $file`)
end

end # module
