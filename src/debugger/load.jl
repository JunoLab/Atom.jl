function enter(mod, ex)
  !isdefined(Atom, :JunoDebugger) && @eval include(joinpath(dirname($@__FILE__), "debugger.jl"))
  Base.invokelatest(Atom.JunoDebugger.enter, mod, :($ex))
end

isdebugging() = isdefined(Atom, :JunoDebugger) && JunoDebugger.isdebugging()
