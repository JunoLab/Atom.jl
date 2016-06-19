function RunDebugIDE(in)
  global interp = in
  tocall!(in)
  debugmode(true)
  stepto(in)
  wait(cond)
  finish!(in)
  in.retval
end

# Manual Entry

export @step

function step(args...)
  global interp
  RunDebugIDE(enter_call_expr(nothing, :($(args...)())))
end

macro step(ex)
  @capture(ex, f_(args__)) || error("Syntax: @enter f(...)")
  :(step($(esc(f)), $(map(esc, args)...)))
end

# Breakpoints

using Gallium
import Gallium: stackwalk, process_lowlevel_conditionals, bps_at_location,
  Location, LocalSession, CStackFrame, JuliaStackFrame, Hooking, FileLineSource

Gallium.breakpoint_hit(hook, RC) = _breakpoint_hit(hook, RC)

# function Gallium.breakpoint_hit(hook, RC)
_breakpoint_hit = function (hook, RC)
  if !process_lowlevel_conditionals(Location(LocalSession(), hook.addr), RC)
    return
  end
  stack = stackwalk(RC; fromhook = true)[1]
  stacktop = pop!(stack)
  linfo = stacktop.linfo
  argnames = linfo.slotnames[2:linfo.nargs]
  spectypes = linfo.specTypes.parameters[2:end]
  bps = bps_at_location[Location(LocalSession(),hook.addr)]
  target_line = minimum(map(bps) do bp
    idx = findfirst(s->isa(s, FileLineSource), bp.sources)
    idx != 0 ? bp.sources[idx].line : linfo.def.line
  end)
  conditions = reduce(vcat,map(bp->bp.conditions, bps))
  thunk = Expr(:->,Expr(:tuple,argnames...),Expr(:block,
    :(linfo = $(Expr(:quote, linfo))),
    :((loctree, code) = ASTInterpreter.reparse_meth(linfo)),
    :(__env = ASTInterpreter.prepare_locals(linfo.def.lambda_template)),
    :(copy!(__env.sparams, linfo.sparam_vals)),
    :(__env.locals[1] = Nullable{Any}()),
    [ :(__env.locals[$i + 1] = Nullable{Any}($(argnames[i]))) for i = 1:length(argnames) ]...,
    :(interp = ASTInterpreter.enter(linfo,__env,
      $(collect(filter(x->!isa(x,CStackFrame),stack)));
        loctree = loctree, code = code)),
    (target_line != linfo.def.line ?
      :(ASTInterpreter.advance_to_line(interp, $target_line)) :
      :(nothing)),
    :((isempty($conditions) ||
      any(c->Gallium.matches_condition(interp,c),$conditions)) &&
      Atom.Debugger.RunDebugIDE(interp)),
    :(ASTInterpreter.finish!(interp)),
    :(return interp.retval::$(linfo.rettype))))
  f = eval(thunk)
  faddr = Hooking.get_function_addr(f, Tuple{spectypes...})
  Hooking.Deopt(faddr)
end
