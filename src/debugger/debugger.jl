isdebugging() = isdefined(Atom, :Debugger) && isdefined(Debugger, :isdebugging) && Atom.Debugger.isdebugging()

module Debugger
using ..Atom, MacroTools, ASTInterpreter2, Lazy, Hiccup

include("stepper.jl")

end # module
