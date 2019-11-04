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
