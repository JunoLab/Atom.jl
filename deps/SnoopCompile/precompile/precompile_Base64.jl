function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(Base64, Symbol("##stringmime#7")) && precompile(Tuple{getfield(Base64, Symbol("##stringmime#7")), Nothing, typeof(Base64.stringmime), String, String})
    isdefined(Base64, Symbol("#kw##stringmime")) && precompile(Tuple{getfield(Base64, Symbol("#kw##stringmime")), NamedTuple{(:context,), Tuple{Nothing}}, typeof(Base64.stringmime), Base.Multimedia.MIME{Symbol("text/plain")}, String})
end
