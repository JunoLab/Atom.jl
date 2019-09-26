@testset "Display" begin
    let
        foo() = foo()
        @test Atom.render(Atom.Inline(), Atom.@errs foo()) != nothing
    end

    @test length(Atom.trim(rand(50), 20)) == 20

    @test Atom.isanon(sin) == false
    @test Atom.isanon(x -> x)
end
