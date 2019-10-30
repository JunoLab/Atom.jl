@testset "outline" begin
    function outline(str)
        parsed = CSTParser.parse(str, true)
        items = Atom.toplevelitems(parsed, str)
        Atom.outline(items)
    end

    let str = """
        module Foo
        foo(x) = x
        function bar(x::Int)
            2x
        end
        const sss = 3
        end
        """
        let os = Set(outline(str))
            for o ∈ [
                    Dict(
                        :type => "module",
                        :name => "Foo",
                        :icon => "icon-package",
                        :lines => [1, 7],
                    )
                    Dict(
                        :type => "function",
                        :name => "foo(x)",
                        :icon => "λ",
                        :lines => [2, 2],
                    )
                    Dict(
                        :type => "function",
                        :name => "bar(x::Int)",
                        :icon => "λ",
                        :lines => [3, 5],
                    )
                    Dict(
                        :type => "constant",
                        :name => "sss",
                        :icon => "c",
                        :lines => [6, 6],
                    )
                ]
                @test o ∈ os
            end
        end
    end

    # kwargs shouldn't show up in outline, same as anon function args
    let str = """
        function bar(foo = 3)
            2x
        end
        const foo = (a,b) -> a+b
        const bar = (asd=3, bsd=4)
        """
        let os = Set(outline(str))
            for o ∈ [
                    Dict(
                        :type => "function",
                        :name => "bar(foo = 3)",
                        :icon => "λ",
                        :lines => [1, 3],
                    )
                    Dict(
                        :type => "constant",
                        :name => "foo",
                        :icon => "c",
                        :lines => [4, 4],
                    )
                    Dict(
                        :type => "constant",
                        :name => "bar",
                        :icon => "c",
                        :lines => [5, 5],
                    )
                ]
                @test o ∈ os
            end
        end
    end

    # destructure multiple return expression
    let str = """
        tuple = (one = 1, two = 2) # `(one = 1, two = 2)` shouldn't leak
        a, b = tuple # `a, b` should be correctly destructured
        const c1, c2 = tuple # static constantness checks
        """
        let os = Set(outline(str))
            for o ∈ [
                    Dict(
                        :type => "variable",
                        :name => "tuple",
                        :icon => "v",
                        :lines => [1, 1],
                    ),
                    Dict(
                        :type => "variable",
                        :name => "a, b",
                        :icon => "v",
                        :lines => [2, 2],
                    ),
                    Dict(
                        :type => "constant",
                        :name => "c1, c2",
                        :icon => "c",
                        :lines => [3, 3],
                    ),
                ]
                @test o ∈ os
            end
        end
    end

    # items inside quote blocks don't leak
    let str = """
        ex = :(func() = nothing)
        q = quote
            @macrocall something
            val = nothing
        end
        """
        let names = Set(map(d -> d[:name], outline(str)))
            @test length(names) === 2
            @test names == Set(("ex", "q"))
        end
    end

    # should stringify method signatures correctly
    let str = """
        withstrings(single = \"1\", triple = \"\"\"3\"\"\") = single * triple
        withchar(char = 'c') = char
        withkwarg(arg, defarg = 0; kwarg1 = 1, kwarg2 = 2) = defarg * kwarg
        """
        topbinds = map(b -> b[:name], outline(str))
        @test topbinds[1] == "withstrings(single = \"1\", triple = \"\"\"3\"\"\")"
        @test topbinds[2] == "withchar(char = 'c')"
        @test topbinds[3] == "withkwarg(arg, defarg = 0; kwarg1 = 1, kwarg2 = 2)"
    end

    # docstrings souldn't leak into toplevel items
    let str = """
        @doc \"\"\"
            withdocmacro()

        docstring
        \"\"\"
        withdocmacro() = nothing

        \"\"\"
            withdocstring

        docstring
        \"\"\"
        withdocstring = nothing
        """
        items = outline(str)
        @test length(items) === 2
        @test filter(items) do item
            item[:name] == "withdocmacro()" &&
            item[:lines] == [6, 6]
        end |> !isempty
        @test filter(items) do item
            item[:name] == "withdocstring" &&
            item[:lines] == [13, 13]
        end |> !isempty
    end

    # toplevel macro calls
    let str = """
        @generate f(x) = x
        @render i::Inline x::Complex begin
          re, ima = reim(x)
          if signbit(ima)
            span(c(render(i, re), " - ", render(i, -ima), "im"))
          else
            span(c(render(i, re), " + ", render(i, ima), "im"))
          end
        end
        @nospecialize
        """
        calls = outline(str)

        @test !isempty(calls)
        let call = calls[1] # single line
            @test call[:name] == "@generate f(x) = x"
            @test call[:type] == "snippet"
            @test call[:icon] == "icon-mention"
        end
        let call = calls[2] # multiple lines
            @test call[:name] == "@render i::Inline x::Complex begin" # just shows the first line
            @test call[:type] == "snippet"
            @test call[:icon] == "icon-mention"
        end
        let call = calls[3] # no argument
            @test call[:name] == "@nospecialize"
            @test call[:type] == "snippet"
            @test call[:icon] == "icon-mention"
        end
    end

    # toplevel include
    let str = """
        include(\"test.jl\")
        include(\"moretest.jl\")
        """
        items = outline(str)
        @test length(items) == 2
        let call = items[1]
            @test call[:type] == "module"
            @test call[:name] == "include(\"test.jl\")"
            @test call[:icon] == "icon-file-code"
        end
    end
end
