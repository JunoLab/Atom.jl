@testset "goto symbols" begin
    using Atom: todict

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
            localgotoitem(word, line) = Atom.localgotoitem(word, "path", typemax(Int), line + 1, 0, str)[1] |> todict

            let item = localgotoitem("row", 2)
                @test item[:line] === 0
                @test item[:text] == "row"
                @test item[:file] == "path"
            end
            @test localgotoitem("position", 2)[:line] === 1
            @test localgotoitem("l", 4)[:line] === 3
            @test localgotoitem("l", 8)[:line] === 7
        end

        # ignore dot accessors
        let str = """
            function withdots(expr::CSTParser.EXPR)
                bind = CSTParser.bindingof(expr.args[1])
                val = bind.val
                return val
            end
            """,
            localgotoitem(word, line) = Atom.localgotoitem(word, "path", typemax(Int), line + 1, 0, str)[1] |> todict

            @test localgotoitem("expr.args", 1)[:line] === 0
            @test localgotoitem("bind.val", 2)[:line] === 1
        end

        # don't error on fallback case
        @test_nowarn @test Atom.localgotoitem("word", nothing, 1, 1, 0, "") == []
    end

    @testset "goto global symbols" begin
        using Atom: globalgotoitems, toplevelgotoitems, SYMBOLSCACHE, updatesymbols,
                    clearsymbols, regeneratesymbols, methodgotoitems

        ## strip a dot-accessed modules
        let
            path = joinpath′(@__DIR__, "..", "src", "comm.jl")
            text = read(path, String)
            items = todict.(globalgotoitems("Atom.handlers", Atom, path, text))
            @test !isempty(items)
            @test items[1][:file] == path
            @test items[1][:text] == "handlers"
            items = todict.(globalgotoitems("Main.Atom.handlers", Atom, path, text))
            @test !isempty(items)
            @test items[1][:file] == path
            @test items[1][:text] == "handlers"

            # can access the non-exported (non-method) bindings in the other module
            path = joinpath′(@__DIR__, "..", "src", "goto.jl")
            text = read(@__FILE__, String)
            items = todict.(globalgotoitems("Atom.SYMBOLSCACHE", Main, @__FILE__, text))
            @test !isempty(items)
            @test items[1][:file] == path
            @test items[1][:text] == "SYMBOLSCACHE"
        end

        @testset "goto modules" begin
            let item = globalgotoitems("Atom", Main, nothing, "")[1] |> todict
                @test item[:file] == joinpath′(atomsrcdir, "Atom.jl")
                @test item[:line] == 3
            end
            let item = globalgotoitems("SubJunk", Junk, nothing, "")[1] |> todict
                @test item[:file] == subjunkspath
                @test item[:line] == 3
            end
        end

        @testset "goto toplevel symbols" begin
            ## where Revise approach works, i.e.: precompiled modules
            let path = joinpath′(atomsrcdir, "comm.jl")
                mod = Atom
                key = "Atom"
                word = "handlers"

                # basic
                let items = todict.(toplevelgotoitems(word, mod, path, ""))
                    @test !isempty(items)
                    @test items[1][:file] == path
                    @test items[1][:text] == word
                end

                # check caching works
                @test haskey(SYMBOLSCACHE, key)

                # check the Revise-like approach finds all files in Atom module
                @test length(SYMBOLSCACHE[key]) == length(atommodfiles)

                # when `path` isn't given, i.e. via docpane / workspace
                let items = todict.(toplevelgotoitems(word, mod, nothing, ""))
                    @test !isempty(items)
                    @test items[1][:file] == path
                    @test items[1][:text] == word
                end

                # same as above, but without any previous cache -- falls back to CSTPraser-based module-walk
                delete!(SYMBOLSCACHE, key)

                let items = toplevelgotoitems(word, mod, nothing, "") .|> todict
                    @test !isempty(items)
                    @test items[1][:file] == path
                    @test items[1][:text] == word
                end

                # check CSTPraser-based module-walk finds all the included files
                # NOTE: webio.jl is excluded since `include("webio.jl")` is a toplevel call
                @test length(SYMBOLSCACHE[key]) == length(atommodfiles)
            end

            ## where the Revise-like approach doesn't work, e.g. non-precompiled modules
            let path = junkpath
                mod = Main.Junk
                key = "Main.Junk"
                word = "toplevelval"

                # basic -- no need to pass a buffer text
                let items = toplevelgotoitems(word, mod, path, "") .|> todict
                    @test !isempty(items)
                    @test items[1][:file] == path
                    @test items[1][:line] == 14
                    @test items[1][:text] == word
                end

                # check caching works
                @test haskey(Atom.SYMBOLSCACHE, key)

                # when `path` isn't given, i.e.: via docpane / workspace
                let items = toplevelgotoitems(word, mod, nothing, "") .|> todict
                    @test !isempty(items)
                    @test items[1][:file] == path
                    @test items[1][:line] == 14
                    @test items[1][:text] == word
                end
            end

            ## escape recursive `include` loop
            let
                @test (Atom._collecttoplevelitems_static(nothing, joinpath′(fixturedir, "self_recur.jl"); inmod = true); true)
                @test (Atom._collecttoplevelitems_static(nothing, joinpath′(fixturedir, "mutual_recur.jl"); inmod = true); true)
            end

            ## don't include bindings outside of a module
            let path = subjunkspath
                text = read(subjunkspath, String)
                mod = Main.Junk.SubJunk
                word = "imwithdoc"

                items = toplevelgotoitems(word, mod, path, text) .|> todict
                @test length(items) === 1
                if length(items) === 1
                    @test items[1][:file] == path
                    @test items[1][:line] == 6
                    @test items[1][:text] == word
                end
            end

            ## `Main` module -- use a passed buffer text
            let path = joinpath′(@__DIR__, "runtests.jl")
                text = read(path, String)
                mod = Main
                word = "atomsrcdir"

                items = toplevelgotoitems(word, mod, path, text) .|> todict
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:line] == 6
                @test items[1][:text] == word
            end

            # don't mix a function and a macro with the same name
            let items = toplevelgotoitems("samefoo", Main.Junk, nothing, "")
                @test length(items) == 1
                @test items[1].name == "samefoo"
                @test items[1].text == "samefoo(args)"
                @test items[1].file == junkpath
                @test items[1].line == 22
            end
            let items = toplevelgotoitems("@samefoo", Main.Junk, nothing, "")
                @test length(items) === 1
                @test items[1].name == "@samefoo"
                @test items[1].text == "samefoo(ex)"
                @test items[1].file == junkpath
                @test items[1].line == 23
            end
        end

        @testset "updating toplevel symbols" begin
            # check there is no cache before updating
            mod = Main.Junk
            key = "Main.Junk"
            path = junkpath
            text = read(path, String)
            @test filter(SYMBOLSCACHE[key][path]) do item
                item.name == "toplevelval2"
            end |> isempty

            # mock updatesymbol handler
            originallines = readlines(path)
            newtext = join(originallines[1:end - 1], '\n')
            word = "toplevelval2"
            newtext *= "\n$word = :youshoulderaseme\nend"
            updatesymbols(key, path, newtext)

            # check the cache is updated
            @test filter(SYMBOLSCACHE[key][path]) do item
                item.name == word
            end |> !isempty

            let items = toplevelgotoitems(word, mod, path, newtext) .|> todict
                @test !isempty(items)
                @test items[1][:file] == path
                @test items[1][:text] == "toplevelval2"
            end

            # re-update the cache
            updatesymbols(key, path, text)
            @test filter(SYMBOLSCACHE[key][path]) do item
                item.name == word
            end |> isempty

            # don't error on fallback case
            @test_nowarn @test updatesymbols(key, nothing, text) === nothing
        end

        @testset "regenerating toplevel symbols" begin
            regeneratesymbols()

            # cache symbols in loaded modules
            @test haskey(SYMBOLSCACHE, "Base")
            @test length(keys(SYMBOLSCACHE["Base"])) > 100
            @test haskey(SYMBOLSCACHE, "Atom")
            @test length(keys(SYMBOLSCACHE["Atom"])) === length(atommodfiles)

            # cache symbols even if not loaded
            # FIXME:
            # `Pkg.dependencies()` doesn't include dependencies in `extra` section.
            # Let's skip this case until we find a way to make `Pkg.dependencies()` aware of them.
            @test_skip haskey(SYMBOLSCACHE, "Example")

            @testset "goto for unloaded packages" begin
                using Atom: globalgotoitems_unloaded

                @test !isempty(globalgotoitems_unloaded("hello", "Example"))
            end
        end

        @testset "clear toplevel symbols" begin
            clearsymbols()

            @test length(keys(SYMBOLSCACHE)) === 0
        end

        @testset "goto methods" begin
            ## basic
            let ms = methods(Atom.handlemsg)
                @test length(methodgotoitems(ms)) === length(ms)
            end

            ## aggregate methods with default params
            @eval Main function funcwithdefaultargs(args, defarg = "default") end

            let items = methodgotoitems(methods(funcwithdefaultargs)) .|> todict
                # should be handled as an unique method
                @test length(items) === 1
                # show a method with full arguments
                @test "funcwithdefaultargs(args, defarg)" in map(i -> i[:text], items)
            end

            @eval Main function funcwithdefaultargs(args::String, defarg = "default") end

            let items = methodgotoitems(methods(funcwithdefaultargs)) .|> todict
                # should be handled as different methods
                @test length(items) === 2
                # show methods with full arguments
                @test "funcwithdefaultargs(args, defarg)" in map(i -> i[:text], items)
                @test "funcwithdefaultargs(args::String, defarg)" in map(i -> i[:text], items)
            end
        end

        ## both the original methods and the toplevel bindings that are overloaded in a context module should be shown
        let items = globalgotoitems("isconst", Main.Junk, nothing, "")
            @test length(items) === 2
            @test "isconst(m::Module, s::Symbol)" in map(item -> item.text, items) # from Base
            @test "Base.isconst(::JunkType)" in map(item -> item.text, items) # from Junk
        end

        ## don't error on the fallback case
        @test_nowarn @test globalgotoitems("word", Main, nothing, "") == []
    end
end
