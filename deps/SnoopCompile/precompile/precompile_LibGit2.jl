function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(LibGit2.GitRepoExt), String, UInt32})
    precompile(Tuple{typeof(LibGit2.GitRepoExt), String})
end
