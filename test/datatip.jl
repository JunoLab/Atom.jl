@testset "datatip" begin
    @testset "local datatips" begin
        let str = """
            function localdatatip(word, column, row, startRow, context) # L0
              position = row - startRow                                 # L1
              ls = locals(context, position, column)                    # L2
              filter!(ls) do l                                          # L3
                l[:name] == word &&                                     # L4
                l[:line] < position                                     # L5
              end                                                       # L6
              # there should be zero or one element in `ls`             # L7
              map(l -> localdatatip(l, word, startRow), ls)             # L8
            end                                                         # L9
            """
            localdatatip(word, line) = Atom.localdatatip(word, Inf, line + 1, 0, str)[1]
            @test localdatatip("row", 1) == 0 # line
            @test localdatatip("position", 2) == Dict(:type => :snippet, :value => "position = row - startRow") # binding string
            @test localdatatip("l", 4) == 3 # line
        end

        # don't error on fallback case
        @test Atom.localdatatip("word", 1, 1, 0, "") == []
    end

    @testset "code block search" begin
        using Base.Docs
        using Atom: searchcodeblocks

        @eval Main begin
            @doc """
                codeblocktest()

            this doc should n't be captured

            ```julia
            julia> codeblocktest()
            you should move away from atom-ide-ui asap
            ```
            """
            codeblocktest() = print("you should move away from atom-ide-ui asap")
        end

        let codes = searchcodeblocks(@doc codeblocktest)
            @test filter(codes) do code
                occursin(r"codeblocktest()", code)
            end |> !isempty
            @test filter(codes) do code
                occursin(r"this doc should n't be captured", code)
            end |> isempty
            @test filter(codes) do code
                occursin(r"julia> codeblocktest()", code)
            end |> !isempty
        end
    end

    @testset "toplevel datatips" begin
        using Atom: topleveldatatip

        ## method datatip
        @eval Main begin
            @doc """
                datatipmethodtest()

            this doc should be shown in datatip
            """
            datatipmethodtest() = nothing
        end

        let datatip = topleveldatatip("Main", "datatipmethodtest")
            @test datatip isa Vector
            firsttip = datatip[1]
            secondtip = datatip[2]
            @test firsttip[:type] == :snippet
            @test occursin(r"datatipmethodtest()", firsttip[:value])
            @test secondtip[:type] == :markdown
            @test occursin(r"this doc should be shown in datatip", secondtip[:value])
        end

        ## variable datatip
        @eval Main datatipvariabletest = "this string should be shown in datatip"

        let datatip = topleveldatatip("Main", "datatipvariabletest")
            @test datatip isa Vector
            firsttip = datatip[1]
            @test firsttip[:type] == :snippet
            @test occursin(r"this string should be shown in datatip", firsttip[:value])
        end
    end
end
