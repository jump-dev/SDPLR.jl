SDPLRname = "SDPLR-1.03-beta"

uri = "http://sburer.github.io/files/$SDPLRname.zip"

pkgdir  = Pkg.dir("SDPLR")
rootdir = joinpath(pkgdir, "deps")
dwndir  = joinpath(rootdir, "downloads")
zipfile = joinpath(dwndir, "$SDPLRname.zip")
dirsrc  = joinpath(rootdir, "src")
_srcdir = joinpath(dirsrc, SDPLRname)
_bindir = joinpath(rootdir, "usr", "bin")

osname = "linux"
@static if is_apple()
    osname = "mac"
elseif is_windows()
    osname = "mingw"
end

function _libdir(libname)
    @show libname
    libpath=Libdl.dlpath(libname)
    @show libpath
    libdir = dirname(libpath)
    @show libdir
    libdir
end

function julia_blas_lib()
    _libdir(LinAlg.BLAS.libblas)
end

function julia_lapack_lib()
    _libdir(LinAlg.LAPACK.liblapack)
end

using BinDeps

@show `julia -e "println(raw\"LAPACK_LIB_DIR=$(julia_lapack_lib())\")" >> Makefile.inc.$osname`

BinDeps.run(@build_steps begin
        CreateDirectory(dwndir)
       `curl -f -o $zipfile -L $uri`
        CreateDirectory(dirsrc)
        `unzip -x $zipfile -d $dirsrc`
        CreateDirectory(_bindir)
        @build_steps begin
            ChangeDirectory(_srcdir)
            @static if is_windows()
                @build_steps begin
                    pipeline(`patch -N -p0`, stdin="$rootdir/blas_lapack_mingw.patch")
                    `julia -e "println(raw\"LAPACK_LIB_DIR=$(julia_lapack_lib())\")"`
                    pipeline(`julia -e "println(raw\"LAPACK_LIB_DIR=$(julia_lapack_lib())\")"`, stdout="Makefile.inc.$osname", append=true)
                    `julia -e "println(raw\"BLAS_LIB_DIR=$(julia_blas_lib())\")"`
                    pipeline(`julia -e "println(raw\"BLAS_LIB_DIR=$(julia_blas_lib())\")"`, stdout="Makefile.inc.$osname", append=true)
                    `julia -e "println(raw\"LIB_DIRS = -L\$(LAPACK_LIB_DIR) -L\$(BLAS_LIB_DIR)\")"`
                    `julia -e "println(raw\"LIB_DIRS = -L$(Libdl.dlpath(LinAlg.LAPACK.liblapack)) -L\$(LAPACK_LIB_DIR) -L$(Libdl.dlpath(LinAlg.BLAS.libblas)) -L\$(BLAS_LIB_DIR)\")"`
                    pipeline(`julia -e "println(raw\"LIB_DIRS = -L$(Libdl.dlpath(LinAlg.LAPACK.liblapack)) -L\$(LAPACK_LIB_DIR) -L$(Libdl.dlpath(LinAlg.BLAS.libblas)) -L\$(BLAS_LIB_DIR)\")"`, stdout="Makefile.inc.$osname", append=true)
                end
            end
            `cp Makefile.inc.$osname Makefile.inc`
            pipeline(`patch -N -p0`, stdin="$rootdir/main_argc.patch")
            @static if is_windows()
                @build_steps begin
                    pipeline(`patch -N -p0`, stdin="$rootdir/windows.patch")
                    `mingw32-make mingw`
                end
            else
                `make`
            end
            `mv $_srcdir/sdplr $_bindir/sdplr`
        end
    end)
