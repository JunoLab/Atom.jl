old_pwd = pwd()
cd(dirname(@__FILE__))

@testset "path utilities" begin
    @test Atom.realpath′("./utils.jl") == realpath(@__FILE__)
    @test Atom.realpath′(".././dontexist") == ".././dontexist"

    @test Atom.isuntitled(".\\untitled-asdj2123:12") == true
    @test Atom.isuntitled(".\\untitled-asdj2cx3213") == true
    @test Atom.isuntitled("./untitled-asdj2124o3:12") == true
    @test Atom.isuntitled("./untitled-a1j2124o3:12") == true
    @test Atom.isuntitled("untitled-1651asdsd23") == true
    @test Atom.isuntitled("untitled1651asdsd23") == false
    @test Atom.isuntitled("untitled-1651asdsd23:as") == false
    @test Atom.isuntitled("./utils.jl") == false
    @test Atom.isuntitled("../test/utils.jl") == false

    @test Atom.pkgpath(@__FILE__) == "utils.jl"
    @test Atom.pkgpath("foo/bar/pkgname/src/foobar.jl") == "bar/pkgname/src/foobar.jl"
    @test Atom.pkgpath("foo\\bar\\pkgname ü\\src\\foobar.jl") == "bar\\pkgname ü\\src\\foobar.jl"

    @test Atom.fullpath("untitled-asdj2cx3213") == "untitled-asdj2cx3213"
    @test Atom.fullpath("/test/foobar.jl") == "/test/foobar.jl"
    @test joinpath(split(Atom.fullpath("foobar.jl"), Base.Filesystem.pathsep())[end-1:end]...)  == joinpath("base", "foobar.jl")

    @test Atom.appendline("test.jl", -1) == "test.jl"
    @test Atom.appendline("test.jl", 0) == "test.jl"
    @test Atom.appendline("test.jl", 10) == "test.jl:10"

    @test isfile(Atom.expandpath(Atom.view(first(methods(rand)))[2].file)[2])
end

@testset "methods and docs" begin
    @test first(Atom.getmethods("Main", "Atom.getmethods")) == first(methods(Atom.getmethods))
    @test !isempty(Atom.getmethods("Main", "@deprecate"))
    @test !isempty(Atom.getmethods("Main", "Base.@deprecate"))

    @test !isempty(Atom.getdocs("Main", "Atom.getmethods"))
    @test !isempty(Atom.getdocs("Main", "@deprecate"))
end

@testset "REPL path finding" begin
    if Sys.iswindows()
        @test Atom.fullREPLpath(raw"@ Atom C:\Users\ads\.julia\dev\Atom\src\repl.jl:25") == (raw"C:\Users\ads\.julia\dev\Atom\src\repl.jl", 25)
        @test Atom.fullREPLpath(raw"C:\Users\ads\.julia\dev\Atom\src\repl.jl:25") == (raw"C:\Users\ads\.julia\dev\Atom\src\repl.jl", 25)
        @test Atom.fullREPLpath(raw".\foo\bar.jl:1") == (Atom.fullpath(raw".\foo\bar.jl"), 1)
        @test Atom.fullREPLpath(raw"foo\bar.jl:1") == (Atom.fullpath(raw".\foo\bar.jl"), 1)
    else
        @test Atom.fullREPLpath("@ Atom /home/user/foo/.julia/bar.jl:25") == ("/home/user/foo/.julia/bar.jl", 25)
        @test Atom.fullREPLpath("/home/user/foo/.julia/bar.jl:25") == ("/home/user/foo/.julia/bar.jl", 25)
        @test Atom.fullREPLpath("./foo/bar.jl:1") == (Atom.fullpath("./foo/bar.jl"), 1)
        @test Atom.fullREPLpath("foo/bar.jl:1") == (Atom.fullpath("./foo/bar.jl"), 1)
    end
end

@testset "finding dev packages" begin
    @test Atom.finddevpackages() isa Dict
end

#TODO: baselink, edit

cd(old_pwd)
