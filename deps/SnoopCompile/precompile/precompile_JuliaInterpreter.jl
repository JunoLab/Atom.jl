function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(JuliaInterpreter.locals), JuliaInterpreter.Frame})
    precompile(Tuple{typeof(JuliaInterpreter.set_compiled_methods)})
    precompile(Tuple{typeof(JuliaInterpreter.caller), Nothing})
    precompile(Tuple{typeof(JuliaInterpreter.sparam_syms), Method})
    precompile(Tuple{typeof(JuliaInterpreter.__init__)})
    precompile(Tuple{typeof(JuliaInterpreter.traverse), typeof(JuliaInterpreter.caller), Nothing})
    precompile(Tuple{typeof(JuliaInterpreter.root), Nothing})
end
