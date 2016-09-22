__precompile__()

module Atom

using Juno, Lazy, JSON, Blink, MacroTools, Reexport, Requires

@init Juno.activate()

include("comm.jl")
include("display/display.jl")
include("eval.jl")
include("completions.jl")
include("misc.jl")
include("frontend.jl")
include("utils.jl")

# only require the debugger on 0.5.x for now
@static if VERSION.minor == 5
  include("debugger/debugger.jl")
  @reexport using .Debugger
else
  include("debugger/mockingbird.jl")
end

include("blink/BlinkDisplay.jl")
@reexport using .BlinkDisplay

end # module
