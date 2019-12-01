function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(Main, Symbol("#handle#3")) && precompile(Tuple{getfield(Main, Symbol("#handle#3")), String})
    isdefined(Main, Symbol("#handle#3")) && precompile(Tuple{getfield(Main, Symbol("#handle#3")), String, String})
    isdefined(Main, Symbol("#expect#4")) && precompile(Tuple{getfield(Main, Symbol("#expect#4")), Float64})
    isdefined(Main, Symbol("#expect#4")) && precompile(Tuple{getfield(Main, Symbol("#expect#4")), Int64})
    isdefined(Main, Symbol("#expect#4")) && precompile(Tuple{getfield(Main, Symbol("#expect#4")), Nothing})
    precompile(Tuple{typeof(Main.readmsg)})
    isdefined(Main, Symbol("#foo#103")) && precompile(Tuple{getfield(Main, Symbol("#foo#103"))})
    isdefined(Main, Symbol("#expect#4")) && precompile(Tuple{getfield(Main, Symbol("#expect#4")), String})
    isdefined(Main, Symbol("#updatesymbols#75")) && precompile(Tuple{getfield(Main, Symbol("#updatesymbols#75")), String, String, String})
    isdefined(Main, Symbol("#outline#33")) && precompile(Tuple{getfield(Main, Symbol("#outline#33")), String})
end
