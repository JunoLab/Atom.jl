@testset "module validation" begin
    using Atom: toplevelitems

    path = subjunkspath
    text = read(path, String)
    parsed = CSTParser.parse(text, true)

    # basic -- finds every toplevel items when `mod` options is `nothing` (default)
    @test filter(toplevelitems(parsed, text; mod = nothing)) do item
        item isa Atom.ToplevelBinding &&
        item.bind.name == "imwithdoc"
    end |> length === 3

    # don't enter non-target modules, e.g.: submodules
    @test filter(toplevelitems(parsed, text; mod = "Junk")) do item
        item isa Atom.ToplevelBinding &&
        item.bind.name == "imwithdoc"
    end |> length === 1 # only `imwithdoc` in Junk module

    # don't include items outside of a module
    # FIX: currently broken -- include `imwithdoc` in Junk module as well
    @test_broken filter(toplevelitems(parsed, text; mod = "SubJunk")) do item
        item isa Atom.ToplevelBinding &&
        item.bind.name == "imwithdoc"
    end |> length === 1 # only `imwithdoc` in Junk module
end
