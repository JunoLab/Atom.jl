@testset "module validation" begin
    using Atom: toplevelitems

    path = subjunkspath
    text = read(path, String)

    # basic -- finds every toplevel items with default arguments
    @test filter(toplevelitems(text)) do item
        item isa Atom.ToplevelBinding &&
        item.bind.name == "imwithdoc"
    end |> length === 3

    # don't enter non-target modules, e.g.: submodules
    @test filter(toplevelitems(text; mod = "Junk", inmod = true)) do item
        item isa Atom.ToplevelBinding &&
        item.bind.name == "imwithdoc"
    end |> length === 1 # should only find the `imwithdoc` in Junk module

    # don't include items outside of a module
    @test filter(toplevelitems(text; mod = "SubJunk", inmod = false)) do item
        item isa Atom.ToplevelBinding &&
        item.bind.name == "imwithdoc"
    end |> length === 1 # should only find the `imwithdoc` in SubJunk module
end

@testset "outline edge cases" begin
    # don't leak something in a call
    for t in ["f(call())", "f(call(), @macro)", "f(@macro)", "f(@macro, arg; kwarg = kwarg)"]
        items = toplevelitems(t)
        @test length(items) === 1
        @test items[1] isa Atom.ToplevelCall
    end

    # https://github.com/JunoLab/Juno.jl/issues/502
    @test isempty(toplevelitems("ary[ind] = some"))

    # don't leak rhs of the assignemt
    let items = toplevelitems("lhs = rhscall(somearg)")
        @test length(items) === 1
        @test items[1].bind.name == "lhs"
    end
    let items = toplevelitems("lhs = @rhsmacrocall somearg")
        @test length(items) === 1
        @test items[1].bind.name == "lhs"
    end
end
