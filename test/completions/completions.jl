@testset "completions" begin
    @testset "REPL-backend completion mode" begin
        include("replcompletions.jl")
    end
    @testset "fuzzy completion mode" begin
        include("fuzzycompletions.jl")
    end
end
