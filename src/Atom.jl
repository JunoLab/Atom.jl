__precompile__()

module Atom

using Juno, Lazy, JSON, MacroTools, Reexport, Media, Base.StackTraces

import Media: @dynamic

@init Juno.activate()

include("comm.jl")
include("display/display.jl")
include("progress.jl")
include("eval.jl")
include("repl.jl")
include("docs.jl")
include("completions.jl")
include("misc.jl")
include("frontend.jl")
include("utils.jl")

include("debugger/load.jl")

include("profiler/profiler.jl")

end # module
