@testset "toggle docs" begin
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
end
