function enter(mod, ex)
  !isdefined(Atom, :JunoDebugger) && @eval include(joinpath($@__DIR__, "debugger.jl"))
  Base.invokelatest(Atom.JunoDebugger.enter, mod, :($ex))
end

isdebugging() = isdefined(Atom, :JunoDebugger) && JunoDebugger.isdebugging()
