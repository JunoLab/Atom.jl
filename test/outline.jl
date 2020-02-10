@testset "outline" begin
    using Atom: OutlineItem
    outline(text) = Atom.outline(Atom.toplevelitems(text))

    # basic
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
            for o in [
                    OutlineItem("Foo", "module", "icon-package", 1, 7)
                    OutlineItem("foo(x)", "function", "λ", 2, 2)
                    OutlineItem("bar(x::Int)", "function", "λ", 3, 5)
                    OutlineItem("sss", "constant", "c", 6, 6)
                ]
                @test o in os
            end
        end
    end

    # todict check
    let str = """
        module Foo
        foo(x) = x
        function bar(x::Int)
            2x
        end
        const sss = 3
        end
        """
        let os = Set(Atom.todict.(outline(str)))
            for o in [
                    Dict(
                        :type => "module",
                        :name => "Foo",
                        :icon => "icon-package",
                        :start => 1,
                        :stop => 7
                    )
                    Dict(
                        :type => "function",
                        :name => "foo(x)",
                        :icon => "λ",
                        :start => 2,
                        :stop => 2
                    )
                    Dict(
                        :type => "function",
                        :name => "bar(x::Int)",
                        :icon => "λ",
                        :start => 3,
                        :stop => 5
                    )
                    Dict(
                        :type => "constant",
                        :name => "sss",
                        :icon => "c",
                        :start => 6,
                        :stop => 6
                    )
                ]
                @test o in os
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
            for o in [
                    OutlineItem("bar(foo = 3)", "function", "λ", 1, 3)
                    OutlineItem("foo", "constant", "c", 4, 4)
                    OutlineItem("bar", "constant", "c", 5, 5)
                ]
                @test o in os
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
            for o in [
                    OutlineItem("tuple", "variable", "v", 1, 1)
                    OutlineItem("a", "variable", "v", 2, 2)
                    OutlineItem("b", "variable", "v", 2, 2)
                    OutlineItem("c1", "constant", "c", 3, 3)
                    OutlineItem("c2", "constant", "c", 3, 3)
                ]
                @test o in os
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
        let names = Set(map(d -> d.name, outline(str)))
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
        topbinds = map(b -> b.name, outline(str))
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
            item.name == "withdocmacro()" &&
            item.start === 6 &&
            item.stop === 6
        end |> !isempty
        @test filter(items) do item
            item.name == "withdocstring" &&
            item.start === 13 &&
            item.stop === 13
        end |> !isempty
    end

    # don't leak something in a call
    for t in ["f(call())", "f(call(), @macro)", "f(@macro)", "f(@macro, arg; kwarg = kwarg)"]
        @test length(outline(t)) === 0
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
            @test call.name == "@generate f(x) = x"
            @test call.type == "snippet"
            @test call.icon == "icon-mention"
        end
        let call = calls[2] # multiple lines
            @test call.name == "@render i::Inline x::Complex begin" # just shows the first line
            @test call.type == "snippet"
            @test call.icon == "icon-mention"
        end
        let call = calls[3] # no argument
            @test call.name == "@nospecialize"
            @test call.type == "snippet"
            @test call.icon == "icon-mention"
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
            @test call.type == "module"
            @test call.name == "include(\"test.jl\")"
            @test call.icon == "icon-file-code"
        end
    end

    # module usages
    let str = """
        module Mock
        using Atom
        using Atom: SYMBOLSCACHE
        import Base: iterate
        export mock
        mock = :mock
        end
        """
        items = outline(str)
        @test length(items) === 6
        let usage = items[2]
            @test usage.type == "mixin"
            @test usage.name == "using Atom"
            @test usage.icon == "icon-package"
            @test usage.start === 2
            @test usage.stop === 2
        end
        let usage = items[3]
            @test usage.type == "mixin"
            @test usage.name == "using Atom: SYMBOLSCACHE"
            @test usage.icon == "icon-package"
            @test usage.start === 3
            @test usage.stop === 3
        end
        let usage = items[4]
            @test usage.type == "mixin"
            @test usage.name == "import Base: iterate"
            @test usage.icon == "icon-package"
            @test usage.start === 4
            @test usage.stop === 4
        end
        let usage = items[5]
            @test usage.type == "mixin"
            @test usage.name == "export mock"
            @test usage.icon == "icon-package"
            @test usage.start === 5
            @test usage.stop === 5
        end
    end
end
