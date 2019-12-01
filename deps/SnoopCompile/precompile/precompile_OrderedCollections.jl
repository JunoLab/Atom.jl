function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(OrderedCollections, Symbol("##sort!#7")) && precompile(Tuple{getfield(OrderedCollections, Symbol("##sort!#7")), Bool, Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}, typeof(Base.sort!), OrderedCollections.OrderedDict{String, String}})
    precompile(Tuple{typeof(OrderedCollections.rehash!), OrderedCollections.OrderedDict{String, String}, Int64})
    precompile(Tuple{typeof(OrderedCollections.ht_keyindex2), OrderedCollections.OrderedDict{String, String}, String})
    precompile(Tuple{typeof(OrderedCollections._setindex!), OrderedCollections.OrderedDict{String, String}, String, String, Int64})
    isdefined(OrderedCollections, Symbol("##sort#8")) && precompile(Tuple{getfield(OrderedCollections, Symbol("##sort#8")), Base.Iterators.Pairs{Union{}, Union{}, Tuple{}, NamedTuple{(), Tuple{}}}, typeof(Base.sort), OrderedCollections.OrderedDict{String, String}})
end
