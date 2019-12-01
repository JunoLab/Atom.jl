function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(CodeTools.flat_content!), Array{Any, 1}, Array{Any, 1}})
    precompile(Tuple{typeof(CodeTools.getthing), Module, String, Atom.Undefined})
    precompile(Tuple{typeof(CodeTools.getsubmod), Array{Base.SubString{String}, 1}})
    precompile(Tuple{typeof(CodeTools.getpackage), String})
    precompile(Tuple{typeof(CodeTools.getpackage), Base.SubString{String}})
    precompile(Tuple{typeof(CodeTools.getthing), Module, String, Nothing})
end
