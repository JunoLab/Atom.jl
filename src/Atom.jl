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

include("debugger/debugger.jl")
@reexport using .Debugger

include("blink/BlinkDisplay.jl")
@reexport using .BlinkDisplay

end # module
