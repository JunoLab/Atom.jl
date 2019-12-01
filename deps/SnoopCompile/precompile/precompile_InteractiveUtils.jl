function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(InteractiveUtils._subtypes), Module, Type{Int}, Base.IdSet{Any}, Base.IdSet{Module}})
    precompile(Tuple{typeof(InteractiveUtils._subtypes_in), Array{Module, 1}, Type{Int}})
end
