# toggle docs / goto symbols
@testset "docs and methods" begin
    cb = 0  # callback count
    handle(type, word, mod = "Main") =
        Atom.handlemsg(Dict("type"     => type,
                            "callback" => (cb += 1)),
                       Dict("word"     => word,
                            "mod"      => mod))

    # toggle docs
    # basic
    handle("docs", "push!")
    @test !readmsg()[3]["error"]
    # context module
    handle("docs", "handlemsg", "Atom")
    @test !readmsg()[3]["error"]
    # keyword
    handle("docs", "begin", "Atom")
    @test !readmsg()[3]["error"]

    # goto symbols
    # basic
    handle("methods", "push!")
    @test length(readmsg()[3]["items"]) == length(methods(push!))
    # context module
    handle("methods", "handlemsg", "Atom")
    @test length(readmsg()[3]["items"]) == length(methods(Atom.handlemsg)) # == 1
end
