edit(pkg) =
  isdir(Pkg.dir(pkg)) ?
    run(`atom $(Pkg.dir(pkg))`) :
    error("$pkg not installed")
