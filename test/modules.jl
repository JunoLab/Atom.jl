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
            # # XXX modules.jl is unmaintained now and kinda broken for v1.6
            # # works for precompiled packages
            # let (parentfile, included_files) = modulefiles(Atom)
            #     for f in included_files
            #         @test f in atommodfiles
            #     end
            #     # NOTE: `+ 1` stands for Atom.jl (`parentfile`)
            #     @test length(included_files) + 1 === length(atommodfiles)
            #
            #     # TODO:
            #     # Revise-like module traverse fails to detect lazily loaded files even if
            #     # they are actually loaded.
            #     @test_broken webiofile in included_files
            #     @test_broken traceurfile in included_files
            # end

            # fails for non-precompiled packages
            @test_broken junkpath == modulefiles(Junk)[1]
        else
            @warn "skipped Revise-like module file detection test (precompiled modules are currently not used)"
        end

        ## CSTPraser-based module file detection
        # basic
        let included_files = normpath.(modulefiles("Atom", atomjlfile))
            for f in included_files
                @test f in atommodfiles
            end
            @test length(included_files) === length(atommodfiles)

            # TODO:
            # CSTParser-based module traverse is currently not able to find non-toplevel
            # `include` calls
            @test_broken webiofile in included_files
            @test_broken traceurfile in included_files
        end

        # safety checks for recursive `include`s
        @test (modulefiles("Main", joinpath′(fixturedir, "self_recur.jl"); inmod = true); true)
        @test (modulefiles("Main", joinpath′(fixturedir, "mutual_recur.jl"); inmod = true); true)
    end
end
