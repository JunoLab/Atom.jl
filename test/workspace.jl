@testset "workspace" begin
    cb = 0  # callback count
    handle(mod = "Main.Junk") =
        Atom.handlemsg(Dict("type"     => "workspace",
                            "callback" => (cb += 1)),
                       mod)

    include("fixtures/Junk.jl")
    handle()
    items = readmsg()[3][1]["items"]

    # basics
    @test filter(i -> i["name"] == "useme", items) |> !isempty
    @test filter(i -> i["name"] == "@immacro", items) |> !isempty

    # recoginise submodule
    @test filter(i -> i["name"] == "Junk2", items) |> !isempty

    # handle undefs
    @test filter(items) do item
        item["name"] == "imnotdefined" &&
        item["type"] == "ignored" &&
        item["nativetype"] == "Undefined"
    end |> !isempty

    # add variables dynamically
    @eval Main.Junk imadded = 100
    handle()
    @test filter(i -> i["name"] == "imadded", readmsg()[3][1]["items"]) |> !isempty
end
