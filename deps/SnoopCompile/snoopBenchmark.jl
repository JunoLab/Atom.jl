using SnoopCompile

println("load infer benchmark:")
@snoopiBench "Atom" begin
    using Atom
end


println("Examples/Tests infer benchmark")
@snoopiBench "Atom"
