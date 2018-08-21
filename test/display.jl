@testset "Display" begin
    let
        foo() = foo()
        @test Atom.render(Atom.Inline(), Atom.@errs foo()) != nothing
    end
end
