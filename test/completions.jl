@testset "completions" begin
    using REPL.REPLCompletions: completions

    comps(line; mod = "Main", context = "", row = 1, column = 1, force = false) =
        Atom.basecompletionadapter(line, mod, context, row, column, force)
    # emurate `getSuggestionDetailsOnSelect` API
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
            # initial state check
            let cs = comps(line)
                filter!(c -> c[:text] == "push!(::$(mod).Singleton)", cs)
                @test isempty(cs)
            end

            # advanced features
            # - dynamic method addition
            # - shows module where the method defined in right label
            # - shows the infered return type in left label from method signature
            @eval mod begin
                struct Singleton end
                import Base: push!
                push!(::Singleton) = ""
            end
            let cs = comps(line)
                filter!(c -> c[:text] == "push!(::$(mod).Singleton)", cs)
                # dynamic method addition
                @test length(cs) === 1
                c = cs[1]
                @test c[:type] == "method"
                # shows module where the method defined in right label
                @test c[:rightLabel] == string(mod)

                add_details!(c)
                @test c[:leftLabel] == "String" # shows the infered return type in left label from method signature
            end

            # shows the infered return type in left label from input types
            @eval mod f(a) = a
            let cs = comps("f("; mod = string(mod))
                filter!(c -> c[:text] == "f(a)", cs)
                @test length(cs) === 1
                c = cs[1]
                @test c[:text] == "f(a)"
                @test c[:type] == "method"
                @test c[:rightLabel] == string(mod)

                add_details!(c)
                @test c[:leftLabel] == "" # don't show a return type when it can't be inferred
            end
            let cs = comps("f(1, "; mod = string(mod))
                filter!(c -> c[:text] == "f(a)", cs)
                @test length(cs) === 1
                c = cs[1]
                @test c[:text] == "f(a)"
                @test c[:type] == "method"
                @test c[:rightLabel] == string(mod)

                add_details!(c)
                # infer return type with input types
                @static if VERSION ≥ v"1.1"
                    @test c[:leftLabel] == "$(Int)"
                else
                    @test_broken c[:leftLabel] == "$(Int)"
                end
            end

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
        w = pwd()
        cd(@__DIR__)

        line = "\""
        cs = comps(line)
        @test length(cs) ==
              length(completions(line, lastindex(line))[1]) ==
              length(readdir(@__DIR__))
        @test filter(cs) do c
            c[:type] == "path" &&
            c[:icon] == "icon-file" &&
            c[:rightLabel] |> isempty
        end |> !isempty

        cd(w)
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

    let context = """
        function foo(x)
            aaa = 3
            a # C3R6

            foo = x # C5R13
            a # C6R6
            abc = 3
            a # C8R6
        end
        """

        # local completions ordered by proximity
        prefix = "a"
        let c = Atom.basecompletionadapter(prefix, "Main", context, 3, 6)[1]
            @test c[:text] == "aaa"
            @test c[:rightLabel] == "foo"
            @test c[:type] == type
            @test c[:icon] == icon
            @test c[:description] == "aaa = 3"
        end
        let c = Atom.basecompletionadapter(prefix, "Main", context, 6, 6)[1]
            @test c[:text] == "aaa"
            @test c[:rightLabel] == "foo"
            @test c[:type] == type
            @test c[:icon] == icon
            @test c[:description] == "aaa = 3"
        end
        let c = Atom.basecompletionadapter(prefix, "Main", context, 8, 6)[1]
            @test c[:text] == "abc"
            @test c[:rightLabel] == "foo"
            @test c[:type] == type
            @test c[:icon] == icon
            @test c[:description] == "abc = 3"
        end

        # show a bound line as is if binding verbatim is not so useful
        let c = Atom.basecompletionadapter("x", "Main", context, 5, 13)[1]
            @test c[:text] == "x"
            @test c[:rightLabel] == "foo"
            @test c[:type] == type
            @test c[:icon] == icon
            @test c[:description] == "function foo(x)"
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
