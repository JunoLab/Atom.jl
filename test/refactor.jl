@testset "rename refactor" begin
  import Atom: renamerefactor

  @testset "catch invalid/unsupported refactorings" begin
    # catch renaming on keywords
    let result = renamerefactor("function", "function", "func")
      @test haskey(result, :warning)
    end

    # catch field renaming
    let result = renamerefactor("field", "obj.field", "newfield")
      @test haskey(result, :warning)
    end

    # but when dot-accessed object is a (existing) module, continues refactoring
    let result = renamerefactor("bind", "Main.bind", "newbind")
      @test !haskey(result, :warning)
      @test haskey(result, :info)
    end
  end

  @testset "local rename refactor" begin
    # TODO
  end

  @testset "global rename refactor" begin
    @testset "catch edge cases" begin
      # handle refactoring on an unsaved / non-existing file
      let context = """
        toplevel() = nothing
        """
        # mock MAIN_MODULE_LOCATION update in `module` handler
        @eval Atom begin
          MAIN_MODULE_LOCATION[] = "", 1
        end
        result = renamerefactor("toplevel", "toplevel", "toplevel2", 0, 1, 1, context)
        @test haskey(result, :warning)
        @test result[:warning] == Atom.unsaveddescription()
      end

      # handle refactoring on nonwritable files
      let path = joinpath(@__DIR__, "fixtures", "Junk.jl")
        originalmode = Base.filemode(path)

        try
          Base.chmod(path, 0x444) # only reading
          context = "module Junk2 end"
          result = renamerefactor("Junk2", "Junk2", "Junk3", 0, 1, 1, context, "Main.Junk")

          @test haskey(result, :warning)
          @test result[:warning] == Atom.nonwritablesdescription(Main.Junk, [path])
        catch err
          @info """
          Cancelled the test for handling of refactorings on non-writable
          files due to the error below:
          """ err
        finally
          Base.chmod(path, originalmode)
        end
      end
    end
  end
end
