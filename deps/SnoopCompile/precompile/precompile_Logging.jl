function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(Logging, Symbol("##handle_message#2")) && precompile(Tuple{getfield(Logging, Symbol("##handle_message#2")), Nothing, Base.Iterators.Pairs{Symbol, Int64, Tuple{Symbol}, NamedTuple{(:progress,), Tuple{Int64}}}, typeof(Base.CoreLogging.handle_message), Logging.ConsoleLogger, Base.CoreLogging.LogLevel, String, Module, String, String, String, Int64})
    isdefined(Logging, Symbol("##handle_message#2")) && precompile(Tuple{getfield(Logging, Symbol("##handle_message#2")), Nothing, Base.Iterators.Pairs{Symbol, Float64, Tuple{Symbol}, NamedTuple{(:progress,), Tuple{Float64}}}, typeof(Base.CoreLogging.handle_message), Logging.ConsoleLogger, Base.CoreLogging.LogLevel, String, Module, String, String, String, Int64})
    isdefined(Logging, Symbol("##handle_message#2")) && precompile(Tuple{getfield(Logging, Symbol("##handle_message#2")), Nothing, Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}, typeof(Base.CoreLogging.handle_message), Logging.ConsoleLogger, Base.CoreLogging.LogLevel, MethodError, Module, String, Symbol, String, Int64})
    precompile(Tuple{typeof(Logging.default_metafmt), Base.CoreLogging.LogLevel, Module, String, Symbol, String, Int64})
    precompile(Tuple{typeof(Logging.default_metafmt), Base.CoreLogging.LogLevel, Module, String, String, String, Int64})
end
