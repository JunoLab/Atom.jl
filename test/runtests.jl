using Atom
using Test
using Lazy
import JSON


# mock a listener
Core.eval(Atom, Meta.parse("sock = IOBuffer()"))
readmsg() = JSON.parse(String(take!(Atom.sock)))


include("./misc.jl") # basics
include("./eval.jl")
include("./workspace.jl")
include("./completions.jl")
include("./utils.jl")
include("./display.jl")
