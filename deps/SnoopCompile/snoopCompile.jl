using SnoopCompile

cd(@__DIR__)

### Log the compiles
# This only needs to be run once (to generate Atom.log)

# SnoopCompile.@snoopc LogPath begin
SnoopCompile.@snoopc "$(pwd())/Atom.log" begin
    using Atom, Pkg
    include(joinpath(dirname(dirname(pathof(Atom))), "test", "runtests.jl"))
end

### Parse the compiles and generate precompilation scripts
# This can be run repeatedly to tweak the scripts


data = SnoopCompile.read("$(pwd())/Atom.log")

pc = SnoopCompile.parcel(reverse!(data[2]))
SnoopCompile.write("$(pwd())/precompile", pc)
