using SnoopCompile

println("load infer benchmark:")
@snoopiBenchBot "Atom" begin
    using Atom
end


println("Examples/Tests infer benchmark")
@snoopiBenchBot "Atom"
