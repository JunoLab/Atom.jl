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

    @testset "module completion" begin
        ## basic
        line = "@"
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

        ## advanced
        handle("match(code", path = joinpath(pathof(Atom), "src", "completions.jl"), mod = "Atom")
        @test filter(readmsg()[3]["completions"]) do comp
            comp["text"] == "codeblock_regex" &&
            comp["rightLabel"] == "Atom"
        end |> !isempty
    end

    # method completion
    @testset "method completion" begin
        line = "push!("

        ## basic
        handle(line)
        comps = readmsg()[3]["completions"]
        # test no error occurs in completion processing
        @test length(comps) == length(completions(line, lastindex(line))[1])
        # test detecting all the `push!` methods available in Atom module
        @test filter(comps) do comp
            comp["type"] == "method"
        end |> length == length(methods(push!))

        ## features
        # - shows module where the method defined in right label
        # - shows the infered return type in left label
        @test filter(comps) do comp
            comp["type"] == "method" &&
            comp["rightLabel"] == "Atom" &&
            comp["leftLabel"] == "String"
        end |> isempty

        @eval Atom begin
            import Base: push!
            push!(::Undefined) = "i'm an undefined push!"
        end

        handle(line)
        @test filter(readmsg()[3]["completions"]) do comp
            comp["type"] == "method" &&
            comp["rightLabel"] == "Atom" &&
            comp["leftLabel"] == "String" &&
            comp["text"] == "push!(::Atom.Undefined)"
        end |> !isempty

        ## advanced
        line *= "Undefined(), "
        handle(line) # in Main: Undefined is not defined -- should show all push! methods
        @test length(readmsg()[3]["completions"]) == length(methods(push!))

        handle(line, mod = "Atom") # in Atom: show push!(::Undefined) **first**
        let comp = readmsg()[3]["completions"][1]
            @test comp["type"] == "method"
            @test comp["rightLabel"] == "Atom"
            @test comp["leftLabel"] == "String"
            @test comp["text"] == "push!(::Atom.Undefined)"
        end
    end

    @eval Main dict = Dict(:a => 1, :b => 2)

    @testset "dictionary completion" begin
        handle("dict[")
        @test map(readmsg()[3]["completions"]) do comp
            comp["type"] == "key" &&
            comp["text"] ∈ sprint.(show, keys(dict))
        end |> all
    end

    @testset "property completion" begin
        handle("dict.")
        @test map(readmsg()[3]["completions"]) do comp
            comp["type"] == "property" &&
            comp["text"] ∈ string.(propertynames(dict))
        end |> all
    end

    @testset "field completion" begin
        handle("split(\"im going to be split !\", \"to\")[1].")
        @test map(readmsg()[3]["completions"]) do comp
            comp["type"] == "property" &&
            comp["text"] ∈ string.(fieldnames(SubString))
        end |> all
    end

    @testset "keyword completion" begin
        handle("begin")
        @test filter(readmsg()[3]["completions"]) do comp
            comp["type"] == "keyword" &&
            !isempty(comp["description"])
        end |> !isempty
    end

    @testset "path completion" begin
        line = "\""
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

@testset "local completions" begin
    # local completions ordered by proximity
    let str = """
        function foo(x)
            aaa = 3
            a

            foo = x
            a
            abc = 3
            a
        end
        """
        @test Atom.basecompletionadapter("a", Main, true, 3, 6, str)[1][1][:text] == "aaa"
        @test Atom.basecompletionadapter("a", Main, true, 6, 6, str)[1][1][:text] == "aaa"
        @test Atom.basecompletionadapter("a", Main, true, 8, 6, str)[1][1][:text] == "abc"
    end
end
