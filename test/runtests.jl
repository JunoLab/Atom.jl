using Atom
using Test
using Logging
import JSON


joinpath′(files...) = Atom.fullpath(joinpath(files...))

atomjldir = joinpath′(@__DIR__, "..", "src")

webiofile = joinpath′(atomjldir, "display", "webio.jl")

# files in `Atom` module (except files in its submodules)
atommodfiles = let
    files = []
    debuggerdir = joinpath′(atomjldir, "debugger")
    profilerdir = joinpath′(atomjldir, "profiler")
    for (d, ds, fs) in walkdir(atomjldir)
        # NOTE: update directories below when you create an new submodule
        # the 2 files below are in Atom module
        if d == debuggerdir
            push!(files, joinpath′(d, "debugger.jl"))
            continue
        end
        if d == profilerdir
            push!(files, joinpath′(d, "profiler.jl"))
            push!(files, joinpath′(d, "traceur.jl"))
            continue
        end
        for f in fs
            # NOTE: currently both Revise-like and CSTPraser-based approach fails
            # to detect display/webio.jl as a file in Atom module
            f == "webio.jl" && continue

            # .jl check is needed for travis, who creates hoge.cov files
            endswith(f, ".jl") && push!(files, joinpath′(d, f))
        end
    end
    files
end

# mock a listener
Core.eval(Atom, Meta.parse("sock = IOBuffer()"))
readmsg() = JSON.parse(String(take!(Atom.sock)))

# mock Module
junkpath = joinpath′(@__DIR__, "fixtures", "Junk.jl")
include(junkpath)


include("misc.jl") # basics
include("utils.jl")
include("eval.jl")
include("modules.jl")
include("outline.jl")
include("completions.jl")
include("goto.jl")
include("datatip.jl")
include("workspace.jl")
include("display.jl")
