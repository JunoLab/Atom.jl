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
    instantiate_repl_keybindings(repl)
  end

  # HACK: overwrite Pkg mode `on_done` function after Pkg mode has been Initialized
  f = (repl) -> begin
    i = findfirst(Base.active_repl.interface.modes) do mode
      mode isa LineEdit.Prompt &&
      isdefined(mode, :on_done) &&
      let ms = collect(methods(mode.on_done))
        length(ms) > 0 && parentmodule(ms[1].module) == Pkg
      end
    end
    i === nothing && return # if no Pkg mode somehow
    pkg_mode = Base.active_repl.interface.modes[i]
    pkg_mode.on_done = let original = pkg_mode.on_done
      (s, buf, ok) -> begin
        original(s, buf, ok)
        update_project()
      end
    end
  end
  push!(Base.repl_hooks, f)

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

    update_project()

    nothing
  end

  @require WebIO="0f1e0344-ec1d-5b48-a673-e5cf874b6c29" include("display/webio.jl")
  @require Traceur="37b6cedf-1f77-55f8-9503-c64b63398394" include("profiler/traceur.jl")
end

# basics
include("comm.jl")
include("utils.jl")
include("misc.jl")
include("environments.jl")
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
