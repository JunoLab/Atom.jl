function enter(mod, ex)
  !isdefined(Atom, :Debugger) && @eval include(joinpath(dirname($@__FILE__), "debugger.jl"))
  Base.invokelatest(Atom.Debugger.enter, mod, :($ex))
end

isdebugging() = isdefined(Atom, :Debugger) && Debugger.isdebugging()
