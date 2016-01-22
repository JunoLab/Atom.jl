__precompile__()

module Atom

using Lazy, JSON, Blink, MacroTools, Reexport, Requires

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

include("blink/BlinkDisplay.jl")
@reexport using .BlinkDisplay

end # module
