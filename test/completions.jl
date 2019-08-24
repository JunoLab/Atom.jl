@testset "completions" begin
    import REPL.REPLCompletions: completions

    cb = 0  # callback count
    function handle(line; path = @__FILE__, mod = string(@__MODULE__), force = false)
        Atom.handlemsg(Dict("type"     => "completions",
                            "callback" => (cb += 1)),
                       Dict("path"  => path,
                            "mod"   => mod,
                            "line"  => line,
                            "force" => force))
    end


    # module completion
    line = "@"
    handle(line, path = joinpath(pathof(Atom), "src", "completions.jl"), mod = "Atom")
    @test length(readmsg()[3]["completions"]) == length(completions(line, lastindex(line), Atom)[1])

    # path completion
    oldpath = pwd()
    cd(@__DIR__)
    line = "\""
    handle(line)
    @test length(readmsg()[3]["completions"]) == length(completions(line, lastindex(line), @__MODULE__)[1])
    cd(oldpath)

    # method completion
    line = "push!("
    handle(line)
    @test length(readmsg()[3]["completions"]) == length(completions(line, lastindex(line), @__MODULE__)[1])

    # completion suppressing
    @testset "suppressing: $(troublemaker)" for troublemaker ∈ [" ", "(", "[", "\$"]
        handle(troublemaker)
        @test length(readmsg()[3]["completions"]) == 0 # surpressed
        handle(troublemaker, force = true)
        @test length(readmsg()[3]["completions"]) > 500 # invoked
    end
end
