# TODO: test display error handling stuff, here are only basic execution tests

evaltestpath = joinpath′(@__DIR__, "fixtures", "EvalTest.jl")

@testset "eval" begin

@testset "evalall" begin
    code = read(evaltestpath, String)
    Atom.evalall(code, "Main", evaltestpath)
    @test isdefined(Main, :EvalTest)
    @test isdefined(EvalTest, :foo)
end

@testset "eval" begin
    let ret = Atom.eval("bar = :bar", 4, evaltestpath, "Main.EvalTest")
        @test ret[:text] == ":bar"
    end
    @test isdefined(EvalTest, :bar)
    let ret = Atom.eval("bar = :bar2", 4, evaltestpath, "Main.EvalTest")
        @test ret[:text] == ":bar2"
    end
    @test EvalTest.bar == :bar2
end

@testset "evalshow" begin
    # NOTE: semicolons are necessary so that they work without repl display during a test
    Atom.evalshow("baz = :baz;", 5, evaltestpath, "Main.EvalTest")
    @test isdefined(EvalTest, :baz)
    Atom.evalshow("baz = :baz2;", 5, evaltestpath, "Main.EvalTest")
    @test EvalTest.baz == :baz2
end

end

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
