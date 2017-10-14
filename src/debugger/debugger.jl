isdebugging() = Debugger.isdebugging()

module Debugger
using ..Atom, MacroTools, ASTInterpreter2, Lazy, Hiccup

include("stepper.jl")

end # module
