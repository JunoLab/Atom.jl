export Debugger

const loadLock = ReentrantLock()

function __debug__()
  lock(loadLock)
  isdefined(Atom, :Debugger) && return
  @eval include(joinpath(dirname($@__FILE__), "debugger.jl"))
  unlock(loadLock)
end

handle("loadgallium") do
  __debug__()
  nothing
end

isdebugging() = isdefined(Atom, :Debugger) && Debugger.isdebugging()

for f in :[step, breakpoint].args
  @eval function $f(args...)
    __debug__()
    Debugger.$f(args...)
  end
end
