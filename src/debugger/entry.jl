# Manual Entry

function step(args...)
  @schedule RunDebugIDE(enter_call_expr(nothing, :($(args...)())))
  return
end

# Breakpoints

using Gallium
import Gallium: stackwalk, process_lowlevel_conditionals, bps_at_location,
  Location, LocalSession, CStackFrame, JuliaStackFrame, Hooking, FileLineSource

import Base.Meta: quot

import Atom: basepath

bps = Dict()

using Juno

handle("clearbps") do
  for (k, bp) in bps
    Gallium.remove(bp)
    delete!(bps, k)
  end
end

Juno.@render Juno.Inline bp::Gallium.Breakpoint begin
  if isempty(bp.active_locations) && isempty(bp.inactive_locations) && isempty(bp.sources)
    Text("Empty Breakpoint.")
  else
    if !isempty(bp.sources)
      Juno.Row(Text("Breakpoint at "), Atom.baselink(string(bp.sources[1].fname), bp.sources[1].line))
    else
      sprint(show, bp)
    end
  end
end

handle("getbps") do
  ret = []
  for (k, bp) in bps
    push!(ret, Dict(:view => render(Juno.Inline(), bp)))
  end
  ret
end

handle("addsourcebp") do file, line
  k = hash((file, line))

  haskey(bps, k) && (return Dict(:msg => "ERR:bpalreadyexists")

  contains(file, basepath("")) && (file = basename(file))
  bps[k] = Gallium.breakpoint(file, line)
  return Dict(:msg => "bpset")
end

handle("removesourcebp") do file, line
  k = hash((file, line))

  !haskey(bps, k) && (return Dict(:msg => "ERR:bpdoesnotexist")

  Gallium.remove(bps[k])
  delete!(bps, k)
  return Dict(:msg => "bpremoved")
end

function breakpoint(args...)
  Gallium.breakpoint(args...)
  return
end

Gallium.breakpoint_hit(hook, RC) = _breakpoint_hit(hook, RC)

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
      Atom.Debugger.RunDebugIDE(interp, true)),
    # :(Gallium.restore_other_tasks(tty_state)),
    :(ASTInterpreter.finish!(interp)),
    :(return interp.retval::$(linfo.rettype))))
  f = eval(thunk)
  t = Tuple{spectypes...}
  faddr = Hooking.get_function_addr(f, t)
  Hooking.Deopt(faddr)
end
