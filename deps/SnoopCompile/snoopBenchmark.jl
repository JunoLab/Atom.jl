# dev your package

# comment the precompile part of your package ("include() and _precompile_()")
# run this benchmark
# restart Julia

# uncomment the precompile part of your package ("include() and _precompile_()")
# run this benchmark
# restart Julia

# now compare the result
################################################################
using SnoopCompile

println("Package load time:")
loadSnoop = @snoopi using Atom

timesum(loadSnoop)

################################################################
println("Running Examples/Tests:")
runSnoop = @snoopi begin

using Atom

include(joinpath(dirname(dirname(pathof(Atom))), "test", "runtests.jl"))

end

timesum(runSnoop)
