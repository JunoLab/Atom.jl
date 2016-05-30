module Debugger

using MacroTools, ASTInterpreter, Lazy, Hiccup

import ASTInterpreter: Interpreter, enter_call_expr, determine_line_and_file, next_line!,
  evaluated!, finish!, step_expr
using ..Atom
import ..Atom: fullpath, handle, @msg, @run, wsitem, render, Inline

export @step

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

isdebugging() = interp ≠ nothing

function step(args...)
  global interp
  # interp == nothing || error("Already stepping!")
  interp = enter_call_expr(nothing, :($(args...)()))
  tocall!(interp)
  debugmode(true)
  stepto(interp)
  return
end

macro step(ex)
  @capture(ex, f_(args__)) || error("Syntax: @enter f(...)")
  :(step($(esc(f)), $(map(esc, args)...)))
end

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

function done(interp)
  stack, val = interp.stack, interp.retval
  if stack[1] == interp
    debugmode(false)
    interp = nothing
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
  global interp = @run next_line!(interp) && tocall!(interp) ? interp : done(interp)
  stepto(interp)
end

handle("stepin") do
  global interp
  isexpr(interp.next_expr[2], :call) || return
  new = enter_call_expr(interp, interp.next_expr[2])
  if new ≠ nothing
    interp = new
    @run tocall!(interp)
    stepto(interp)
  end
end

handle("finish") do
  global interp
  @run finish!(interp)
  interp = done(interp)
  stepto(interp)
end

handle("stepexpr") do
  @run step_expr(interp)
  stepto(interp)
end

contexts(i::Interpreter = interp) =
  reverse!([d(:context => i.linfo.def.name, :items => context(i)) for i in i.stack])

function context(i::Interpreter)
  items = []
  for (k, v) in zip(i.linfo.sparam_syms, i.env.sparams)
    push!(items, wsitem(k, v))
  end
  for (k, v) in zip(i.linfo.slotnames, i.env.locals)
    # TODO: explicit nulls
    k in (symbol("#self#"), symbol("#unused#")) && continue
    push!(items, wsitem(k, isnull(v) ? v : get(v)))
  end
  return items
end

function interpret(code::AbstractString, i::Interpreter = interp)
  code = parse(code)
  ok, result = ASTInterpreter.eval_in_interp(i, code)
  return ok ? result : Atom.EvalError(result)
end

end
