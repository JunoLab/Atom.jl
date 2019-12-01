function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(REPL.REPLCompletions.find_dict_matches), Base.Dict{Symbol, Int64}, String})
    precompile(Tuple{typeof(REPL.REPLCompletions.filtered_mod_names), typeof(identity), Module, Base.SubString{String}, Bool, Bool})
    precompile(Tuple{typeof(REPL.lookup_doc), Expr})
    precompile(Tuple{typeof(REPL.REPLCompletions.get_type), Int64, Module})
    precompile(Tuple{typeof(REPL.REPLCompletions.get_type), Symbol, Module})
    precompile(Tuple{typeof(REPL.REPLCompletions.get_value), QuoteNode, Module})
    precompile(Tuple{typeof(REPL.REPLCompletions.get_value), Symbol, Module})
    precompile(Tuple{typeof(REPL.lookup_doc), Bool})
    precompile(Tuple{typeof(REPL.summarize), Base.GenericIOBuffer{Array{UInt8, 1}}, Int, Base.Docs.Binding})
    precompile(Tuple{typeof(REPL.REPLCompletions.get_type), String, Module})
end
