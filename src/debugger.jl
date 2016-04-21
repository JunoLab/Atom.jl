module Debugger

using MacroTools, ASTInterpreter

import ASTInterpreter: Interpreter, enter_call_expr, determine_line, next_line!,
  evaluated!, finish!, step_expr
import ..Atom: fullpath, handle, @msg

export @step

line(i::Interpreter) = determine_line(i, i.next_expr[1])
file(i::Interpreter) = fullpath(string(i.linfo.def.file))

debugmode(on) = @msg debugmode(on)
stepto(file, line, text) = @msg stepto(file, line, text)
stepto(i::Interpreter) = stepto(file(i), line(i), string(i.next_expr[2]))
stepto(::Void) = debugmode(false)

interp = nothing

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

validcall(x) = @capture(x, f_(args__)) && !isa(f, Core.IntrinsicFunction)

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
  global interp = next_line!(interp) && tocall!(interp) ? interp : done(interp)
  stepto(interp)
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
  finish!(interp)
  interp = done(interp)
  stepto(interp)
end

handle("stepexpr") do
  step_expr(interp)
  stepto(interp)
end

end
