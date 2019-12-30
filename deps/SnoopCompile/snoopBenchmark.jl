using SnoopCompile

println("load infer benchmark:")
@snoopiBenchBot "Atom" using Atom

println("Examples/Tests infer benchmark")
@snoopiBenchBot "Atom"
