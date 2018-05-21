__precompile__()

module Atom

using Juno, Lazy, JSON, Blink, MacroTools, Reexport, Media

import Media: @dynamic

@init Juno.activate()

include("comm.jl")
include("display/display.jl")
include("eval.jl")
include("repl.jl")
include("docs.jl")
include("completions.jl")
include("misc.jl")
include("frontend.jl")
include("utils.jl")
include("progress.jl")

include("debugger/load.jl")

include("profiler/profiler.jl")

include("linting/traceur.jl")

include("blink/BlinkDisplay.jl")
@reexport using .BlinkDisplay

end # module
