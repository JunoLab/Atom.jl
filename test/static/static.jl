@testset "static analysis" begin
    @testset "bindings" begin
        include("bindings.jl")
    end

    @testset "toplevel items" begin
        include("toplevel.jl")
    end

    @testset "local bindings" begin
        include("local.jl")
    end
end
