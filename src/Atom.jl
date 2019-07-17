__precompile__()

module Atom

using Juno, Lazy, JSON, MacroTools, Reexport, Media, Base.StackTraces

using InteractiveUtils
import Requires
import Media: @dynamic

function __init__()
  Juno.activate()

  atreplinit(i -> fixdisplayorder())

  Atom.handle("connected") do
    if isREPL()
      reset_repl_history()
      fixdisplayorder()

      # HACK: overloading this allows us to open remote files
      InteractiveUtils.eval(quote
        function InteractiveUtils.edit(path::AbstractString, line::Integer=0)
          if endswith(path, ".jl")
              f = Base.find_source_file(path)
              f !== nothing && (path = f)
          end
          $(msg)("openFile", f, line-1)
        end
      end)
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
include("datatip.jl")
include("workspace.jl")
include("repl.jl")
include("docs.jl")
include("completions.jl")
include("misc.jl")
include("formatter.jl")
include("frontend.jl")
include("utils.jl")

include("debugger/debugger.jl")

include("profiler/profiler.jl")
include("profiler/traceur.jl")

end # module
