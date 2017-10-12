export Debugger

include("debugger.jl")


function __debug__()
  isdefined(Atom, :Debugger) && return
  lock(evallock)
  @eval include(joinpath(dirname($@__FILE__), "debugger.jl"))
  unlock(evallock)
end

handle("loadgallium") do
  __debug__()
  return
end

isdebugging() = isdefined(Atom, :Debugger) && Debugger.isdebugging()

for f in :[step, breakpoint].args
  @eval function $f(args...)
    __debug__()
    Debugger.$f(args...)
  end
end
