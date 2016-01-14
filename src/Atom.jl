__precompile__()

module Atom

using Lazy, JSON, Blink

include("comm.jl")
include("display/display.jl")
include("eval.jl")
include("completions.jl")
include("misc.jl")
include("frontend.jl")
include("utils.jl")

function __init__()
  include(joinpath(dirname(@__FILE__), "patch.jl"))
end

end # module
