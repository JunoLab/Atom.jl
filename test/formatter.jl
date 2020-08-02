@testset "formatter" begin
    @static if VERSION < v"1.4"
        @test_broken !isempty(Atom.FORMAT_TEXT_KWARGS)
    else
        @test !isempty(Atom.FORMAT_TEXT_KWARGS)
    end
end
