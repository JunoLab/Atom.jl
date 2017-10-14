import ASTInterpreter2
import DebuggerFramework: DebuggerState, execute_command, print_status, locinfo, eval_code
import ..Atom: fullpath, handle, @msg, wsitem, Inline, EvalError, Console
import Juno: Row
using Media

chan = nothing
state = nothing

isdebugging() = chan ≠ nothing

# entrypoint
macro enter(arg)
  quote
    let stack = $(ASTInterpreter2._make_stack(arg))
      startdebugging(stack)
    end
  end
end

# setup interpreter
function startdebugging(stack)
  global state = DebuggerState(stack, 1, nothing, nothing, nothing, nothing, nothing)
  global chan = Channel(0)

  debugmode(true)

  stepto(state)

  try
    evalscope() do
      for val in chan
        if val in (:nextline, :stepexpr)
          val == :nextline ?
            execute_command(state, state.stack[state.level], Val{:n}(), "n") :
            execute_command(state, state.stack[state.level], Val{:se}(), "nc")
        elseif val == :stepin
          execute_command(state, state.stack[state.level], Val{:s}(), "s")
        elseif val == :finish
          execute_command(state, state.stack[state.level], Val{:finish}(), "finish")
        end
        length(state.stack) == 0 && break
        stepto(state)
      end
    end
  catch e
    ee = EvalError(e, catch_stacktrace())
    render(Console(), ee)
  finally
    chan = nothing
    state = nothing
    debugmode(false)
  end
end

# setup handlers for stepper commands
for cmd in :[nextline, stepin, stepexpr, finish].args
  handle(()->put!(chan, cmd), string(cmd))
end

# notify the frontend that we start debugging now
debugmode(on) = @msg debugmode(on)

## Stepping

# perform step in frontend
function stepto(state::DebuggerState)
  file, line = ASTInterpreter2.determine_line_and_file(state.stack[state.level])[end]
  file = Atom.fullpath(string(file))
  loc = locinfo(state.stack[state.level])
  stepto(file, loc.line, stepview(nextstate(state)))
end
stepto(file, line, text) = @msg stepto(file, line, text)
stepto(::Void) = debugmode(false)

# return expression that will be evaluated next
function nextstate(state)
  frame = state.stack[state.level]
  expr = ASTInterpreter2.pc_expr(frame, frame.pc)
  isa(expr, Expr) && (expr = copy(expr))
  if isexpr(expr, :(=))
      expr = expr.args[2]
  end
  if isexpr(expr, :call) || isexpr(expr, :return)
      expr.args = map(var -> ASTInterpreter2.lookup_var_if_var(frame, var), expr.args)
  end
  expr
end

function stepview(ex)
  # FIXME: `f` will usually be rendered to a lazy tree which needs to be registered
  render(Inline(),
    @capture(ex, f_(as__)) ? Row(f, text"(", interpose(as, text", ")..., text")") :
    @capture(ex, x_ = y_) ? Row(Text(string(x)), text" = ", y) :
    @capture(ex, return x_) ? Row(text"return ", x) :
    Text(string(ex)))
end

function evalscope(f)
  try
    @msg doneWorking()
    unlock(Atom.evallock)
    f()
  finally
    lock(Atom.evallock)
    @msg working()
  end
end

## Workspace

function contexts(s::DebuggerState = state)
  [Dict(:context => string("Debug: ", frame.meth.name), :items => localvars(frame)) for frame in state.stack]
end

function localvars(frame::ASTInterpreter2.JuliaStackFrame)
  items = []
  for i = 1:length(frame.locals)
    if !isnull(frame.locals[i])
      if frame.code.slotnames[i] == Symbol("#self#") && sizeof(get(frame.locals[i])) == 0
        continue
      end
      push!(items, wsitem(frame.code.slotnames[i], get(frame.locals[i], Undefined())))
    end
  end
  for i = 1:length(frame.sparams)
    push!(items, wsitem(frame.meth.sparam_syms[i], get(Nullable{Any}(frame.sparams[i]), Undefined())))
  end

  return items
end

type Undefined end
@render Inline u::Undefined span(".fade", "<undefined>")
Atom.wsicon(::Undefined) = "icon-circle-slash"

## Evaluation

function interpret(code::AbstractString, frame::DebuggerState = state)
  eval_code(state, state.stack[state.level], code)
end
