__precompile__()

module Atom

using Juno, Lazy, JSON, MacroTools, Reexport, Media, Base.StackTraces

import Requires
import Media: @dynamic

function __init__()
  Juno.activate()

  atreplinit(i -> fixdisplayorder())

  Atom.handle("connected") do
    if isREPL()
      reset_repl_history()
      fixdisplayorder()
    end
    nothing
  end

  Requires.@require WebIO="0f1e0344-ec1d-5b48-a673-e5cf874b6c29" begin
    include("display/webio.jl")
  end
end

include("comm.jl")
include("display/display.jl")
include("progress.jl")
include("eval.jl")
include("workspace.jl")
include("repl.jl")
include("docs.jl")
include("completions.jl")
include("misc.jl")
include("frontend.jl")
include("utils.jl")

include("debugger/load.jl")

include("profiler/profiler.jl")

end # module
