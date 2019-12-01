function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(Core.throw_inexacterror), Symbol, Type{Int32}, Int128})
    isdefined(Core, Symbol("#@doc")) && precompile(Tuple{getfield(Core, Symbol("#@doc")), LineNumberNode, Module, Int})
    precompile(Tuple{typeof(Core.Compiler.zero), Type{Int128}})
    precompile(Tuple{typeof(Core.Compiler.eltype), Type{Array{DataType, 1}}})
    precompile(Tuple{typeof(Core.Compiler.zero), Type{UInt8}})
    precompile(Tuple{typeof(Core.Compiler.eltype), Type{Array{Array{Base.StackTraces.StackFrame, 1}, 1}}})
    precompile(Tuple{typeof(Core.Compiler.eltype), Type{Array{Union{Type{Int64}, Type{String}}, 1}}})
    isdefined(Core, Symbol("#kw#Type")) && precompile(Tuple{getfield(Core, Symbol("#kw#Type")), NamedTuple{(:href,), Tuple{String}}, Type{Hiccup.Node{tag} where tag}, Symbol, Array{Hiccup.Node{:code}, 1}})
end
