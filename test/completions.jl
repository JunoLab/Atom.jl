@testset "completions" begin
    import REPL.REPLCompletions: completions

    cb = 0  # callback count
    function handle(line; path = @__FILE__, mod = "Main", force = false)
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

    # method completion
    line = "push!("
    handle(line)
    @test length(readmsg()[3]["completions"]) == length(completions(line, lastindex(line))[1])

    # method completion should show
    # - module where the method defined in right label
    # - the infered return type in left label
    handle(line)
    @test filter(readmsg()[3]["completions"]) do comp
        comp["type"] == "method" &&
        comp["rightLabel"] == "Atom" &&
        comp["leftLabel"] == "String"
    end |> isempty

    @eval Atom begin
        import Base: push!
        push!(::Undefined) = "i'm a silly push!"
    end

    handle(line)
    @test filter(readmsg()[3]["completions"]) do comp
        comp["type"] == "method" &&
        comp["rightLabel"] == "Atom" &&
        comp["leftLabel"] == "String"
    end |> !isempty

    @eval Main dict = Dict(:a => 1, :b => 2)

    # package completion - on top level
    line = "using B"
    handle(line)
    @test filter(readmsg()[3]["completions"]) do comp
        comp["type"] ∈ ("package", "import", "module") &&
        comp["text"] == "Base"
    end |> !isempty

    # package completion - on module level
    line = "using C"
    handle(line, mod = "Atom")
    @test filter(readmsg()[3]["completions"]) do comp
        comp["type"] ∈ ("package", "import", "module") &&
        comp["text"] == "CodeTools"
    end |> !isempty

    # property completion
    line = "dict."
    handle(line)
    @test map(readmsg()[3]["completions"]) do comp
        comp["type"] == "property" &&
        comp["text"] ∈ string.(propertynames(dict))
    end |> all

    # dictionary completion
    line = "dict["
    handle(line)
    @test map(readmsg()[3]["completions"]) do comp
        comp["type"] == "key" &&
        comp["text"] ∈ sprint.(show, keys(dict))
    end |> all

    # keyword completion
    line = "begin"
    handle(line)
    @test filter(readmsg()[3]["completions"]) do comp
        comp["type"] == "keyword" &&
        !isempty(comp["description"])
    end |> !isempty

    # path completion
    line = "\""
    handle(line)
    @test length(readmsg()[3]["completions"]) == length(completions(line, lastindex(line))[1]) == length(readdir(@__DIR__))

    # completion suppressing
    @testset "suppressing: $(troublemaker)" for troublemaker ∈ [" ", "(", "[", "\$"]
        handle(troublemaker)
        @test length(readmsg()[3]["completions"]) == 0 # surpressed
        handle(troublemaker, force = true)
        @test length(readmsg()[3]["completions"]) > Atom.MAX_COMPLETIONS # invoked
    end
end
