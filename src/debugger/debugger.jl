function enter(mod, ex; initial_continue = false)
  if isdebugging()
    Base.printstyled(stderr, "Can't debug while debugging.\n", color=Base.error_color())
  else
    JunoDebugger.enter(mod, ex; initial_continue = initial_continue)
  end
end

isdebugging() = JunoDebugger.isdebugging()

module JunoDebugger

using ..Atom, MacroTools, Lazy, Hiccup

include("breakpoints.jl")
include("stepper.jl")
include("repl.jl")
include("workspace.jl")
include("datatip.jl")

end # module
