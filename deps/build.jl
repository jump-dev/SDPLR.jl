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

# Taken from SDPA.jl at deps/blaslapack.jl
function ldflags(; libpath=Libdl.dlpath(libname), libname=first(split(basename(libpath), '.', limit=2)))
    libdir = dirname(libpath)
    # I use [4:end] to drop the "lib" at the beginning
    linkname = libname[4:end]
    info("Using $libname at $libpath : -L$libpath -L$libdir -l$libname -l$linkname")
    "-L$libpath -L$libdir", "-l$libname -l$linkname -l$libpath -l$libname.DLL -l$libname.dll -l$linkname.DLL -l$linkname.dll"
end

function blas_lib()
    ldflags(libname=LinAlg.BLAS.libblas)
end

function lapack_lib()
    ldflags(libname=LinAlg.LAPACK.liblapack)
end

const BLAS_L, BLAS_l = blas_lib()
const LAPACK_L, LAPACK_l = lapack_lib()

using BinDeps

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
                    pipeline(`julia -e "println(raw\"LIBS += $BLAS_l $LAPACK_l\")"`, stdout="Makefile.inc.$osname", append=true)
                    pipeline(`julia -e "println(raw\"LIB_DIRS = $BLAS_L $LAPACK_L\")"`, stdout="Makefile.inc.$osname", append=true)
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
