__precompile__()

module Atom

using Juno, Lazy, JSON, MacroTools, Media, Base.StackTraces

using InteractiveUtils
import Requires
import Media: @dynamic

function __init__()
  Juno.activate()

  atreplinit() do repl
    fixdisplayorder()
  end

  Atom.handle("connected") do
    if isREPL(before_run_repl = true)
      reset_repl_history()
      fixdisplayorder()

      # HACK: overloading this allows us to open remote files
      InteractiveUtils.eval(quote
        function InteractiveUtils.edit(path::AbstractString, line::Integer=0)
          if endswith(path, ".jl")
              f = Base.find_source_file(path)
              f !== nothing && (path = f)
          end
          $(msg)("openFile", Base.abspath(path), line-1)
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
include("utils.jl")
include("display/display.jl")
include("progress.jl")
include("eval.jl")
include("workspace.jl")
include("repl.jl")
include("docs.jl")
include("outline.jl")
include("completions.jl")
include("goto.jl")
include("datatip.jl")
include("refactor.jl")
include("misc.jl")
include("formatter.jl")
include("frontend.jl")

include("debugger/debugger.jl")

include("profiler/profiler.jl")
include("profiler/traceur.jl")

end # module
