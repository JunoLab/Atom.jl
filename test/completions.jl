@testset "completions" begin
    import REPL.REPLCompletions: completions

    cb = 0  # callback count
    handle(line; path = @__FILE__, mod = "Main", force = false) =
        Atom.handlemsg(Dict("type"     => "completions",
                            "callback" => (cb += 1)),
                       Dict("path"  => path,
                            "mod"   => mod,
                            "line"  => line,
                            "force" => force))

    # module completion
    let line = "@"
        handle(line, path = joinpath(pathof(Atom), "src", "completions.jl"), mod = "Atom")
        comps = readmsg()[3]["completions"]
        # test no error occurs in completion processing
        @test length(comps) == length(completions(line, lastindex(line), Atom)[1])
        # test detecting all the macros in Atom module
        @test filter(comps) do comp
            comp["icon"] == "icon-mention" &&
            comp["rightLabel"] == "Atom"
        end |> length == filter(names(Atom, all=true, imported=true)) do name
            startswith(string(name), '@')
        end |> length
    end

    # method completion
    let line = "push!("
        # basic method completion
        handle(line)
        comps = readmsg()[3]["completions"]
        # test no error occurs in completion processing
        @test length(comps) == length(completions(line, lastindex(line))[1])
        # test detecting all the `push!` methods available in Atom module
        @test filter(comps) do comp
            comp["type"] == "method"
        end |> length == length(methods(push!))

        # method completion should show
        # - module where the method defined in right label
        # - the infered return type in left label
        @test filter(comps) do comp
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
    end

    @eval Main dict = Dict(:a => 1, :b => 2)

    # dictionary completion
    let line = "dict["
        handle(line)
        @test map(readmsg()[3]["completions"]) do comp
            comp["type"] == "key" &&
            comp["text"] ∈ sprint.(show, keys(dict))
        end |> all
    end

    # property completion
    let line = "dict."
        handle(line)
        @test map(readmsg()[3]["completions"]) do comp
            comp["type"] == "property" &&
            comp["text"] ∈ string.(propertynames(dict))
        end |> all
    end

    # field completion
    let line = "split(\"im going to be split !\", \"to\")[1]."
        handle(line)
        @test map(readmsg()[3]["completions"]) do comp
            comp["type"] == "property" &&
            comp["text"] ∈ string.(fieldnames(SubString))
        end |> all
    end

    # keyword completion
    let line = "begin"
        handle(line)
        @test filter(readmsg()[3]["completions"]) do comp
            comp["type"] == "keyword" &&
            !isempty(comp["description"])
        end |> !isempty
    end

    # path completion
    let line = "\""
        handle(line)
        @test length(readmsg()[3]["completions"]) ==
              length(completions(line, lastindex(line))[1]) ==
              length(readdir(@__DIR__))
    end

    # completion suppressing
    @testset "suppressing: $(troublemaker)" for troublemaker ∈ [" ", "(", "[", "\$"]
        handle(troublemaker)
        @test length(readmsg()[3]["completions"]) == 0 # surpressed
        handle(troublemaker, force = true)
        @test length(readmsg()[3]["completions"]) > Atom.MAX_COMPLETIONS # invoked
    end
end
