@testset "goto symbols" begin
    using Atom: modulegotoitems, realpath′, toplevelgotoitems, SYMBOLSCACHE,
                regeneratesymbols, methodgotoitems, globalgotoitems
    using CSTParser

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
            """,
            localgotoitem(word, line) = Atom.localgotoitem(word, "path", Inf, line + 1, 0, str)[1] |> Dict

            let item = localgotoitem("row", 2)
                @test item[:line] === 0
                @test item[:text] == "row"
                @test item[:file] == "path"
            end
            @test localgotoitem("position", 2)[:line] === 1
            @test localgotoitem("l", 4)[:line] === 3
            @test localgotoitem("l", 8)[:line] === 7
        end

        # remove dot accessors
        let str = """
            function withdots(expr::CSTParser.EXPR)
                bind = CSTParser.bindingof(expr.args[1])
                val = bind.val
                return val
            end
            """,
            localgotoitem(word, line) = Atom.localgotoitem(word, "path", Inf, line + 1, 0, str)[1] |> Dict

            @test localgotoitem("expr.args", 1)[:line] === 0
            @test localgotoitem("bind.val", 2)[:line] === 1
        end

        # don't error on fallback case
        @test Atom.localgotoitem("word", nothing, 1, 1, 0, "") == []
    end

    @testset "module goto" begin
        let item = modulegotoitems("Atom", Main)[1]
            @test item.file == realpath′(joinpath(@__DIR__, "..", "src", "Atom.jl"))
            @test item.line == 2
        end
        let item = modulegotoitems("Junk2", Main.Junk)[1]
            @test item.file == joinpath(@__DIR__, "fixtures", "Junk.jl")
            @test item.line == 14
        end
    end

    @testset "goto toplevel symbols" begin
        ## where Revise approach works, i.e.: precompiled modules
        let dir = realpath′(joinpath(@__DIR__, "..", "src"))
            path = joinpath(dir, "comm.jl")
            text = read(path, String)
            mod = Atom
            key = "Atom"
            word = "handlers"

            # basic
            let items = toplevelgotoitems(word, mod, text, path) .|> Dict
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:text] == word
            end

            # check caching works
            @test haskey(SYMBOLSCACHE, key)

            # check the Revise-like approach finds all the included files
            let numfiles = 0
                debuggerpath = realpath′(joinpath(@__DIR__, "..", "src", "debugger"))
                profilerpath = realpath′(joinpath(@__DIR__, "..", "src", "profiler"))
                for (d, ds, fs) ∈ walkdir(dir)
                    if d ∈ (debuggerpath, profilerpath)
                        numfiles += 1 # debugger.jl / traceur.jl (in Atom module)
                        continue
                    end
                    for f ∈ fs
                        if endswith(f, ".jl") # .jl check is needed for travis, who creates hoge.cov files
                            numfiles += 1
                        end
                    end
                end
                @test length(SYMBOLSCACHE[key]) == numfiles
            end

            # when `path` isn't given, i.e. via docpane / workspace
            let items = toplevelgotoitems(word, mod, "", nothing) .|> Dict
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:text] == word
            end

            # same as above, but without any previous cache -- falls back to CSTPraser-based module-walk
            delete!(SYMBOLSCACHE, key)
            let items = toplevelgotoitems(word, mod, "", nothing) .|> Dict
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:text] == word
            end
        end

        ## where the Revise-like approach doesn't work, e.g. non-precompiled modules
        let path = junkpath
            text = read(path, String)
            mod = Main.Junk
            key = "Main.Junk"
            word = "toplevelval"

            # basic
            let items = toplevelgotoitems(word, mod, text, path) .|> Dict
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:line] == 16
                @test items[1][:text] == word
            end

            # check caching works
            @test haskey(Atom.SYMBOLSCACHE, key)

            # when `path` isn't given, i.e.: via docpane / workspace
            let items = toplevelgotoitems(word, mod, "", nothing) .|> Dict
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:line] == 16
                @test items[1][:text] == word
            end
        end

        # don't error on the fallback case
        @test toplevelgotoitems("word", Main, "", nothing) == []
    end

    @testset "updating toplevel symbols" begin
        mod = "Main.Junk"
        path = junkpath
        text = read(path, String)
        function updatesymbols(mod, text, path)
            parsed = CSTParser.parse(text, true)
            items = Atom.toplevelitems(parsed, text)
            Atom.updatesymbols(text, mod, path, items)
        end

        # check there is no cache before updating
        @test filter(SYMBOLSCACHE[mod][path]) do item
            Atom.str_value(item.expr) == "toplevelval2"
        end |> isempty

        # mock updatesymbol handler
        originallines = readlines(path)
        newtext = join(originallines[1:end - 1], '\n')
        word = "toplevelval2"
        newtext *= "\n$word = :youshoulderaseme\nend"
        updatesymbols(mod, newtext, path)

        # check the cache is updated
        @test filter(SYMBOLSCACHE[mod][path]) do item
            Atom.str_value(item.expr) == word
        end |> !isempty

        let items = toplevelgotoitems(word, mod, newtext, path) .|> Dict
            @test !isempty(items)
            @test items[1][:file] == path
            @test items[1][:text] == "toplevelval2"
        end

        # re-update the cache
        updatesymbols(mod, text, path)
        @test filter(SYMBOLSCACHE[mod][path]) do item
            Atom.str_value(item.expr) == word
        end |> isempty
    end

    @testset "regenerating symbols" begin
        regeneratesymbols()

        @test haskey(SYMBOLSCACHE, "Base")
        @test length(keys(SYMBOLSCACHE["Base"])) > 100
        @test haskey(SYMBOLSCACHE, "Example") # cache symbols even if not loaded
        @test toplevelgotoitems("hello", "Example", "", nothing) |> !isempty
    end

    @testset "goto methods" begin
        ## basic
        # `Atom.handlemsg` is not defined with default args
        let items = methodgotoitems("Main", "Atom.handlemsg")
            @test length(items) === length(methods(Atom.handlemsg))
        end

        ## module awareness
        let items = methodgotoitems("Atom", "handlemsg")
            @test length(items) === length(methods(Atom.handlemsg))
        end

        ## aggregate methods with default params
        @eval Main function funcwithdefaultargs(args, defarg = "default") end

        let items = methodgotoitems("Main", "funcwithdefaultargs") .|> Dict
            # should be handled as an unique method
            @test length(items) === 1
            # show a method with full arguments
            @test "funcwithdefaultargs(args, defarg)" ∈ map(i -> i[:text], items)
        end

        @eval Main function funcwithdefaultargs(args::String, defarg = "default") end

        let items = methodgotoitems("Main", "funcwithdefaultargs") .|> Dict
            # should be handled as different methods
            @test length(items) === 2
            # show methods with full arguments
            @test "funcwithdefaultargs(args, defarg)" ∈ map(i -> i[:text], items)
            @test "funcwithdefaultargs(args::String, defarg)" ∈ map(i -> i[:text], items)
        end
    end

    @testset "goto global symbols" begin # toplevel symbol goto & method goto
        # both the original methods and the toplevel bindings that are overloaded
        # in a context module should be shown
        let items = globalgotoitems("isconst", "Atom", "", nothing)
            @test length(items) === 2
            @test "isconst(m::Module, s::Symbol)" ∈ map(item -> item.text, items) # from Base
            @test "Base.isconst(expr::CSTParser.EXPR)" ∈ map(item -> item.text, items) # from Atom
        end
    end
end
