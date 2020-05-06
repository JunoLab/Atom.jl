let

using Atom.FuzzyCompletions

comps(line; mod = "Main", context = "", row = 1, column = 1, force = false) =
    Atom.fuzzycompletionadapter(line, mod, context, row, column, force)
# emurate `getSuggestionDetailsOnSelect` API
add_details!(c) = Atom.completiondetail!(JSON.parse(json(c)))

@testset "module completion" begin
    ## basic
    let line = "@", cs = comps(line, mod = "Atom")
        # test detecting all the macros in Atom module
        @test filter(cs) do c
            c.type == "snippet" &&
            c.icon == "icon-mention" &&
            c.rightLabel == "Atom"
        end |> length == filter(names(Atom, all=true, imported=true)) do n
            startswith(string(n), '@')
        end |> length
    end

    ## advanced
    let cs = comps("match(code", mod = "Atom")
        @test filter(cs) do c
            c.text == "codeblock_regex" &&
            c.rightLabel == "Atom"
        end |> !isempty
    end

    ## don't error for `ModuleCompletion` of modules where `@doc` isn't defined
    let line = "Core.Compiler.type"
        @test (comps(line); true)
    end
end

# method completion
@testset "method completion" begin
    line = "push!("

    ## basic
    let cs = comps(line)
        # test no error occurs in completion processing
        @test length(cs) == length(FuzzyCompletions.completions(line, lastindex(line))[1])
        # test detecting all the `push!` methods available
        @test filter(cs) do c
            c.type == "method"
        end |> length == length(methods(push!))
    end

    ## advances
    # HACK: this allows testing this in a same julia runtime
    let mod = Main.eval(:(module $(gensym("tempmod")) end))
        # initial state check
        let cs = comps(line)
            filter!(c -> c.text == "push!(::$(mod).Singleton)", cs)
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
            filter!(c -> c.text == "push!(::$(mod).Singleton)", cs)
            # dynamic method addition
            @test length(cs) === 1
            c = cs[1]
            @test c.type == "method"
            # shows module where the method defined in right label
            @test c.rightLabel == string(mod)

            c = add_details!(c)
            @test c["leftLabel"] == "String" # shows the infered return type in left label from method signature
        end

        # shows the infered return type in left label from input types
        @eval mod f(a) = a
        let cs = comps("f("; mod = string(mod))
            filter!(c -> c.text == "f(a)", cs)
            @test length(cs) === 1
            c = cs[1]
            @test c.text == "f(a)"
            @test c.type == "method"
            @test c.rightLabel == string(mod)

            c = add_details!(c)
            @test c["leftLabel"] == "" # don't show a return type when it can't be inferred
        end
        let cs = comps("f(1, "; mod = string(mod))
            filter!(c -> c.text == "f(a)", cs)
            @test length(cs) === 1
            c = cs[1]
            @test c.text == "f(a)"
            @test c.type == "method"
            @test c.rightLabel == string(mod)

            # infer return type with input types
            c = add_details!(c)
            @static if VERSION ≥ v"1.1"
                @test c["leftLabel"] == "$(Int)"
            else
                @test_broken c["leftLabel"] == "$(Int)"
            end
        end

        # don't segfault on generate function
        @eval mod begin
            @generated g(x) = :(return $x)
        end
        @test_nowarn let cs = comps("g("; mod = string(mod))
            @test !isempty(cs)
            @test cs[1].type == "method"
            @test cs[1].text == "g(x)"
        end
    end
end

# HACK: this allows testing these while preventing Main from getting polluted
let m = Main.eval(:(module $(gensym("tempmod")) end))
    ms = string(m)
    @eval m dict = Dict(:a => 1, :b => 2)

    @testset "property completion" begin
        props = string.(propertynames(m.dict))
        foreach(comps("dict.", mod = ms)) do c
            @test c.text in props
            @test c.type == "property"
            @test c.rightLabel == ms
        end
    end

    @testset "field completion" begin
        line = "split(\"\", \"\")[1]."
        fields = string.(fieldnames(SubString{String}))
        foreach(comps(line, mod = ms)) do c
            @test c.text in fields
            @test c.type == "property"
            @test c.rightLabel == "SubString{String}" # the type of object who has those fields
            @test c.leftLabel == string(fieldtype(SubString{String}, Symbol(c.text)))
        end
    end

    @testset "dictionary completion" begin
        ks = repr.(keys(m.dict))
        foreach(comps("dict[", mod = ms)) do c
            @test c.text in ks
            @test c.type == "property"
            @test c.icon == "icon-key"
            @test c.rightLabel == ms
            @test c.leftLabel == string(Int)
        end
    end
end

@testset "keyword completion" begin
    for line in ["begin", "beg", "bgin", "bg"]
        cs = comps(line)
        i = findfirst(c -> c.text == "begin", cs)
        @test i !== nothing
        c = cs[i]
        @test c.type == "keyword"
        @test isempty(c.rightLabel)
        c = add_details!(c)
        @test !isempty(c["description"])
    end
end

@testset "path completion" begin
    line = "\""
    cs = comps(line)
    # XXX: currently `withpath` isn't functional
    # once our path completions are able to return paths relative to each editor's one,
    # we can test against `readdir(@__DIR__)`
    @test length(cs) ==
          length(REPLCompletions.completions(line, lastindex(line))[1]) ==
          length(readdir(pwd()))
    foreach(cs) do c
        @test c.type == "path"
        @test c.icon == "icon-file"
        @test c.rightLabel |> isempty
    end
end

# completion suppressing
troublemakers = [" ", "(", "[", "\$", "=", "&"]
@testset "suppressing: $t" for t in troublemakers
    @test length(comps(t, force = false)) === 0 # surpressed
    @test length(comps(t, force = true)) === Atom.MAX_COMPLETIONS # invoked
end

# don't error on fallback case
@test (Atom.fuzzycompletionadapter(""); true)

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
        comps′(prefix, row, column, force = false) =
            comps(prefix; context = context, row = row, column = column, force = force)

        # local completions ordered by proximity
        prefix = "a"
        let c = comps′(prefix, 3, 6)[1]
            @test c.text == "aaa"
            @test c.rightLabel == "foo"
            @test c.type == type
            @test c.icon == icon
            @test c.description == "aaa = 3"
        end
        let c = comps′(prefix, 6, 6)[1]
            @test c.text == "aaa"
            @test c.rightLabel == "foo"
            @test c.type == type
            @test c.icon == icon
            @test c.description == "aaa = 3"
        end
        let c = comps′(prefix, 8, 6)[1]
            @test c.text == "abc"
            @test c.rightLabel == "foo"
            @test c.type == type
            @test c.icon == icon
            @test c.description == "abc = 3"
        end

        # show a bound line as is if binding verbatim is not so useful
        let c = comps′("x", 5, 13)[1]
            @test c.text == "x"
            @test c.rightLabel == "foo"
            @test c.type == type
            @test c.icon == icon
            @test c.description == "function foo(x)"
        end

        # show all the local bindings in order when forcibly invoked
        let cs = comps′("", 6, 6, true)
            inds = findall(c -> c.type == type && c.icon == icon, cs)
            @test inds == [1, 2, 3, 4]
            @test map(c -> c.text, cs[inds]) == ["foo", "aaa", "x", "abc"]
        end

        # suppress local completions when in "troublemaker" cases
        for t in troublemakers
            cs = comps′(t, 1, 1)
            @test isempty(cs)
        end
    end

    # don't error on fallback case
    @test (Atom.localcompletions("", 1, 1, ""); true)
end

end
