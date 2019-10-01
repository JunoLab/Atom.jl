@testset "local bindings" begin
    let str = """
        function local_bindings(expr, bindings = [], pos = 1)
            bind = CSTParser.bindingof(expr)
            scope = CSTParser.scopeof(expr)
            if bind !== nothing && scope === nothing
                push!(bindings, LocalBinding(bind.name, pos:pos+expr.span))
            end
            if scope !== nothing
                if expr.typ == CSTParser.Kw
                    return bindings
                end
                range = pos:pos+expr.span
                localbindings = []
                if expr.args !== nothing
                    for (i, arg) in expr.args
                        ### L15 -- FOR THE FIRST TEST ###
                        local_bindings(arg, text, localbindings, pos, line)
                        line += count(c -> c === '\n', text[nextind(text, pos - 1):prevind(text, pos + arg.fullspan)])
                        pos += arg.fullspan
                    end
                end
                if expr.typ == CSTParser.TupleH # deconstruct tuple expression
                    ### L21 - FOR THE SECOND TEST ###
                    for leftbind in localbindings
                        push!(bindings, leftbind)
                    end
                else
                    push!(bindings, LocalScope(bind === nothing ? "" : bind.name, range, line, localbindings, expr))
                end
                return bindings
            elseif expr.args !== nothing
                for arg in expr.args
                    local_bindings(arg, bindings, pos)
                    pos += arg.fullspan
                end
            end
            return bindings
        end
        """
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 15, 1))) == Set([
            ("i", ""),
            ("arg", ""),
            ("localbindings", "local_bindings"),
            ("range", "local_bindings"),
            ("scope", "local_bindings"),
            ("bind", "local_bindings"),
            ("pos", "local_bindings"),
            ("bindings", "local_bindings"),
            ("expr", "local_bindings"),
            ("local_bindings", "")
        ])
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 21, 100))) == Set([
            ("localbindings", "local_bindings"),
            ("pos", "local_bindings"),
            ("scope", "local_bindings"),
            ("bind", "local_bindings"),
            ("bindings", "local_bindings"),
            ("expr", "local_bindings"),
            ("local_bindings", ""),
            ("range", "local_bindings"),
            ("local_bindings", "")
        ])
    end

    let str = """
        const bar = 2
        function f(x=2) # `x` should show up in completions
            ff = function (x, xxx)
                z = 3
            end
            return y+x
        end
        kwfun(kw = 3) # `kw` should not show up in completions
        function foo(x)
            asd = 3
        end
        """
        outers = (("bar", ""), ("f", ""), ("foo", ""))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 1, 1))) ==
            Set(outers)
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 2, 100))) ==
            Set((("x", "f"), ("ff", "f"), outers...))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 4, 100))) ==
            Set((("ff", "f"), ("x", ""), ("xxx", ""), ("z", ""), outers...))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 10, 100))) ==
            Set((("x", "foo"), ("asd", "foo"), outers...))
    end

    # destructure multiple return expression
    let str = """
        function foo()
            tpl1, tpl2 = (1, 2)
            shown1, shown2 = (ntpl1 = 1, ntpl2 = 2)
        end
        """

        ls = Atom.locals(str, 1, 1)
        # basic
        for l in filter(l -> l[:line] == 2, ls)
            @test l[:name] ∈ ("tpl1", "tpl2")
            @test l[:root] == "foo"
            @test l[:bindstr] == "tpl1, tpl2 = (1, 2)"
        end
        # named tuple elements shouldn't show up in completions
        for l in filter(l -> l[:line] == 3, ls)
            @test l[:name] ∈ ("shown1", "shown2")
            @test l[:root] == "foo"
            @test l[:bindstr] == "shown1, shown2 = (ntpl1 = 1, ntpl2 = 2)"
        end
    end

    let str = """
        function foo(x)
            @macrocall begin
                xyz = 2
            end
            xxx = 3
            return 12
        end
        """
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 2, 1))) ==
            Set((("foo", ""), ("xxx", "foo"), ("x", "foo")))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 3, 1))) ==
            Set((("foo", ""), ("xxx", "foo"), ("xyz", ""), ("x", "foo")))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 5, 1))) ==
            Set((("foo", ""), ("xxx", "foo"), ("x", "foo")))
    end
end

@testset "outline" begin
    let str = """
        module Foo
        foo(x) = x
        function bar(x::Int)
            2x
        end
        const sss = 3
        end
        """
        @test Atom.outline(str) == Any[
            Dict(
                :type => "module",
                :name => "Foo",
                :icon => "icon-package",
                :lines => [1, 7]
            ),
            Dict(
                :type => "function",
                :name => "foo(x)",
                :icon => "λ",
                :lines => [2, 2]
            ),
            Dict(
                :type => "function",
                :name => "bar(x::Int)",
                :icon => "λ",
                :lines => [3, 5]
            ),
            Dict(
                :type => "constant",
                :name => "sss",
                :icon => "c",
                :lines => [6, 6]
            )
        ]
    end

    # kwargs shouldn't show up in outline, same as anon function args
    let str = """
        function bar(foo = 3)
            2x
        end
        const foo = (a,b) -> a+b
        const bar = (asd=3, bsd=4)
        """
        @test Atom.outline(str) == Any[
            Dict(
                :type => "function",
                :name => "bar(foo = 3)",
                :icon => "λ",
                :lines => [1, 3]
            ),
            Dict(
                :type => "constant",
                :name => "foo",
                :icon => "c",
                :lines => [4, 4]
            ),
            Dict(
                :type => "constant",
                :name => "bar",
                :icon => "c",
                :lines => [5, 5]
            ),
        ]
    end

    # destructure multiple return expression
    let str = """
        tuple = (one = 1, two = 2) # `(one = 1, two = 2)` shouldn't leak
        a, b = tuple # `a, b` should be correctly destructured
        const c1, c2 = tuple # static constantness checks
        """
        @test Atom.outline(str) == Any[
            Dict(
                :type => "variable",
                :name => "tuple",
                :icon => "v",
                :lines => [1, 1]
            ),
            Dict(
                :type => "variable",
                :name => "a, b",
                :icon => "v",
                :lines => [2, 2]
            ),
            Dict(
                :type => "constant",
                :name => "c1, c2",
                :icon => "c",
                :lines => [3, 3]
            )
        ]
    end

    # should stringify method signatures correctly
    let str = """
        withstrings(single = \"1\", triple = \"\"\"3\"\"\") = single * triple
        withchar(char = 'c') = char
        withkwarg(arg, defarg = 0; kwarg1 = 1, kwarg2 = 2) = defarg * kwarg
        """
        topbinds = map(b -> b[:name], Atom.outline(str))
        topbinds[1] == "withstrings(single=\"1\",triple=\"\"\"\"3\"\")"
        topbinds[2] == "withchar(char='c')"
        topbinds[3] == "withkwarg(arg,defarg=0;kwarg1=1,kwarg2=2)"
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
        calls = Atom.outline(str)

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
        items = Atom.outline(str)
        @test length(items) == 2
        let call = items[1]
            @test call[:type] == "module"
            @test call[:name] == "include(\"test.jl\")"
            @test call[:icon] == "icon-file-code"
        end
    end
end
