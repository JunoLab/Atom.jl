@testset "completions" begin
    using REPL.REPLCompletions: completions

    comps(line; mod = Main, force = false, lineNumber = 1, column = 1, text = "") =
        Atom.basecompletionadapter(line, mod, force, lineNumber, column, text)[1]

    @testset "module completion" begin
        ## basic
        let line = "@", cs = comps(line, mod = Atom)
            # test no error occurs in completion processing
            @test length(cs) == length(completions(line, lastindex(line), Atom)[1])
            # test detecting all the macros in Atom module
            @test filter(cs) do c
                c[:type] == "snippet" &&
                c[:icon] == "icon-mention" &&
                c[:rightLabel] == "Atom"
            end |> length == filter(names(Atom, all=true, imported=true)) do n
                startswith(string(n), '@')
            end |> length
        end

        ## advanced
        let cs = comps("match(code", mod = Atom)
            filter(cs) do c
                c[:text] == "codeblock_regex" &&
                c[:rightLabel] == "Atom"
            end |> !isempty
        end
    end

    # method completion
    @testset "method completion" begin
        line = "push!("

        ## basic
        let cs = comps(line)
            # test no error occurs in completion processing
            @test length(cs) == length(completions(line, lastindex(line))[1])
            # test detecting all the `push!` methods available
            @test filter(cs) do c
                c[:type] == "method"
            end |> length == length(methods(push!))
        end

        ## features
        # - dynamic method addition
        # - shows module where the method defined in right label
        # - shows the infered return type in left label
        let cs = comps(line)
            @test filter(cs) do c
                c[:type] == "method" &&
                c[:rightLabel] == "Atom" &&
                c[:leftLabel] == "String"
            end |> isempty
        end

        @eval Atom begin
            import Base: push!
            push!(::Undefined) = "i'm such a dynamic push!"
        end

        let cs = comps(line)
            @test filter(cs) do c
                c[:type] == "method" &&
                c[:rightLabel] == "Atom" &&
                c[:leftLabel] == "String" &&
                c[:text] == "push!(::Atom.Undefined)"
            end |> !isempty
        end

        ## advanced
        line *= "Undefined(), "
        let cs = comps(line) # in Main: Undefined is not defined -- should show all push! methods
            @test length(cs) == length(methods(push!))
        end

        let c = comps(line, mod = Atom)[1] # in Atom: show push!(::Undefined) **first**
            @test c[:type] == "method"
            @test c[:rightLabel] == "Atom"
            @test c[:leftLabel] == "String"
            @test c[:text] == "push!(::Atom.Undefined)"
        end
    end

    @eval Main dict = Dict(:a => 1, :b => 2)

    @testset "property completion" begin
        @test map(comps("dict.")) do c
            c[:type] == "property" &&
            c[:rightLabel] == "Main" &&
            c[:text] ∈ string.(propertynames(dict))
        end |> all
    end

    @testset "field completion" begin
        @test map(comps("split(\"\", \"\")[1].")) do c
            c[:type] == "property" &&
            c[:rightLabel] == "SubString{String}" &&
            c[:leftLabel] ∈ string.(fieldtypes(SubString{String})) &&
            c[:text] ∈ string.(fieldnames(SubString{String}))
        end |> all
    end

    @testset "dictionary completion" begin
        @test map(comps("dict[")) do c
            c[:type] == "property" &&
            c[:icon] == "icon-key" &&
            c[:rightLabel] == "Main" &&
            c[:leftLabel] == string(Int) &&
            c[:text] ∈ sprint.(show, keys(dict))
        end |> all
    end

    @testset "keyword completion" begin
        @test filter(comps("begin")) do c
            c[:type] == "keyword" &&
            c[:rightLabel] |> isempty &&
            c[:description] |> !isempty
        end |> !isempty
    end

    @testset "path completion" begin
        let line = "\"", cs = comps(line)
            @test length(cs) ==
                  length(completions(line, lastindex(line))[1]) ==
                  length(readdir(@__DIR__))
            @test filter(cs) do c
                c[:type] == "path" &&
                c[:icon] == "icon-file" &&
                c[:rightLabel] |> isempty
            end |> !isempty
        end
    end

    # completion suppressing
    @testset "suppressing: $(troublemaker)" for troublemaker ∈ [" ", "(", "[", "\$"]
        @test length(comps(troublemaker, force = false)) == 0 # surpressed
        @test length(comps(troublemaker, force = true)) > Atom.MAX_COMPLETIONS # invoked
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
