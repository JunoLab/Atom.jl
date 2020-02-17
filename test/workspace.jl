@testset "workspace" begin
    using Atom: workspace

    items = workspace("Main.Junk")[1][:items]

    # basics
    let items = filter(i -> i[:name] == :useme, items)
        @test !isempty(items)
        @test items[1][:type] == "function"
        @test items[1][:icon] == "λ"
        @test items[1][:nativetype] == "Function"
    end

    # let items = filter(i -> i[:name] == Symbol("@immacro"), items)
    #     @test !isempty(items)
    #     @test items[1][:type] == "snippet"
    #     @test items[1][:icon] == "icon-mention"
    #     @test items[1][:nativetype] == "Function"
    # end

    # recoginise submodule
    let items = filter(i -> i[:name] == :SubJunk, items)
        @test !isempty(items)
        @test items[1][:type] == "module"
        @test items[1][:icon] == "icon-package"
        @test items[1][:nativetype] == "Module"
    end

    # handle undefs
    let items = filter(i -> i[:name] == :imnotdefined, items)
        @test !isempty(items)
        @test items[1][:type] == "ignored"
        @test items[1][:icon] == "icon-circle-slash"
        @test items[1][:nativetype] == "Undefined"
    end

    # add variables dynamically
    @eval Main.Junk imadded = 100
    items = workspace("Main.Junk")[1][:items]
    let items = filter(i -> i[:name] == :imadded, items)
        @test !isempty(items)
        @test items[1][:type] == "variable"
        @test items[1][:icon] == "n"
        @test items[1][:nativetype] == "Int64"
    end
end
