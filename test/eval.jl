# toggle docs / goto symbols
@testset "docs and methods" begin
    cb = 0  # callback count
    handle(type, word, mod = "Main") =
        Atom.handlemsg(Dict("type"     => type,
                            "callback" => (cb += 1)),
                       Dict("word"     => word,
                            "mod"      => mod))

    ## toggle docs

    # basic
    handle("docs", "push!")
    @test !readmsg()[3]["error"]

    # context module
    handle("docs", "handlemsg", "Atom")
    @test !readmsg()[3]["error"]

    # keyword
    handle("docs", "begin", "Atom")
    @test !readmsg()[3]["error"]

    ## goto symbols

    # basic - `Atom.handlemsg` is not defined with default args
    handle("methods", "Atom.handlemsg")
    @test length(readmsg()[3]["items"]) === length(methods(Atom.handlemsg))

    # module awareness
    handle("methods", "handlemsg", "Atom")
    @test length(readmsg()[3]["items"]) === length(methods(Atom.handlemsg))

    # aggregate methods with default params
    @eval Main function funcwithdefaultargs(args, defarg = "default") end
    handle("methods", "funcwithdefaultargs") # should be handled as an unique method
    @test length(readmsg()[3]["items"]) === 1

    @eval Main function funcwithdefaultargs(args::Vector, defarg = "default") end
    handle("methods", "funcwithdefaultargs") # should be handled as a different method
    @test length(readmsg()[3]["items"]) === 2
end
