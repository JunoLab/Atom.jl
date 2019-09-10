@testset "basic message handling" begin
    cb = 0  # callback count
    function handle(type, args...)
        Atom.handlemsg(Dict("type"     => type,
                            "callback" => (cb += 1)),
                       args...)
    end
    function expect(expected)
        @test readmsg() == ["cb", cb, expected]
    end


    # pingpong
    handle("ping")
    expect("pong")

    # echo
    handle("echo", "echome!")
    expect("echome!")

    # cd
    oldpath = pwd()
    handle("cd", joinpath(oldpath, ".."))
    expect(nothing)
    @test pwd() == realpath(joinpath(oldpath, ".."))
    cd(oldpath)

    # evalsimple
    handle("evalsimple", "1 + 1")
    expect(2)
    handle("evalsimple", "sin(pi)")
    expect(sin(pi))
end

@testset "outline" begin
    let str = """
        module Foo
        foo(x) = x
        function bar(x::Int)
            2x
        end
        const sss = 3
        end
        """
        @test Atom.outline(str) == Any[
            Dict(
                :type => "module",
                :name => "Foo",
                :icon => "icon-package",
                :lines => [1, 7]
            ),
            Dict(
                :type => "function",
                :name => "foo(x)",
                :icon => "λ",
                :lines => [2, 2]
            ),
            Dict(
                :type => "function",
                :name => "bar(x::Int)",
                :icon => "λ",
                :lines => [3, 5]
            ),
            Dict(
                :type => "variable",
                :name => "sss",
                :icon => "v",
                :lines => [6, 6]
            )
        ]
    end
    # kwargs shouldn't show up in outline, same as anon function args
    let str = """
        function bar(foo = 3)
            2x
        end
        const foo = (a,b) -> a+b
        """
        @test Atom.outline(str) == Any[
            Dict(
                :type => "function",
                :name => "bar(foo=3)",
                :icon => "λ",
                :lines => [1, 3]
            ),
            Dict(
                :type => "variable",
                :name => "foo",
                :icon => "v",
                :lines => [4, 4]
            ),
        ]
    end
end
