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
        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 15, 1)))
            for l ∈ [
                    ("i", "")
                    ("arg", "")
                    ("localbindings", "local_bindings")
                    ("range", "local_bindings")
                    ("scope", "local_bindings")
                    ("bind", "local_bindings")
                    ("pos", "local_bindings")
                    ("bindings", "local_bindings")
                    ("expr", "local_bindings")
                    ("local_bindings", "")
                ]
                @test l ∈ ls
            end
        end

        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 21, 100)))
            for l ∈ [
                    ("localbindings", "local_bindings")
                    ("pos", "local_bindings")
                    ("scope", "local_bindings")
                    ("bind", "local_bindings")
                    ("bindings", "local_bindings")
                    ("expr", "local_bindings")
                    ("local_bindings", "")
                    ("range", "local_bindings")
                    ("local_bindings", "")
                ]
                @test l ∈ ls
            end
        end
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
        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 1, 1)))
            for o ∈ outers; @test o ∈ ls; end
        end
        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 2, 1)))
            for o ∈ outers; @test o ∈ ls; end
            @test ("x", "f") ∈ ls
            @test ("ff", "f") ∈ ls
        end
        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 4, 100)))
            for o ∈ outers; @test o ∈ ls; end
            @test ("ff", "f") ∈ ls
            @test ("x", "") ∈ ls
            @test ("xxx", "") ∈ ls
            @test ("z", "") ∈ ls
        end
        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 10, 100)))
            for o ∈ outers; @test o ∈ ls; end
            @test ("x", "foo") ∈ ls
            @test ("asd", "foo") ∈ ls
        end
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

    # detect all the method parameters of a method with a `where` clause
    let str = """
        function push!′(ary::Vector{T}, item::S) where {T, S<:T}
            tmpvec, tmpitem = ary, item
            push!(tmpvec, tmpitem)
        end
        """

        binds = map(l -> l[:name], Atom.locals(str, 1, 0))
        @test "ary" in binds
        @test "item" in binds
        @test "T" in binds
        @test "S" in binds
        @test "tmpvec" in binds
        @test "tmpitem" in binds
        @test "push!′" in binds
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
        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 2, 1)))
            for l ∈ [
                    ("foo", "")
                    ("xxx", "foo")
                    ("x", "foo")
                ]
                @test l ∈ ls
            end
        end
        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 3, 1)))
            for l ∈ [
                    ("foo", "")
                    ("xxx", "foo")
                    ("xyz", "")
                    ("x", "foo")
                ]
                @test l ∈ ls
            end
        end
        let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 5, 1)))
            for l ∈ [
                    ("foo", "")
                    ("xxx", "foo")
                    ("x", "foo")
                ]
                @test l ∈ ls
            end
        end
    end
end

@testset "outline" begin
    using CSTParser
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
