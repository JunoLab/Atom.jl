using JuliaInterpreter: pc_expr, moduleof, linenumber, extract_args,
                        root, caller, whereis, get_return, nstatements, @lookup
using JuliaInterpreter
import Debugger: DebuggerState, execute_command, print_status, locinfo, eval_code
using Debugger
import ..Atom: fullpath, handle, @msg, wsitem, Inline, EvalError, Console, display_error
import Juno: Row, Tree
import REPL
using Media
using MacroTools

const chan = Ref{Union{Channel, Nothing}}()
const state = Ref{Union{DebuggerState, Nothing}}()

isdebugging() = isassigned(chan) && chan[] !== nothing

# entrypoint
function enter(mod, arg)
  quote
    let frame = $(_make_frame(mod, arg))
      $(@__MODULE__).startdebugging(frame)
    end
  end
end

function _make_frame(mod, arg)
    args = try
      extract_args(mod, arg)
    catch e
      return :(throw($e))
    end
    quote
      theargs = $(esc(args))
      frame = $(@__MODULE__).JuliaInterpreter.enter_call_expr(Expr(:call, theargs...))
      $(@__MODULE__).JuliaInterpreter.maybe_step_through_wrapper!(frame)
      $(@__MODULE__).JuliaInterpreter.maybe_next_call!(frame)
      frame
    end
end

# setup interpreter
function startdebugging(stack)
  repl = Base.active_repl
  terminal = Base.active_repl.t

  global state[] = DebuggerState(stack, repl, terminal)
  global chan[] = Channel(0)

  debugmode(true)
  if Atom.isREPL()
    # FIXME: Should get rid of the second code path (see comment in repl.jl).
    if Atom.inREPL[]
      t = @async debugprompt()
    else
      Atom.changeREPLprompt("debug> ", color="\e[38;5;166m")
    end
  end

  stepto(state[])
  res = nothing

  try
    evalscope() do
      for val in chan[]
        if val == :nextline
          execute_command(state[], Val{:n}(), "n")
        elseif val == :stepexpr
          execute_command(state[], Val{:nc}(), "nc")
        elseif val == :stepin
          execute_command(state[], Val{:s}(), "s")
        elseif val == :finish
          execute_command(state[], Val{:so}(), "so")
        elseif val isa Tuple && val[1] == :toline
          frame = Debugger.active_frame(state[])
          while locinfo(frame).line < val[2]
            execute_command(state[], Val{:n}(), "n")
            frame = Debugger.active_frame(state[])
            frame === nothing && break
          end
        else
          warn("Internal: Unknown debugger message $val.")
        end
        state[].frame === nothing && break
        stepto(state[])
      end
    end
  catch err
    if Atom.isREPL()
      display_error(stderr, err, stacktrace(catch_backtrace()))
    else
      render(Console(), EvalError(e, catch_stacktrace()))
    end
  finally
    res = state[].overall_result
    chan[] = nothing
    state[] = nothing
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
        r = Atom.JunoDebugger.interpret(line)
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
  handle(()->put!(chan[], cmd), string(cmd))
end

handle((line)->put!(chan[], (:toline, line)), "toline")

# notify the frontend that we start debugging now
debugmode(on) = @msg debugmode(on)

## Stepping

# perform step in frontend
function stepto(state::DebuggerState)
  frame = Debugger.active_frame(state)
  loc = locinfo(frame)
  if loc == nothing
    @warn "not implemented"
  else
    file, line = loc.filepath, loc.line
  end
  stepto(Atom.fullpath(string(file)), line, stepview(nextstate(state)))
end
stepto(file, line, text) = @msg stepto(file, line, text)
stepto(::Nothing) = debugmode(false)

# return expression that will be evaluated next
function nextstate(state)
  maybe_quote(x) = (isa(x, Expr) || isa(x, Symbol)) ? QuoteNode(x) : x

  frame = Debugger.active_frame(state)
  expr = pc_expr(frame)
  isa(expr, Expr) && (expr = copy(expr))
  if isexpr(expr, :(=))
      expr = expr.args[2]
  end
  if isexpr(expr, :call) || isexpr(expr, :return)
    for i in 1:length(expr.args)
      val = try
          @lookup(frame, expr.args[i])
      catch err
          err isa UndefVarError || rethrow(err)
          expr.args[i]
      end
      expr.args[i] = maybe_quote(val)
    end
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
    # @msg doneWorking()
    # unlock(Atom.evallock)
    f()
  finally
    # lock(Atom.evallock)
    # @msg working()
  end
end

## Workspace
function contexts(s::DebuggerState = state[])
  ctx = []
  trace = ""
  frame = root(s.frame)
  while frame ≠ nothing
    trace = string(trace, "/", frame.framecode.scope isa Method ?
                                frame.framecode.scope.name : "???")
    c = Dict(:context => string("Debug: ", trace), :items => localvars(frame))
    push!(ctx, c)

    frame = frame.callee
  end
  reverse(ctx)
end

function localvars(frame)
  vars = JuliaInterpreter.locals(frame)
  items = []
  for v in vars
      v.name == Symbol("#self#") && (isa(v.value, Type) || sizeof(v.value) == 0) && continue
      push!(items, wsitem(String(v.name), v.value))
  end
  return items
end

struct Undefined end
@render Inline u::Undefined span(".fade", "<undefined>")
Atom.wsicon(::Undefined) = "icon-circle-slash"

## Evaluation
function interpret(code::AbstractString, s::DebuggerState = state[])
  eval_code(Debugger.active_frame(s), code)
end
