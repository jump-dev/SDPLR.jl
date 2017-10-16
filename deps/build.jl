SDPLRname = "SDPLR-1.03-beta"

uri = "http://sburer.github.io/files/SDPLR-1.03-beta.zip"

pkgdir  = Pkg.dir("SDPLR")
rootdir = joinpath(pkgdir, "deps")
dwndir  = joinpath(rootdir, "downloads")
zipfile = joinpath(dwndir, "SDPLR-1.03-beta.zip")
dirsrc  = joinpath(rootdir, "src")
_srcdir  = joinpath(dirsrc, SDPLRname)
_bindir  = joinpath(rootdir, "usr", "bin")

osname = "linux"
@static if is_apple()
    osname = "mac"
elseif is_windows()
    osname = "mingw"
end

using BinDeps

BinDeps.run(@build_steps begin
        CreateDirectory(dwndir)
       `curl -f -o $zipfile -L $uri`
        CreateDirectory(dirsrc)
        `unzip -x $zipfile -d $dirsrc`
        CreateDirectory(_bindir)
        @build_steps begin
            ChangeDirectory(_srcdir)
            `cp Makefile.inc.$osname Makefile.inc`
            `make`
            `mv $_srcdir/sdplr $_bindir/sdplr`
        end
    end)
