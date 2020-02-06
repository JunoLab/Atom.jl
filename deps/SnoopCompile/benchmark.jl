using SnoopCompile

@info "Benchmark inference time during package loading"
@snoopi_bench "Atom" using Atom

@info "Benchmark inference time during running package testsuite"
@snoopi_bench "Atom"
