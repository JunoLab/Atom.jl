__precompile__()

module Atom

using Juno, Lazy, JSON, Blink, MacroTools, Reexport, Media

import Media: @dynamic

@init Juno.activate()

include("comm.jl")
include("display/display.jl")
include("eval.jl")
include("completions.jl")
include("misc.jl")
include("frontend.jl")
include("utils.jl")

# Gallium.jl only works on 0.5
if VERSION.minor == 5
  include("debugger/load.jl")
end
include("profiler/profiler.jl")

include("blink/BlinkDisplay.jl")
@reexport using .BlinkDisplay

end # module
