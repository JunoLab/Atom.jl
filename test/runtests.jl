using Atom
using Test
using Lazy
import JSON


# mock a listener
Core.eval(Atom, Meta.parse("sock = IOBuffer()"))
readmsg() = JSON.parse(String(take!(Atom.sock)))


include("./misc.jl") # basics
include("./utils.jl")
include("./eval.jl")
include("./outline.jl")
include("./completions.jl")
include("./goto.jl")
include("./workspace.jl")
include("./display.jl")
