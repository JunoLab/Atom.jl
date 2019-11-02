@testset "modules" begin
    @testset "find module definition" begin
        using Atom: moduledefinition

        let (path, line) = moduledefinition(Atom)
            @test path == joinpath′(@__DIR__, "..", "src", "Atom.jl")
            @test line == 4
        end
        let (path, line) = moduledefinition(Junk)
            @test path == joinpath′(@__DIR__, "fixtures", "Junk.jl")
            @test line == 1
        end
        let (path, line) = moduledefinition(Junk.Junk2)
            @test path == joinpath′(@__DIR__, "fixtures", "Junk.jl")
            @test line == 15
        end
    end

    @testset "find module files" begin
        using Atom: modulefiles

        ## Revise-like module file detection
        # works for precompiled packages
        let (parentfile, included_files) = modulefiles(Atom)
            expected = Set(atommodfiles)
            actual = Set((parentfile, included_files...))
            @test actual == expected

            # can't detect display/webio.jl
            @test_broken webiofile in modfiles
        end

        # fails for non-precompiled packages
        @test_broken junkpath == modulefiles(Junk)[1]

        ## CSTPraser-based module file detection
        let included_files = normpath.(modulefiles("Atom", joinpath′(atomjldir, "Atom.jl")))
            # finds all the files in Atom module except display/webio.jl
            for f in atommodfiles
                f == webiofile && continue
                @test f in included_files
            end

            # only finds files in a module -- exclude files in the submodules
            @test length(atommodfiles) == length(included_files)

            # can't look for non-toplevel `include` calls
            @test_broken webiofile in included_files
        end
    end
end
