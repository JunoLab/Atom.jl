@testset "goto symbols" begin
    @testset "goto local symbols" begin
        let str = """
            function localgotoitem(word, path, column, row, startRow, context) # L0
              position = row - startRow                                        # L1
              ls = locals(context, position, column)                           # L2
              filter!(ls) do l                                                 # L3
                l[:name] == word &&                                            # L4
                l[:line] < position                                            # L5
              end                                                              # L6
              map(ls) do l # there should be zero or one element in `ls`       # L7
                text = l[:name]                                                # L8
                line = startRow + l[:line] - 1                                 # L9
                gotoitem(text, path, line)                                     # L10
              end                                                              # L11
            end                                                                # L12
            """
            localgotoitem(word, line) = Atom.localgotoitem(word, "path", Inf, line + 1, 0, str)[1]

            let item = localgotoitem("row", 2)
                @test item[:line] === 0
                @test item[:text] == "row"
                @test item[:file] == "path"
            end
            @test localgotoitem("position", 2)[:line] === 1
            @test localgotoitem("l", 4)[:line] === 3
            @test localgotoitem("l", 8)[:line] === 7
        end

        # don't error on fallback case
        @test Atom.localgotoitem("word", nothing, 1, 1, 0, "") == []
    end

    @testset "goto toplevel symbols" begin
        using Atom: realpath′, toplevelgotoitem

        ## where `Base.find_package(modstr)` works
        let dir = realpath′(joinpath(@__DIR__, "..", "src")),
            path = joinpath(dir, "comm.jl")

            # basic
            let items = toplevelgotoitem(Atom, "handlers", path, [])
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:text] == "handlers"
            end

            # when `path` isn't given e.g.: via docpane or workspace view
            let items = toplevelgotoitem(Atom, "handlers", nothing, [])
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:text] == "handlers"
            end

            # check recursive file inclusion works
            numfiles = 0
            for (d, ds, fs) ∈ walkdir(dir)
                for f ∈ fs
                    if endswith(f, ".jl") # .jl check is needed for travis, who creates hoge.cov files
                        numfiles += 1
                    end
                end
            end
            @test length(Atom.symbolscache) == numfiles - 1 # `-1` is because of display/webio.jl
        end

        ## where `Base.find_package(modstr)` works
        let path = joinpath(@__DIR__, "fixtures", "Junk.jl")
            include(path)

            # basic
            let items = toplevelgotoitem("Main.Junk", "toplevelval", path, [])
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:line] == 16
                @test items[1][:text] == "toplevelval"
            end

            # when `path` isn't given, don't work but shouldn't error
            @test toplevelgotoitem(Main.Junk, "toplevelval", nothing, []) == []

            # check caching works
            @test path ∈ keys(Atom.symbolscache)

            # test cache refreshing
            @test filter(Atom.symbolscache[path]) do item
                Atom.str_value(item.expr) == "toplevelval2"
            end |> isempty

            originallines = readlines(path)
            open(path, "w") do io
                for line ∈ originallines[1:end - 1]
                    write(io, line * "\n")
                end
                write(io, "toplevelval2 = :youshoulderaseme\n")
                write(io, "end\n")
            end
            try
                let items = toplevelgotoitem(Main.Junk, "toplevelval2", path, [path])
                    @test !isempty(items)
                    @test items[1][:file] == path
                    @test items[1][:line] == 18
                    @test items[1][:text] == "toplevelval2"
                end

                @test filter(Atom.symbolscache[path]) do item
                    Atom.str_value(item.expr) == "toplevelval2"
                end |> !isempty
            catch err
                @error err
            finally
                open(path, "w") do io
                    for line ∈ originallines
                        write(io, line * "\n")
                    end
                end
            end
        end

        # don't error on fallback case
        @test toplevelgotoitem(Main, "word", nothing, []) == []
    end

    @testset "goto methods" begin
        using Atom: methodgotoitem

        ## basic
        # `Atom.handlemsg` is not defined with default args
        let items = methodgotoitem("Main", "Atom.handlemsg")
            @test length(items) === length(methods(Atom.handlemsg))
        end

        ## module awareness
        let items = methodgotoitem("Atom", "handlemsg")
            @test length(items) === length(methods(Atom.handlemsg))
        end

        ## aggregate methods with default params
        @eval Main function funcwithdefaultargs(args, defarg = "default") end

        let items = methodgotoitem("Main", "funcwithdefaultargs")
            # should be handled as an unique method
            @test length(items) === 1
            # show a method with full arguments
            @test "funcwithdefaultargs(args, defarg)" ∈ map(i -> i[:text], items)
        end

        @eval Main function funcwithdefaultargs(args::String, defarg = "default") end

        let items = methodgotoitem("Main", "funcwithdefaultargs")
            # should be handled as different methods
            @test length(items) === 2
            # show methods with full arguments
            @test "funcwithdefaultargs(args, defarg)" ∈ map(i -> i[:text], items)
            @test "funcwithdefaultargs(args::String, defarg)" ∈ map(i -> i[:text], items)
        end
    end
end
