@testset "toggle docs" begin
    # basic
    let doc = Atom.docs("push!")
        @test !doc[:error]
    end

    # context module
    let doc = Atom.docs("handle", "Atom")
        @test !doc[:error]
    end

    # keyword
    let doc = Atom.docs("begin", "Atom")
        @test !doc[:error]
    end
end
