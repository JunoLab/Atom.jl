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
        for l in [
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
            @test l in ls
        end
    end

    let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 21, 100)))
        for l in [
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
            @test l in ls
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
        for o in outers; @test o in ls; end
    end
    let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 2, 1)))
        for o in outers; @test o in ls; end
        @test ("x", "f") in ls
        @test ("ff", "f") in ls
    end
    let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 4, 100)))
        for o in outers; @test o in ls; end
        @test ("ff", "f") in ls
        @test ("x", "") in ls
        @test ("xxx", "") in ls
        @test ("z", "") in ls
    end
    let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 10, 100)))
        for o in outers; @test o in ls; end
        @test ("x", "foo") in ls
        @test ("asd", "foo") in ls
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
        @test l[:name] in ("tpl1", "tpl2")
        @test l[:root] == "foo"
        @test l[:bindstr] == "tpl1, tpl2 = (1, 2)"
    end
    # named tuple elements shouldn't show up in completions
    for l in filter(l -> l[:line] == 3, ls)
        @test l[:name] in ("shown1", "shown2")
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

# finds function arguments when the function is type-declared
# ref: https://github.com/JunoLab/Atom.jl/issues/223
let str = """
    function func(ary::Vector{T}, i::Int)::T where {T<:Number}
        # here
        s = sum(ary[1:i])
        return s
    end
    """

    binds = map(l -> l[:name], Atom.locals(str, 2, 4))
    @test "ary" in binds
    @test "i" in binds
    @test "T" in binds
    @test "func" in binds
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
        for l in [
                ("foo", "")
                ("xxx", "foo")
                ("x", "foo")
            ]
            @test l in ls
        end
    end
    let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 3, 1)))
        for l in [
                ("foo", "")
                ("xxx", "foo")
                ("xyz", "")
                ("x", "foo")
            ]
            @test l in ls
        end
    end
    let ls = Set(map(x -> (x[:name], x[:root]), Atom.locals(str, 5, 1)))
        for l in [
                ("foo", "")
                ("xxx", "foo")
                ("x", "foo")
            ]
            @test l in ls
        end
    end
end
