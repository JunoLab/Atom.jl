function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(DelimitedFiles, Symbol("##writedlm#14")) && precompile(Tuple{getfield(DelimitedFiles, Symbol("##writedlm#14")), Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}, typeof(DelimitedFiles.writedlm), Base.IOContext{Base.GenericIOBuffer{Array{UInt8, 1}}}, Float64, Char})
    isdefined(DelimitedFiles, Symbol("##writedlm#14")) && precompile(Tuple{getfield(DelimitedFiles, Symbol("##writedlm#14")), Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}, typeof(DelimitedFiles.writedlm), Base.GenericIOBuffer{Array{UInt8, 1}}, Method, Char})
    isdefined(DelimitedFiles, Symbol("##writedlm#14")) && precompile(Tuple{getfield(DelimitedFiles, Symbol("##writedlm#14")), Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}, typeof(DelimitedFiles.writedlm), Base.IOContext{Base.GenericIOBuffer{Array{UInt8, 1}}}, Atom.EvalError{StackOverflowError}, Char})
    isdefined(DelimitedFiles, Symbol("##writedlm#14")) && precompile(Tuple{getfield(DelimitedFiles, Symbol("##writedlm#14")), Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}, typeof(DelimitedFiles.writedlm), Base.IOContext{Base.GenericIOBuffer{Array{UInt8, 1}}}, Atom.EvalError{Atom.DisplayError}, Char})
    precompile(Tuple{typeof(DelimitedFiles.writedlm), Base.GenericIOBuffer{Array{UInt8, 1}}, Method, Char})
    precompile(Tuple{typeof(DelimitedFiles.writedlm), Base.IOContext{Base.GenericIOBuffer{Array{UInt8, 1}}}, Atom.EvalError{StackOverflowError}, Char})
    precompile(Tuple{typeof(DelimitedFiles.writedlm), Base.IOContext{Base.GenericIOBuffer{Array{UInt8, 1}}}, Atom.EvalError{Atom.DisplayError}, Char})
end
