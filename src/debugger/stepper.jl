import ASTInterpreter2
import DebuggerFramework: DebuggerState, execute_command, print_status, locinfo, eval_code, dummy_state
import ..Atom: fullpath, handle, @msg, wsitem, Inline, EvalError, Console, display_error
import Juno: Row, Tree
import REPL
using Media
using MacroTools

chan = nothing
state = nothing

isdebugging() = chan ≠ nothing

# entrypoint
function enter(mod, arg)
  quote
    let stack = $(_make_stack(mod, arg))
      $(@__MODULE__).startdebugging(stack)
    end
  end
end

function _make_stack(mod, arg)
    args = try
        ASTInterpreter2.extract_args(mod, arg)
    catch e
        return :(throw($e))
    end
    quote
        theargs = $(esc(args))
        stack = [$(@__MODULE__).ASTInterpreter2.enter_call_expr(Expr(:call,theargs...))]
        $(@__MODULE__).ASTInterpreter2.maybe_step_through_wrapper!(stack)
        stack[1] = $(@__MODULE__).ASTInterpreter2.JuliaStackFrame(stack[1], $(@__MODULE__).ASTInterpreter2.maybe_next_call!(stack[1]))
        stack
    end
end

# setup interpreter
function startdebugging(stack)
  global state = dummy_state(stack)
  global chan = Channel(0)

  debugmode(true)

  if Atom.isREPL()
    # FIXME: Should get rid of the second code path (see comment in repl.jl).
    if Atom.inREPL[]
      t = @async debugprompt()
    else
      Atom.changeREPLprompt("debug> ", color="\e[38;5;166m")
    end
  end

  stepto(state)
  res = nothing

  try
    evalscope() do
      for val in chan
        if val == :nextline
          execute_command(state, state.stack[state.level], Val{:n}(), "n")
        elseif val == :stepexpr
          execute_command(state, state.stack[state.level], Val{:nc}(), "nc")
        elseif val == :stepin
          execute_command(state, state.stack[state.level], Val{:s}(), "s")
        elseif val == :finish
          execute_command(state, state.stack[state.level], Val{:finish}(), "finish")
        elseif typeof(val) <: Tuple && val[1] == :toline
          while locinfo(state.stack[state.level]).line < val[2]
            execute_command(state, state.stack[state.level], Val{:n}(), "n")
            length(state.stack) == 0 && break
          end
        else
          warn("Internal: Unknown debugger message $val.")
        end
        length(state.stack) == 0 && break
        stepto(state)
      end
    end
  catch err
    if Atom.isREPL()
      display_error(stderr, err, stacktrace(catch_backtrace()))
    else
      render(Console(), EvalError(e, catch_stacktrace()))
    end
  finally
    res = state.overall_result
    chan = nothing
    state = nothing
    debugmode(false)

    if Atom.isREPL()
      if Atom.inREPL[]
        istaskdone(t) || schedule(t, InterruptException(); error=true)
        print("\r                        \r")
      else
        print("\r                        \r")
        Atom.changeREPLprompt(Atom.juliaprompt, color = :green, write = false)
      end
    end
  end
  res
end

using REPL
function debugprompt()
  try
    panel = REPL.LineEdit.Prompt("debug> ";
              prompt_prefix="\e[38;5;166m",
              prompt_suffix="\e[0m",
              on_enter = s -> true)

    panel.on_done = (s, buf, ok) -> begin
      Atom.msg("working")

      line = String(take!(buf))

      isempty(line) && return true

      if !ok
        REPL.LineEdit.transition(s, :abort)
        REPL.LineEdit.reset_state(s)
        return false
      end

      try
        r = Atom.Debugger.interpret(line)
        r ≠ nothing && display(r)
        println()
      catch err
        display_error(stderr, err, stacktrace(catch_backtrace()))
      end

      Atom.msg("doneWorking")
      Atom.msg("updateWorkspace")

      return true
    end

    REPL.run_interface(Base.active_repl.t, REPL.LineEdit.ModalInterface([panel]))
  catch e
    e isa InterruptException || rethrow(e)
  end
end

# setup handlers for stepper commands
for cmd in [:nextline, :stepin, :stepexpr, :finish]
  handle(()->put!(chan, cmd), string(cmd))
end

handle((line)->put!(chan, (:toline, line)), "toline")

# notify the frontend that we start debugging now
debugmode(on) = @msg debugmode(on)

## Stepping

# perform step in frontend
function stepto(state::DebuggerState)
  frame = state.stack[state.level]
  loc = locinfo(frame)
  if loc == nothing
    file, line = ASTInterpreter2.determine_line_and_file(frame, frame.pc.next_stmt)[end]
  else
    file, line = loc.filepath, loc.line
  end
  stepto(Atom.fullpath(string(file)), line, stepview(nextstate(state)))
end
stepto(file, line, text) = @msg stepto(file, line, text)
stepto(::Nothing) = debugmode(false)

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
  out = if @capture(ex, f_(as__))
    Row(span(".syntax--support.syntax--function", string(typeof(f).name.mt.name)),
             text"(", interpose(as, text", ")..., text")")
  elseif @capture(ex, x_ = y_)
    Row(Text(string(x)), text" = ", y)
  elseif @capture(ex, return x_)
    Row(span(".syntax--support.syntax--keyword", "return "), x)
  else
    Text(string(ex))
  end
  render(Inline(), out)
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
  cxt = []
  trace = ""
  for frame in reverse(state.stack)
    trace = string(trace, "/", frame.meth.name)
    c = Dict(:context => string("Debug: ", trace), :items => localvars(frame))
    push!(cxt, c)
  end
  cxt
end

function localvars(frame::ASTInterpreter2.JuliaStackFrame)
  items = []
  for i = 1:length(frame.locals)
    if frame.locals[i] !== nothing
      val = something(frame.locals[i])
      if frame.code.slotnames[i] == Symbol("#self#") && (isa(val, Type) || sizeof(val) == 0)
        continue
      end
      push!(items, wsitem(frame.code.slotnames[i], val))
    end
  end
  for i = 1:length(frame.sparams)
    push!(items, wsitem(frame.meth.sparam_syms[i], something(frame.sparams[i], Undefined())))
  end
  return items
end

struct Undefined end
@render Inline u::Undefined span(".fade", "<undefined>")
Atom.wsicon(::Undefined) = "icon-circle-slash"

## Evaluation

function interpret(code::AbstractString, frame::DebuggerState = state)
  eval_code(state, state.stack[state.level], code)
end
