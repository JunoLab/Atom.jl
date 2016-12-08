import ASTInterpreter: Interpreter, enter_call_expr, determine_line_and_file, next_line!,
  evaluated!, finish!, step_expr, idx_stack

import ..Atom: fullpath, handle, @msg, wsitem, Inline
using Media

function fileline(i::Interpreter)
  file, line = determine_line_and_file(i, idx_stack(i))[end]
  Atom.fullpath(string(file)), line
end

debugmode(on) = @msg debugmode(on)
stepto(file, line, text) = @msg stepto(file, line, text)
stepto(i::Interpreter) = stepto(fileline(i)..., stepview(i.next_expr[2]))
stepto(::Void) = debugmode(false)

function stepview(ex)
  @capture(ex, f_(as__)) || return render(Inline(), Text(string(ex)))
  render(Inline(), span(c(render(Inline(), f),
                          "(",
                          interpose([render(Inline(), a) for a in as], ", ")...,
                          ")")))
end

global interp = nothing
global chan = nothing
isdebugging() = chan ≠ nothing

framedone(interp) = isexpr(interp.next_expr[2], :return)
interpdone(interp) = framedone(interp) && interp.stack[1] == interp

validcall(x) =
  @capture(x, f_(args__)) &&
  !isa(f, Core.IntrinsicFunction) &&
  f ∉ [tuple, getfield]

function skip!(interp)
  while !(validcall(interp.next_expr[2]) || isexpr(interp.next_expr[2], :return, :(=)))
    step_expr(interp) || return false
  end
  return true
end

function endframe!(interp)
  finish!(interp)
  stack, val = interp.stack, interp.retval
  stack = filter(x -> isa(x, Interpreter), stack)
  if stack[1] == interp
    return interp
  else
    i = findfirst(interp.stack, interp)
    resize!(interp.stack, i-1)
    interp = interp.stack[end]
    evaluated!(interp, val)
    skip!(interp)
    return interp
  end
end

function RunDebugIDE(i)
  global interp = i
  global chan = Channel()
  @schedule begin
    skip!(interp)
    debugmode(true)
    stepto(interp)
    for val in chan
      if val in (:nextline, :stepexpr)
        interpdone(interp) && continue
        step = val == :nextline ? next_line! : step_expr
        framedone(interp) ? (interp = endframe!(interp)) :
          (step(interp) && skip!(interp))
      elseif val == :stepin
        isexpr(interp.next_expr[2], :call) || continue
        next = enter_call_expr(interp, interp.next_expr[2])
        if next ≠ nothing
          interp = next
          skip!(interp)
        end
      elseif val == :finish
        finish!(interp)
        interpdone(interp) && break
        interp = endframe!(interp)
      end
      stepto(interp)
    end
    chan = nothing
    interp = nothing
    debugmode(false)
  end
end

for cmd in :[nextline, stepin, stepexpr, finish].args
  handle(()->put!(chan, cmd), string(cmd))
end

contexts(i::Interpreter = interp) =
  reverse!([d(:context => i.linfo.def.name, :items => context(i)) for i in i.stack])

import Gallium: JuliaStackFrame

type Undefined end
@render Inline u::Undefined span(".fade", "<undefined>")
Atom.wsicon(::Undefined) = "icon-circle-slash"

function context(i::Union{Interpreter,JuliaStackFrame})
  items = []
  for (k, v) in zip(i.linfo.sparam_syms, i.env.sparams)
    push!(items, wsitem(k, v))
  end
  isdefined(i.linfo, :slotnames) || return items
  for (k, v) in zip(i.linfo.slotnames, i.env.locals)
    k in (Symbol("#self#"), Symbol("#unused#")) && continue
    push!(items, wsitem(k, isnull(v) ? Undefined() : get(v)))
  end
  return items
end

context(i) = []

function interpret(code::AbstractString, i::Interpreter = interp)
  code = parse(code)
  ok, result = ASTInterpreter.eval_in_interp(i, code)
  return ok ? result : Atom.EvalError(result)
end
