@testset "Display" begin
    let
        foo() = foo()
        @test Atom.render(Atom.Inline(), Atom.@errs foo()) != nothing
    end

    # issue: https://github.com/JunoLab/Juno.jl/issues/376
    @test Atom.render(Atom.Inline(), :abc)[:contents] == [":abc"]
    @test Atom.render(Atom.Inline(), Symbol("A B"))[:contents] == ["Symbol(\"A B\")"]

    # function display
    # basic
    let d = Atom.render(Atom.Inline(), sin)
        @test d[:type] === :lazy
        @test d[:head][:contents] == ["sin"]
    end

    # in a specific module
    m = eval(:(module $(gensym(:atomjltestmodule)) end))

    let d = Atom.render(Atom.Inline(), Core.eval(m, :(mock_func() = nothing)))
        @test d[:type] === :lazy
        @test d[:head][:contents] == ["$(m).mock_func"]
    end

    # macro
    let d = Atom.render(Atom.Inline(), Core.eval(m, :(macro mock_macro() end)))
        @test d[:type] === :lazy
        @test d[:head][:contents] == ["$(m).@mock_macro"]
    end

    @test length(Atom.trim(rand(50), 20)) == 20

    @test Atom.isanon(sin) == false
    @test Atom.isanon(x -> x) == true # the `== true` might fix a weird travis error

    @test Atom.pluralize([1,2,3], "entry", "entries") == "3 entries"
    @test Atom.pluralize([1], "entry", "entries") == "1 entry"
end
