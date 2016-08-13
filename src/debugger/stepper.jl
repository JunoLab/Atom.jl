import ASTInterpreter: Interpreter, enter_call_expr, determine_line_and_file, next_line!,
  evaluated!, finish!, step_expr

import ..Atom: fullpath, handle, @msg, wsitem, Inline
using Media

function fileline(i::Interpreter)
  file, line = determine_line_and_file(i, i.next_expr[1])[end]
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

interp = nothing

const cond = Condition()

isdebugging() = interp ≠ nothing

validcall(x) =
  @capture(x, f_(args__)) &&
  !isa(f, Core.IntrinsicFunction) &&
  f ∉ [tuple, getfield]

function tocall!(interp)
  while !validcall(interp.next_expr[2])
    step_expr(interp) || return false
  end
  return true
end

function err(e)
  debugmode(false)
  interp = nothing
  notify(cond, e, error = true)
end

macro errs(ex)
  :(try
      $(esc(ex))
    catch e
      err(e)
    end)
end

function done(interp)
  stack, val = interp.stack, interp.retval
  stack = filter(x -> isa(x, Interpreter), stack)
  if stack[1] == interp
    debugmode(false)
    interp = nothing
    notify(cond)
  else
    i = findfirst(stack, interp)
    resize!(stack, i-1)
    interp = stack[end]
    evaluated!(interp, val)
    tocall!(interp)
  end
  return interp
end

handle("nextline") do
  @errs begin
    global interp = next_line!(interp) && tocall!(interp) ? interp : done(interp)
    stepto(interp)
  end
end

handle("stepin") do
  global interp
  isexpr(interp.next_expr[2], :call) || return
  new = enter_call_expr(interp, interp.next_expr[2])
  if new ≠ nothing
    interp = new
    tocall!(interp)
    stepto(interp)
  end
end

handle("finish") do
  global interp
  @errs begin
    finish!(interp)
    interp = done(interp)
    stepto(interp)
  end
end

handle("stepexpr") do
  @errs begin
    step_expr(interp)
    stepto(interp)
  end
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
