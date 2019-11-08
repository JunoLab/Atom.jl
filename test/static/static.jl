@testset "static analysis" begin
    @testset "toplevel items" begin
        include("toplevel.jl")
    end

    @testset "local bindings" begin
        include("local.jl")
    end
end
