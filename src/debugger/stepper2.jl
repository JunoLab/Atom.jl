import ASTInterpreter2
import DebuggerFramework: DebuggerState, execute_command, print_status, locinfo
import ..Atom: fullpath, handle, @msg, wsitem, Inline, EvalError, Console
import Juno: Row
using Media


export @enter

macro enter(arg)
  quote
    let stack = $(ASTInterpreter2._make_stack(arg))
      startdebugging(stack)
    end
  end
end

function startdebugging(stack)
  state = DebuggerState(stack, 1, nothing, nothing, nothing, nothing, nothing)

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
          length(state.stack) == 0 && break
        end
        stepto(state)
      end
    end
  catch e
    ee = EvalError(e, catch_stacktrace())
    render(Console(), ee)
  finally
    chan = nothing
    debugmode(false)
  end
end

# setup handlers for stepper commands
for cmd in :[nextline, stepin, stepexpr, finish].args
  handle(()->put!(chan, cmd), string(cmd))
end

# notify the frontend that we start debugging now
debugmode(on) = @msg debugmode(on)

# perform step in frontend
function stepto(state::DebuggerState)
  file, line = ASTInterpreter2.determine_line_and_file(state.stack[state.level])[end]
  file = Atom.fullpath(string(file))
  loc = locinfo(state.stack[state.level])
  stepto(file, loc.line, stepview(nextstate(state)))
end
stepto(file, line, text) = @msg stepto(file, line, text)
stepto(::Void) = debugmode(false)

function nextstate(state)
  frame = state.stack[state.level]
  expr = ASTInterpreter2.pc_expr(frame, frame.pc)
  isa(expr, Expr) && (expr = copy(expr))
  if isexpr(expr, :(=))
      expr = expr.args[2]
  end
  if isexpr(expr, :call) || isexpr(expr, :return)
      expr.args = map(var->ASTInterpreter2.lookup_var_if_var(frame, var), expr.args)
  end
  expr
end

function stepview(ex)
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
