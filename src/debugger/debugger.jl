function enter(mod, ex; initial_continue = false)
  JunoDebugger.enter(mod, ex; initial_continue = initial_continue)
end

isdebugging() = JunoDebugger.isdebugging()

module JunoDebugger
using ..Atom, MacroTools, Lazy, Hiccup

include("breakpoints.jl")
include("stepper.jl")

end # module
