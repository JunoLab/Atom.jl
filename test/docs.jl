@testset "docs" begin
  @testset "searchdocs" begin
    using Atom: searchdocs′, _searchdocs

    @test !searchdocs′("sin")[:error]
        # module awareness
    @test all(_searchdocs("getfield′"; mod = "Atom")) do (score, docobj)
      docobj.mod == "Atom"
    end
        # strip module accessor
    @test all(_searchdocs("Atom.getfield′"; mod = "Main")) do (score, docobj)
      docobj.mod == "Atom"
    end
  end

  @testset "moduleinfo" begin
    using Atom: moduleinfo

    @test_nowarn moduleinfo("Main")
    @test all(moduleinfo("Atom")[:items]) do item
      item[:mod] == "Atom"
    end
  end
end
