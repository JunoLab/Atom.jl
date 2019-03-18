isdebugging() = isdefined(Atom, :JunoDebugger) && isdefined(JunoDebugger, :isdebugging) && Atom.JunoDebugger.isdebugging()

module JunoDebugger
using ..Atom, MacroTools, Lazy, Hiccup

include("stepper.jl")

end # module
