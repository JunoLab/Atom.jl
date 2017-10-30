isdebugging() = isdefined(Atom, :Debugger) && Debugger.isdebugging()

module Debugger
using ..Atom, MacroTools, ASTInterpreter2, Lazy, Hiccup

include("stepper.jl")

end # module
