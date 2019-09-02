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
        function bar(x)
            2x
        end
        const sss = 3
        end
        """
        @test Atom.outline(str) == Any[
            ("Foo", 1:7),
            ("foo", 2:2),
            ("bar", 3:5),
            ("sss", 6:6),
        ]
    end
end
