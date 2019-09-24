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
            y = (foo = 3, bar = 4) # named tuple elements shouldn't show up in completions
            return y+x
        end
        kwfun(kw = 3) # `kw` should not show up in completions
        function foo(x)
            asd = 3
        end
        function baz(x) # should destructure multiple return values
           shown1, shown2 = (notshown1 = 1, notshown2 = 2) # should n't leak named tuple names
        end
        """
        outers = (("bar", ""), ("f", ""), ("foo", ""), ("baz", ""))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 1, 1))) ==
            Set(outers)
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 2, 100))) ==
            Set((("x", "f"), ("ff", "f"), ("y", "f"), outers...))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 4, 100))) ==
            Set((("ff", "f"), ("x", ""), ("xxx", ""), ("z", ""), ("y", "f"), outers...))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 10, 100))) ==
            Set((("x", "foo"), ("asd", "foo"), outers...))
        @test Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 13, 100))) ==
            Set((("x", "baz"), ("shown1", "baz"), ("shown2", "baz"), outers...))
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
                :type => "variable",
                :name => "sss",
                :icon => "v",
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
                :name => "bar(foo=3)",
                :icon => "λ",
                :lines => [1, 3]
            ),
            Dict(
                :type => "variable",
                :name => "foo",
                :icon => "v",
                :lines => [4, 4]
            ),
            Dict(
                :type => "variable",
                :name => "bar",
                :icon => "v",
                :lines => [5, 5]
            ),
        ]
    end

    # destructure multiple return expression
    let str = """
        tuple = (one = 1, two = 2) # `(one = 1, two = 2)` shouldn't leak
        a, b = tuple # `a, b` should be correctly destructured
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
                :name => "a,b",
                :icon => "v",
                :lines => [2, 2]
            )
        ]
    end
end
