old_pwd = pwd()
cd(dirname(@__FILE__))

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
@test Atom.pkgpath("foo/pkgname/src/foobar.jl") == "pkgname/src/foobar.jl"
@test Atom.pkgpath("foo\\pkgname ü\\src\\foobar.jl") == "pkgname ü\\src\\foobar.jl"

@test Atom.fullpath("untitled-asdj2cx3213") == "untitled-asdj2cx3213"
@test Atom.fullpath("/test/foobar.jl") == "/test/foobar.jl"
@test joinpath(split(Atom.fullpath("foobar.jl"), Base.Filesystem.pathsep())[end-1:end]...)  == joinpath("base", "foobar.jl")

@test Atom.appendline("test.jl", -1) == "test.jl"
@test Atom.appendline("test.jl", 0) == "test.jl"
@test Atom.appendline("test.jl", 10) == "test.jl:10"

@test isfile(Atom.expandpath(Atom.view(first(methods(rand)))[2].file)[2])

@test isfile(Atom.package_file_path("Atom", "repl.jl"))

#TODO: baselink, edit

cd(old_pwd)
