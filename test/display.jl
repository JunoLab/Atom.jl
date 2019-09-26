@testset "Display" begin
    let
        foo() = foo()
        @test Atom.render(Atom.Inline(), Atom.@errs foo()) != nothing
    end

    @test length(Atom.trim(rand(50), 20)) == 20

    @test Atom.isanon(sin) == false
    @test Atom.isanon(x -> x)

    @test Atom.pluralize([1,2,3], "entry", "entries") == "3 entries"
    @test Atom.pluralize([1], "entry", "entries") == "1 entry"
end
