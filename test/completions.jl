@testset "completions" begin
    using REPL.REPLCompletions: completions

    comps(line; mod = "Main", context = "", row = 1, column = 1, force = false) =
        Atom.basecompletionadapter(line, mod, context, row, column, force)
    # emurate `getSuggestionDetailsOnSelect`
    add_details!(c) = Atom.completiondetail!(c)

    @testset "module completion" begin
        ## basic
        let line = "@", cs = comps(line, mod = "Atom")
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
        let cs = comps("match(code", mod = "Atom")
            filter(cs) do c
                c[:text] == "codeblock_regex" &&
                c[:rightLabel] == "Atom"
            end |> !isempty
        end

        ## don't error for `ModuleCompletion` of modules where `@doc` isn't defined
        let line = "Core.Compiler.type"
            @test length(comps(line)) == length(completions(line, lastindex(line))[1])
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

        ## advances
        # HACK: this allows testing this in a same julia runtime
        let mod = Main.eval(:(module $(gensym("tempmod")) end))
            # advanced features
            # - dynamic method addition
            # - shows module where the method defined in right label
            # - shows the infered return type in left label
            @test filter(comps(line)) do c
                add_details!(c)
                c[:type] == "method" &&
                c[:rightLabel] == string(mod) &&
                c[:leftLabel] == "String" &&
                c[:text] == "push!(::$(mod).Singleton)"
            end |> isempty
            @eval mod begin
                struct Singleton end
                import Base: push!
                push!(::Singleton) = ""
            end
            @test filter(comps(line)) do c
                add_details!(c)
                c[:type] == "method" &&
                c[:rightLabel] == string(mod) &&
                c[:leftLabel] == "String" &&
                c[:text] == "push!(::$(mod).Singleton)"
            end |> !isempty

            # don't segfault on generate function
            @eval mod begin
                @generated g(x) = :(return $x)
            end
            @test_nowarn let cs = comps("g("; mod = string(mod))
                @test !isempty(cs)
                @test cs[1][:type] == "method"
                @test cs[1][:text] == "g(x)"
            end
        end
    end

    @eval Main dict = Dict(:a => 1, :b => 2)

    @testset "property completion" begin
        @test map(comps("dict.")) do c
            c[:type] == "property" &&
            c[:rightLabel] == "Main" &&
            c[:text] in string.(propertynames(dict))
        end |> all
    end

    @testset "field completion" begin
        @test map(comps("split(\"\", \"\")[1].")) do c
            c[:type] == "property" &&
            c[:rightLabel] == "SubString{String}" &&
            c[:leftLabel] in string.(ntuple(i -> fieldtype(SubString{String}, i), fieldcount(SubString{String}))) &&
            c[:text] in string.(fieldnames(SubString{String}))
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
            add_details!(c)
            c[:type] == "keyword" &&
            isempty(c[:rightLabel]) &&
            !isempty(c[:description])
        end |> !isempty
    end

    @testset "path completion" begin
        let line = "\"", cs = comps(line)
            @test_skip length(cs) ==
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
    troublemakers = [" ", "(", "[", "\$"]
    @testset "suppressing: $t" for t in troublemakers
        @test length(comps(t, force = false)) === 0 # surpressed
        @test length(comps(t, force = true)) === Atom.MAX_COMPLETIONS # invoked
    end

    # don't error on fallback case
    @test_nowarn @test Atom.basecompletionadapter("") == []
end

@testset "local completions" begin
    type = "attribute"
    icon = "icon-chevron-right"

    # local completions ordered by proximity
    let context = """
        function foo(x)
            aaa = 3
            a

            foo = x
            a
            abc = 3
            a
        end
        """
        prefix = "a"
        let c = Atom.basecompletionadapter(prefix, "Main", context, 3, 6)[1]
            @test c[:text] == "aaa"
            @test c[:rightLabel] == "foo"
            @test c[:type] == type
            @test c[:icon] == icon
        end
        let c = Atom.basecompletionadapter(prefix, "Main", context, 6, 6)[1]
            @test c[:text] == "aaa"
            @test c[:rightLabel] == "foo"
            @test c[:type] == type
            @test c[:icon] == icon
        end
        let c = Atom.basecompletionadapter(prefix, "Main", context, 8, 6)[1]
            @test c[:text] == "abc"
            @test c[:rightLabel] == "foo"
            @test c[:type] == type
            @test c[:icon] == icon
        end

        # show all the local bindings in order when forcibly invoked
        let cs = Atom.basecompletionadapter("", "Main", context, 6, 6, true)
            inds = findall(c -> c[:type] == type && c[:icon] == icon, cs)
            @test inds == [1, 2, 3, 4]
            @test map(c -> c[:text], cs[inds]) == ["foo", "aaa", "x", "abc"]
        end
    end

    # don't error on fallback case
    @test_nowarn @test Atom.localcompletions("", 1, 1, "") == []
end
