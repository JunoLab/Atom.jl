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
            localgotoitem(word, line) = Atom.localgotoitem(word, "path", Inf64, line + 1, 0, str)[1]

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
        @test Atom.localgotoitem("word", "path", 1, 1, 0, "") == []
    end

    @testset "goto methods" begin
        using Atom: methodgotoitem
        #$ basic
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
