__precompile__()

@doc read(joinpath(dirname(@__DIR__), "README.md"), String)
module Atom

using Base.StackTraces, InteractiveUtils, Logging
using Juno, Lazy, JSON, MacroTools, Media, Requires
import Media: @dynamic

function __init__()
  Juno.activate()

  atreplinit() do repl
    fixdisplayorder()
  end

  atreplinit(instantiate_repl_keybindings)

  start_eval_backend()

  Atom.handle("connected") do
    if isREPL(before_run_repl = true)
      reset_repl_history()
      fixdisplayorder()

      # HACK: overloading this allows us to open remote files
      InteractiveUtils.eval(quote
        function InteractiveUtils.edit(path::AbstractString, line::Integer = 0)
          if endswith(path, ".jl")
            f = Base.find_source_file(path)
            f !== nothing && (path = f)
          end
          $(msg)("openFile", Base.abspath(path), line - 1)
        end
      end)
    end
    nothing
  end

  @require WebIO="0f1e0344-ec1d-5b48-a673-e5cf874b6c29" include("display/webio.jl")
  @require Traceur="37b6cedf-1f77-55f8-9503-c64b63398394" include("profiler/traceur.jl")
end

# basics
include("comm.jl")
include("utils.jl")
include("misc.jl")
include("display/display.jl")
include("progress.jl")
include("static/static.jl")
include("modules.jl")

include("eval.jl")
include("repl.jl")
include("workspace.jl")
include("outline.jl")
include("docs.jl")
include("completions.jl")
include("goto.jl")
include("datatip.jl")
include("formatter.jl")
include("frontend.jl")
include("debugger/debugger.jl")
include("profiler/profiler.jl")

include("precompile.jl")
_precompile_()

end # module
