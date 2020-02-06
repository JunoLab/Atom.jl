@testset "modules" begin
    @testset "find module definition" begin
        using Atom: moduledefinition

        let (path, line) = moduledefinition(Atom)
            @test path == atomjlfile
            @test line == 4
        end
        let (path, line) = moduledefinition(Junk)
            @test path == junkpath
            @test line == 1
        end
        let (path, line) = moduledefinition(Junk.SubJunk)
            @test path == subjunkspath
            @test line == 4
        end
    end

    @testset "find module files" begin
        using Atom: modulefiles, use_compiled_modules

        ## Revise-like module file detection
        # NOTE: only test when using compiled modules
        if use_compiled_modules()
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
        else
            @warn "skipped Revise-like module file detection test (precompiled modules are currently not used)"
        end

        ## CSTPraser-based module file detection
        # basic
        let included_files = normpath.(modulefiles("Atom", atomjlfile))
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

        # safety checks for recursive `include`s
        @test (modulefiles("Main", joinpath′(fixturedir, "self_recur.jl"); inmod = true); true)
        @test (modulefiles("Main", joinpath′(fixturedir, "mutual_recur.jl"); inmod = true); true)
    end
end
