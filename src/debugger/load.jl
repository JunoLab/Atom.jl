function enter(ex)
  !isdefined(Atom, :Debugger) && @eval include(joinpath(dirname($@__FILE__), "debugger.jl"))
  Atom.Debugger.enter(ex)
end

isdebugging() = isdefined(Atom, :Debugger) && Debugger.isdebugging()
