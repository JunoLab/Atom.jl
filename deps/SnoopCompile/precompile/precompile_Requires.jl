function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(Requires.__init__)})
    precompile(Tuple{typeof(Requires.loadpkg), Base.PkgId})
end
