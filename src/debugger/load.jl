export Debugger

function __debug__()
  isdefined(Atom, :Debugger) && return
  # only require the debugger on 0.5.x for now and we aren't on x86 Windows
  if VERSION.minor == 5 && !(Sys.WORD_SIZE == 32 && is_windows())
    @eval include(joinpath(dirname($@__FILE__), "debugger.jl"))
  end
end

isdebugging() = isdefined(:Debugger) && Debugger.isdebugging()

for f in :[step, breakpoint].args
  @eval function $f(args...)
    __debug__()
    Debugger.$f(args...)
  end
end
