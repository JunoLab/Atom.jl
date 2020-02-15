@testset "docs" begin
  @testset "searchdocs" begin
    using Atom: searchdocs′

    # don't error on fallback case
    @test !searchdocs′("sin")[:error]

    # don't erase module input when it's used
    @test !searchdocs′("getfield′", true, "Atom")[:shoulderase]
    # erase module input when it's replaced by module prefix in search text
    @test searchdocs′("Atom.getfield′", true, "Main")[:shoulderase]
  end

  @testset "moduleinfo" begin
    using Atom: moduleinfo

    @test_nowarn moduleinfo("Main")
    @test all(moduleinfo("Atom")[:items]) do item
      item[:mod] == "Atom"
    end
  end
end
