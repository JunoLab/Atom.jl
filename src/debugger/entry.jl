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
  @capture(ex, f_(args__)) || error("Syntax: @step f(...)")
  :(step($(esc(f)), $(map(esc, args)...)))
end

# Breakpoints

using Gallium
import Gallium: stackwalk, process_lowlevel_conditionals, bps_at_location,
  Location, LocalSession, CStackFrame, JuliaStackFrame, Hooking, FileLineSource

export breakpoint

# Gallium.breakpoint_hit(hook, RC) = _breakpoint_hit(hook, RC)
function breakpoint(args...)
  Gallium.breakpoint(args...)
  return
end

# function Gallium.breakpoint_hit(hook, RC)
_breakpoint_hit = function (hook, RC)
  if !process_lowlevel_conditionals(Location(LocalSession(), hook.addr), RC)
    return
  end
  stack = stackwalk(RC; fromhook = true)[1]
  stacktop = pop!(stack)
  linfo = stacktop.linfo
  fT = linfo.def.sig.parameters[1]
  def_linfo = linfo.def.lambda_template
  argnames = [Symbol("#target_self#");def_linfo.slotnames[2:def_linfo.nargs]]
  spectypes = [fT;linfo.specTypes.parameters[2:end]...]
  bps = bps_at_location[Location(LocalSession(),hook.addr)]
  target_line = minimum(map(bps) do bp
      idx = findfirst(s->isa(s, FileLineSource), bp.sources)
      idx != 0 ? bp.sources[idx].line : def_linfo.def.line
  end)
  conditions = reduce(vcat,map(bp->bp.conditions, bps))
  thunk = Expr(:->,Expr(:tuple,map(x->Expr(:(::),x[1],x[2]),zip(argnames,spectypes))...),Expr(:block,
    :(linfo = $(quot(linfo))),
    :((loctree, code) = ASTInterpreter.reparse_meth(linfo)),
    :(__env = ASTInterpreter.prepare_locals(linfo.def.lambda_template)),
    :(copy!(__env.sparams, linfo.sparam_vals)),
    [ :(__env.locals[$i] = Nullable{Any}($(argnames[i]))) for i = 1:length(argnames) ]...,
    :(interp = ASTInterpreter.enter(linfo,__env,
      $(collect(filter(x->!isa(x,CStackFrame),stack)));
        loctree = loctree, code = code)),
    (target_line != linfo.def.line ?
      :(ASTInterpreter.advance_to_line(interp, $target_line)) :
      :(nothing)),
    # :(tty_state = Gallium.suspend_other_tasks()),
    :((isempty($conditions) ||
      any(c->Gallium.matches_condition(interp,c),$conditions)) &&
      Atom.Debugger.RunDebugIDE(interp)),
    # :(Gallium.restore_other_tasks(tty_state)),
    :(ASTInterpreter.finish!(interp)),
    :(return interp.retval::$(linfo.rettype))))
  f = eval(thunk)
  t = Tuple{spectypes...}
  faddr = Hooking.get_function_addr(f, t)
  Hooking.Deopt(faddr)
end
