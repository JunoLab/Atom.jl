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
include("debugger/load.jl")

include("blink/BlinkDisplay.jl")
@reexport using .BlinkDisplay

include("precompile.jl")

end # module
