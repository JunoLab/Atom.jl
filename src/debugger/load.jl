function enter(ex)
  # !isdefined(Atom, :Debugger) && @eval include(joinpath(dirname($@__FILE__), "debugger.jl"))
  # Base.invokelatest(Atom.Debugger.enter, :($ex))
end

isdebugging() = false # isdefined(Atom, :Debugger) && Debugger.isdebugging()
