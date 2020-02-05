using SnoopCompile

println("load infer benchmark:")
@snoopi_bench "Atom" begin
    using Atom
end


println("Examples/Tests infer benchmark")
@snoopi_bench "Atom"
