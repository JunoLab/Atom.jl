function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(Pkg.Display.print_diff), Pkg.Types.Context, Array{Pkg.Display.DiffEntry, 1}, Bool})
    isdefined(Pkg, Symbol("##read_manifest#45")) && precompile(Tuple{getfield(Pkg.Types, Symbol("##read_manifest#45")), Nothing, typeof(Pkg.Types.read_manifest), Base.DevNull})
    isdefined(Pkg, Symbol("##read_manifest#45")) && precompile(Tuple{getfield(Pkg.Types, Symbol("##read_manifest#45")), String, typeof(Pkg.Types.read_manifest), Base.IOStream})
    isdefined(Pkg, Symbol("##status#2")) && precompile(Tuple{getfield(Pkg.Display, Symbol("##status#2")), Bool, Pkg.Types.PackageMode, Bool, typeof(Pkg.Display.status), Pkg.Types.Context, Array{Pkg.Types.PackageSpec, 1}})
    isdefined(Pkg, Symbol("##read_manifest#45")) && precompile(Tuple{getfield(Pkg.Types, Symbol("##read_manifest#45")), Nothing, typeof(Pkg.Types.read_manifest), Base.GenericIOBuffer{Array{UInt8, 1}}})
    precompile(Tuple{typeof(Pkg.API.__installed), Pkg.Types.PackageMode})
    precompile(Tuple{typeof(Pkg.TOML.insertpair), Pkg.TOML.Parser{Base.GenericIOBuffer{Array{UInt8, 1}}}, Pkg.TOML.Table, String, Dates.DateTime, Int64})
end
