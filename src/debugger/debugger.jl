function enter(mod, ex)
  JunoDebugger.enter(mod, ex)
end

isdebugging() = JunoDebugger.isdebugging()

module JunoDebugger
using ..Atom, MacroTools, Lazy, Hiccup

include("breakpoints.jl")
include("stepper.jl")

end # module
