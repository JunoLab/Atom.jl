module Atom

using Lazy, JSON

include("comm.jl")
include("eval.jl")
include("completions.jl")
include("misc.jl")
include("utils.jl")

end # module
